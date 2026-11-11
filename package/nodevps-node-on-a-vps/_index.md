---
code: nodevps
title: "Hub Node on a VPS (KVM Host Kit)"
description: "Run one or more ZeroBias Hub Node VMs on a rented VPS with nested KVM, using a ready-made, re-runnable host kit."
type: "kb"
application: learning_center
kbType: guide
keywords:
  - connection
  - node
  - hub
  - vps
  - kvm
  - libvirt
  - qcow2
  - nested virtualization
  - ubuntu
relatesTo: []
date: '2026-11-11T00:00:00.000Z'
lastmod: '2026-11-11T00:00:00.000Z'
draft: false
images: []
weight: 110
---

## Background

A ZeroBias Hub Node runs integration modules close to the systems they connect
to. The node ships as a VM appliance. The appliance contains the operating
system, Docker and the node services, and it updates itself.

Sometimes you do not have a hypervisor to run the appliance on. A rented
virtual private server (VPS) can do the job, but a VPS is itself a VM. To run
the node appliance inside it, the VPS must support **nested virtualization**:

```
provider hardware
└── your VPS  (L1 guest, Ubuntu + KVM/libvirt)        <- this kit configures it
    ├── node-1  (L2 guest, ZeroBias node appliance)   <- register in ZeroBias
    └── node-2  (L2 guest, ...)
        └── module containers (plain Docker, no more virtualization)
```

