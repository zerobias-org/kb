node-kvm-host — run ZeroBias Hub Node VMs on a VPS (or any Linux KVM host)

Full guide: the ZeroBias KB article "Hub Node on a VPS (KVM host kit)"
Source:     https://github.com/zerobias-org/kb/tree/main/package/nodevps-node-on-a-vps

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

Quick start (Ubuntu host, as a sudo-capable user):
  chmod +x bootstrap.sh host/*.sh bin/*.sh
  ./bootstrap.sh
  bin/node-console.sh node-1     # register the node from its console

Every host/ step is idempotent. Re-run ./bootstrap.sh at any time.
