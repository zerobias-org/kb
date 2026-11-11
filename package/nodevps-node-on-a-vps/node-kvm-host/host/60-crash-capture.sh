#!/usr/bin/env bash
# OPTIONAL. Stability + crash evidence for a nested-virt host on a VPS.
# Run it if the host reboots or dies with nothing in its logs (see the KB
# article, "Troubleshooting"). Nothing here restarts libvirt or touches nodes.
#   - qxl blacklist: the qxl display driver has crashed nested hosts; rebuilds initramfs.
#   - no-kvmapf: stops "Host injected async #PF in kernel mode" panics (below);
#     takes effect on next boot.
#   - kdump: a kernel panic writes a dump + dmesg to /var/crash, then reboots.
#     Dumps exclude user pages, so guest RAM doesn't end up in them.
#   - panic sysctls: turn oops/soft lockup into a panic so kdump catches them,
#     and let a provider-injected NMI dump a hung host.
#   - journald: sync every 15s instead of 5m, so the last moments reach disk.
#   - sysstat: per-minute resource history, for the state just before a crash.
source "$(dirname "$0")/../lib/common.sh"
require_root "$@"

# --- qxl -------------------------------------------------------------------
if write_if_changed /etc/modprobe.d/blacklist-qxl.conf "blacklist qxl"; then
  update-initramfs -u
  warn "qxl blacklisted — takes effect on next reboot"
fi

# --- async page faults -----------------------------------------------------
# When the VPS provider pages this VM's RAM out, its hypervisor can inject an
# async #PF while this kernel is in kernel mode. Linux answers that with an
# unconditional panic ("Host injected async #PF in kernel mode"). no-kvmapf
# turns async PF off, so a vCPU just stalls while the provider pages the
# memory back in. Ask the provider to stop swapping your VM's memory too.
if write_if_changed /etc/default/grub.d/90-zbnode-no-kvmapf.cfg \
  'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT no-kvmapf"'; then
  update-grub
  warn "no-kvmapf set — takes effect on next reboot"
fi

# --- kdump -----------------------------------------------------------------
# kdump-tools adds crashkernel= to the kernel cmdline (its grub.d snippet).
# That needs a reboot, so the first run arms kdump config only.
if ! dpkg -s kdump-tools >/dev/null 2>&1; then
  log "installing kdump-tools"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o DPkg::Lock::Timeout=300 kdump-tools >/dev/null
  update-grub
fi
if ! grep -qx 'USE_KDUMP=1' /etc/default/kdump-tools; then
  sed -i -E 's/^#?\s*USE_KDUMP=.*/USE_KDUMP=1/' /etc/default/kdump-tools
  log "enabled kdump"
fi
systemctl enable kdump-tools.service >/dev/null 2>&1
kdump_ready=false
if grep -q 'crashkernel=' /proc/cmdline; then
  [ "$(cat /sys/kernel/kexec_crash_loaded)" = 1 ] || systemctl restart kdump-tools.service || true
  [ "$(cat /sys/kernel/kexec_crash_loaded)" = 1 ] && kdump_ready=true
else
  warn "no crashkernel= on the running kernel cmdline — reboot, then re-run step 60"
fi

# --- panic sysctls ---------------------------------------------------------
# No hung_task_panic: one task blocked on the hypervisor shouldn't reboot the
# host. kernel.panic is the fallback reboot if the dump itself fails.
if write_if_changed /etc/sysctl.d/91-zbnode-crash.conf \
"kernel.panic_on_oops = 1
kernel.softlockup_panic = 1
kernel.unknown_nmi_panic = 1
kernel.panic = 60"; then
  sysctl -q -p /etc/sysctl.d/91-zbnode-crash.conf
  log "applied panic sysctls"
fi

# --- journald --------------------------------------------------------------
if write_if_changed /etc/systemd/journald.conf.d/90-zbnode-sync.conf \
"[Journal]
SyncIntervalSec=15s"; then
  systemctl restart systemd-journald.service
  log "journald syncs every 15s"
fi

# --- sysstat ---------------------------------------------------------------
dpkg -s sysstat >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o DPkg::Lock::Timeout=300 sysstat >/dev/null
sed -i -E 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
sed -i -E 's/^HISTORY=.*/HISTORY=28/' /etc/sysstat/sysstat
if write_if_changed /etc/systemd/system/sysstat-collect.timer.d/90-zbnode-1min.conf \
"[Timer]
OnCalendar=
OnCalendar=*:*:00"; then
  systemctl daemon-reload
  log "sysstat samples every minute"
fi
systemctl enable --now sysstat.service sysstat-collect.timer >/dev/null 2>&1

if $kdump_ready; then
  ok "kdump armed, dumps go to $(. /etc/default/kdump-tools; echo "$KDUMP_COREDIR")"
else
  warn "kdump not armed yet — reboot, re-run step 60, check: kdump-config status"
fi
ok "panic: oops=$(sysctl -n kernel.panic_on_oops) softlockup=$(sysctl -n kernel.softlockup_panic) nmi=$(sysctl -n kernel.unknown_nmi_panic) reboot_after=$(sysctl -n kernel.panic)s"