This article shows how to build that host with **node-kvm-host**, a small kit of
shell scripts. ZeroBias uses the same kit (internally called `waide-vm`) to run
its own development nodes. One 12 vCPU / 92 GB VPS runs two nodes. Each step in
the kit encodes a lesson from that host. The [Troubleshooting](#troubleshooting)
section explains each lesson.

For general information about nodes (architecture, registration, network
requirements) read
[Connection Node Deployment](https://cdn.zerobias.com/kb/kb251/index.html).

## Requirements

### The VPS

| Item | Minimum | Notes |
|---|---|---|
| Nested virtualization | Required | The VPS must show the `vmx` (Intel) or `svm` (AMD) CPU flag and have `/dev/kvm`. Ask the provider before you buy. Many providers turn it off by default. |
| Operating system | Ubuntu 22.04 LTS or later | The kit uses `apt`, `systemd` and Ubuntu package names. |
| vCPU | 4 + 2 per node | A node can use all of its vCPUs. Several nodes can share host vCPUs. One node must never have more vCPUs than the host. |
| RAM | 4 GB for the host + the RAM of all nodes | VPS providers rarely allow memory oversubscription. Keep the total node RAM below the host RAM. |
| Disk | 30 GB + the disk of all nodes | Node disks are thin. They use host space only as the node writes data. |
| Network | Outbound internet | The node connects out to ZeroBias. You do not need any inbound port except SSH. |
| Access | A user with `sudo` | The scripts run privileged steps through `sudo` themselves. |

Check for nested virtualization on an existing VPS:

```bash
grep -cE 'vmx|svm' /proc/cpuinfo   # more than 0 = supported
ls -l /dev/kvm                     # must exist
```

### Node sizing

A node that only routes module traffic needs little. A node that runs many
modules, or heavy ones, needs more. Start with these values and adjust:

| Use | vCPU | RAM | Disk |
|---|---|---|---|
| Light (a few modules) | 2 | 4 GB | 50 GB |
| Typical | 4 | 8 GB | 100 GB |
| Heavy (many modules or development workloads) | 8–10 | 32 GB | 400 GB |

## Get the kit

The kit is in the public `zerobias-org/kb` repository, next to this article.

**Option 1 (recommended): clone only the kit with git.** This keeps the
executable flags on the scripts.

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/zerobias-org/kb.git zb-kb
cd zb-kb
git sparse-checkout set package/nodevps-node-on-a-vps/node-kvm-host
mv package/nodevps-node-on-a-vps/node-kvm-host ~/node-kvm-host
cd ~ && rm -rf zb-kb
cd ~/node-kvm-host
```

**Option 2: download the files one by one.** The [Downloads](#downloads)
section lists every file. After the download, make the scripts executable:

```bash
chmod +x bootstrap.sh host/*.sh bin/*.sh
```

### Kit layout

```
config.env        host settings: storage pool, network, image version, swap sizes
nodes/*.env       one file per node VM (name, vCPU, RAM, disk, VNC port)
bootstrap.sh      runs host/NN-*.sh in order (all, or by number)
host/
  00-preflight.sh      read-only checks (vmx/svm, /dev/kvm, resources)
  10-kvm.sh            qemu/libvirt/virtinst/ksmtuned/zram-tools, libvirt-guests, groups
  20-memory.sh         memory safety net: zram + disk swap, sysctls, KSM
  30-libvirt.sh        NAT network + storage pool
  40-image.sh          download + sha256-verify the node qcow2 from the ZeroBias CDN
  50-nodes.sh          create one VM per nodes/*.env (create-only, never redefines)
  60-crash-capture.sh  OPTIONAL: no-kvmapf, qxl blacklist, kdump, panic sysctls, sysstat
bin/
  node-list.sh      nodes + memory picture (RSS, KSM savings, swap)
  node-console.sh   serial console (Ctrl+] to detach)
  node-vnc.sh       VGA console over VNC (prints the SSH tunnel command)
  node-rename.sh    rename a node: VM + disk + nodes/*.env
  node-destroy.sh   remove a node VM + its disk (asks for confirmation)
lib/common.sh     shared helpers
```

Every `host/` step is **idempotent**. A step checks the current state and
changes only what is different. You can re-run any step, or all of them, at any
time.

## Configure

### Host settings: `config.env`

The defaults work on most hosts. Change the swap file size to suit your disk.

```bash
POOL_NAME=zbnodes                          # libvirt storage pool for node disks
POOL_DIR=/var/lib/libvirt/images/zbnodes   # base images go in $POOL_DIR/base
LIBVIRT_NET=default                        # libvirt NAT network (outbound only)
IMAGE_MANIFEST_URL=https://cdn.zerobias.com/distributions/vm/proxmox/manifest.json
IMAGE_VERSION=latest                       # or pin, for example 1.7.9
ZRAM_PERCENT=25                            # compressed RAM swap, % of host RAM
SWAPFILE=/swap.img
SWAPFILE_SIZE=64G                          # last-resort disk swap
```

`IMAGE_VERSION=latest` selects the newest stable x64 image in the manifest. The
`proxmox` target in the manifest is the node appliance as a QCOW2 disk. KVM
uses QCOW2 natively, so the kit needs no conversion.

### Nodes: `nodes/*.env`

Each file in `nodes/` defines one node VM. The kit includes one example,
`nodes/node-1.env`:

```bash
NAME=node-1
VCPUS=4
MEMORY_GB=8
DISK_GB=100
VNC_PORT=5901
# NODE_IMAGE_VERSION=1.7.9   # optional: pin this node's base image
```

To plan more nodes, copy the file (for example to `nodes/node-2.env`). Give each
node a unique `NAME` and a unique `VNC_PORT`.

## Build the host

Run all steps:

```bash
./bootstrap.sh
```

Other forms:

```bash
./bootstrap.sh --list     # show the steps
./bootstrap.sh 20         # run only step 20 (memory tuning)
./bootstrap.sh 40 50      # get a new image, then create any new nodes
```

Step 10 adds your user to the `kvm` and `libvirt` groups. Log out and log in
again once, so that the `bin/` helpers work without `sudo`.

### What each step does

**00 — preflight.** The step reads the system and changes nothing. It stops if
the CPU flag `vmx`/`svm` or `/dev/kvm` is missing.

**10 — KVM and libvirt.** The step installs QEMU, libvirt, `virt-install`,
`ksmtuned`, `zram-tools` and the disk tools for step 50. It sets
`libvirt-guests` to shut nodes down cleanly when the host reboots.

**20 — memory.** Nodes have spiky memory use. This step gives the host a safety
net, so that a spike does not make the kernel kill a node:

- **zram** (zstd, 25% of RAM, priority 100): compressed swap in RAM, used first.
- **Disk swap file** (priority 10): the last resort before the out-of-memory killer.
- **KSM**: merges identical memory pages across nodes. All nodes run the same
  appliance and containers, so the savings are real. `ksmtuned` scans only when
  free memory is low.
- **sysctls**: early swapping into zram, and earlier background reclaim.

The kit does not use hugepages. The host cannot swap, merge or reclaim them.

**30 — libvirt network and pool.** The step starts the `default` NAT network and
creates the storage pool. Nodes need only outbound access: the node opens the
connection to ZeroBias.

**40 — image.** The step downloads the node appliance from the ZeroBias CDN and
verifies its SHA-256 checksum. It keeps each version read-only in
`$POOL_DIR/base/`.

**50 — nodes.** For each new `nodes/*.env`, the step:

1. Creates a thin QCOW2 overlay disk on the base image.
2. Grows the root partition offline, before the first boot (see
   [Troubleshooting](#troubleshooting)).
3. Creates the VM with `virt-install`. The VM uses `host-passthrough` CPU, a
   virtio balloon with free page reporting (the node returns free memory to the
   host), `discard=unmap` (TRIM shrinks the disk), a serial console and VGA on
   VNC bound to `127.0.0.1`.
4. Sets the VM to start automatically, and starts it.

Step 50 **only creates**. It never redefines a VM or touches the disk of an
existing node, because the node disk holds the registered node identity. For an
existing node, the step only reports differences from its `.env` file.

**60 — crash capture (optional).** Run this step if the host reboots or freezes
with nothing in its logs. See [Troubleshooting](#troubleshooting).

## Register the node

First boot takes about 2 minutes. The node then updates itself to the newest
release (see [Troubleshooting](#troubleshooting)). When it is ready, the node
console shows a text user interface (TUI) with the registration flow.

1. In ZeroBias, create a node registration and copy the registration code. See
   [Connection Node Deployment](https://cdn.zerobias.com/kb/kb251/index.html).
2. Open the node console on the host:

   ```bash
   bin/node-console.sh node-1     # serial console. Press Ctrl+] to detach.
   ```

   Or use VNC. VNC listens on `127.0.0.1` only, because a VPS has a public IP
   address. `bin/node-vnc.sh node-1` prints the SSH tunnel command to run on
   your workstation:

   ```bash
   ssh -N -L 5901:127.0.0.1:5901 <you>@<vps-host>
   # then connect a VNC client to localhost:5901
   ```

3. Enter the registration code in the TUI.

Do not store registration codes in the kit folder. Enter them only on the node
console.

## Operate

| Task | Command |
|---|---|
| List nodes, memory, KSM savings and swap | `bin/node-list.sh` |
| Add a node | Add `nodes/node-2.env`, then `./bootstrap.sh 50`, then register it |
| Resize a node | Edit its `.env`, then `virsh shutdown <node>`, `virsh setmaxmem <node> 16G --config`, `virsh setmem <node> 16G --config`, `virsh setvcpus <node> 6 --config --maximum`, `virsh setvcpus <node> 6 --config`, `virsh start <node>` |
| Use a newer image for new nodes | `./bootstrap.sh 40 50` |
| Rename a node | `bin/node-rename.sh <old> <new>` (shuts the node down, renames VM + disk + `.env`, starts it) |
| Remove a node | `bin/node-destroy.sh <node>`, then delete the node in ZeroBias |
| Re-apply all host settings | `./bootstrap.sh` |

Use `virsh --connect qemu:///system` for manual `virsh` commands, or set
`LIBVIRT_DEFAULT_URI=qemu:///system`.

**Do not delete a base image that a node still uses.** Node disks are overlays
on the base image. If you delete the base image, every node on it stops working.
Check a disk with:

```bash
qemu-img info --backing-chain /var/lib/libvirt/images/zbnodes/node-1.qcow2
```

## Troubleshooting

### Preflight fails: no vmx/svm flag or no /dev/kvm

The provider does not expose nested virtualization to your VPS. Ask the
provider to turn it on, or move to a plan that has it. The kit cannot work
around this.

### Step 20 fails: zram is not available

Some cloud kernels (for example Ubuntu `linux-kvm`) do not include the zram
module. Install the extra modules for your kernel, or switch to the generic
kernel:

```bash
sudo apt-get install linux-modules-extra-$(uname -r)   # or: linux-generic, then reboot
```

### The node looks frozen at first boot

Boots take about 2 minutes under nested virtualization. The VGA console can look
frozen while the boot waits on a serial device timeout. This is not a hang. Use
`bin/node-console.sh` to watch the serial console.

### The node came up on an old release

The newest QCOW2 on the CDN can be older than the current node release. This is
normal. Nodes run with automatic updates on by default and upgrade to the newest
release on boot. Only the first boot uses the image version.

The node upgrade needs free disk space. The appliance grows its small root
partition at first boot, but the boot-time update can start before that grow is
complete. The update then fails because the disk is full, and the node stays on
the image version. Step 50 prevents this: it grows the root partition before
the first boot.

### Never reboot a node during an update

An upgrade can take several minutes under nested virtualization. If the node
holds an `apt` or `dpkg` lock, an upgrade is running. Wait for it:

```bash
ps aux | grep -E 'apt|dpkg'
```

A reboot during the upgrade leaves the node with mixed component versions. To
recover, use **Services → Update & Reboot** in the node TUI.

### The host reboots or dies with nothing in its logs

On a VPS, the provider can page your VM's memory out to its own disk. Then the
provider's hypervisor can inject an "async page fault" while your kernel runs in
kernel mode. Linux must panic when that happens. The panic message is:

```
Kernel panic - not syncing: Host injected async #PF in kernel mode
```

Run the optional step 60, then reboot the host:

```bash
./bootstrap.sh 60
sudo reboot
./bootstrap.sh 60     # second run arms kdump after the reboot
```

Step 60:

- Boots the kernel with `no-kvmapf`. The kernel turns async page faults off, so
  a vCPU waits instead of panicking.
- Blacklists the `qxl` display driver, which has crashed nested hosts.
- Installs and arms **kdump**. A kernel panic writes a dump and `dmesg` to
  `/var/crash` and then reboots the host.
- Turns an oops or a soft lockup into a panic, so kdump catches it. A
  provider-injected NMI also triggers a dump of a hung host.
- Makes journald write to disk every 15 seconds instead of every 5 minutes.
- Turns on `sysstat` with a sample every minute.

After a crash, look in this order:

```bash
ls -la /var/crash/                        # a timestamped folder = kernel panic (read dmesg.*)
sudo journalctl -b -1 -n 100 --no-pager   # last logs, at most about 15 s old
sar -r -f /var/log/sysstat/saDD           # memory by minute. Also -u (CPU), -q (load), -S (swap)
```

If there is no dump and the logs are clean up to the end, something outside
stopped the VM. Ask the provider for the reason at that time. Also ask the
provider to stop swapping your VM's memory: `no-kvmapf` stops the panic, but the
nodes are still slow while the provider swaps.

The nodes start automatically after a host reboot.

### `virsh ... | grep -q` fails in a script

With `set -o pipefail`, `grep -q` exits at the first match and `virsh` then gets
`SIGPIPE`, so the pipeline fails. The kit puts the `virsh` output in a variable
first, and then searches the variable. Do the same in your own scripts.

## Downloads

All files of the kit, in the kit folder layout:

- {{< download "node-kvm-host/README.txt" >}}
- {{< download "node-kvm-host/bootstrap.sh" >}}
- {{< download "node-kvm-host/config.env" >}}
- {{< download "node-kvm-host/lib/common.sh" >}}
- {{< download "node-kvm-host/nodes/node-1.env" >}}
- {{< download "node-kvm-host/host/00-preflight.sh" >}}
- {{< download "node-kvm-host/host/10-kvm.sh" >}}
- {{< download "node-kvm-host/host/20-memory.sh" >}}
- {{< download "node-kvm-host/host/30-libvirt.sh" >}}
- {{< download "node-kvm-host/host/40-image.sh" >}}
- {{< download "node-kvm-host/host/50-nodes.sh" >}}
- {{< download "node-kvm-host/host/60-crash-capture.sh" >}}
- {{< download "node-kvm-host/bin/node-list.sh" >}}
- {{< download "node-kvm-host/bin/node-console.sh" >}}
- {{< download "node-kvm-host/bin/node-vnc.sh" >}}
- {{< download "node-kvm-host/bin/node-rename.sh" >}}
- {{< download "node-kvm-host/bin/node-destroy.sh" >}}

Source: [github.com/zerobias-org/kb](https://github.com/zerobias-org/kb/tree/main/package/nodevps-node-on-a-vps/node-kvm-host)

## Related

- [Connection Node Deployment](https://cdn.zerobias.com/kb/kb251/index.html)
- [Connection Node on Proxmox](https://cdn.zerobias.com/kb/kb261/index.html)
