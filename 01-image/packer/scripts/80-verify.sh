#!/usr/bin/env bash
# Image acceptance. If any of this does not hold, the build must fail here rather than
# surface in production a week later.
set -euo pipefail

. /tmp/packer-lib.sh

fail=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "  ok    $1"
    else
        echo "  FAIL  $1"
        fail=1
    fi
}

# Checks that need quotes inside are written as functions: eval with nested quoting lies
# about the result instead of failing, and debugging such a "FAIL" costs more than it saves.
pw_auth_off()   { [ "$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2}')" = no ]; }
syncookies_on() { [ "$(sysctl -n net.ipv4.tcp_syncookies)" = 1 ]; }
# A leading ! or * in the shadow entry means locked.
root_locked()   { awk -F: '$1=="root"{print $2}' /etc/shadow | grep -qE '^[!*]'; }

# Cloud properties. Each of these is invisible until the image is already in use: a disk that
# never grows, a vCPU that stays offline, a console that shows nothing when the boot fails.
growpart_ready() { command -v growpart >/dev/null 2>&1; }
growpart_on()    { ! [ -f /etc/growroot-disabled ]; }
hotplug_rules()  { [ -f /etc/udev/rules.d/80-hotplug-cpu-mem.rules ]; }
serial_console() { grep -qs 'console=ttyS0' /proc/cmdline || grep -qs 'console=ttyS0' /etc/default/grub; }
# `enabled` when the symlink is in place, `enabled-runtime` when systemd-getty-generator created
# the unit from console=ttyS0 on the current command line — both mean a getty on the next boot.
serial_getty() {
    case "$(systemctl is-enabled serial-getty@ttyS0.service 2>/dev/null)" in
    enabled | enabled-runtime | static) return 0 ;;
    *) return 1 ;;
    esac
}
console_resize() { [ -f /etc/profile.d/99-resize-terminal.sh ]; }
# The machine may be given either firmware; NVRAM does not survive here, so EFI boots only
# through the fallback loader that autoinstall.yaml installs.
efi_fallback()   { [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; }
no_swap()        { [ -z "$(swapon --show --noheadings 2>/dev/null)" ] && ! grep -qE '^[^#].*\sswap\s' /etc/fstab; }
cloud_init_ok()  { command -v cloud-init >/dev/null 2>&1; }
# The file, not a lookup: whether a name resolves depends on the stand, whether the resolver is
# wired up depends on the image. grep fails on a dangling symlink too.
resolver_set()   { grep -q '^nameserver' /etc/resolv.conf; }
dhcp_catch_all() { [ -f /etc/netplan/99-ethernet-dhcp.yaml ]; }
# Only the setting can be checked here: the disk it writes exists on the clone, not on this machine.
grub_dpkg_on()   { grep -qsx '  enabled: true' /etc/cloud/cloud.cfg.d/90-grub-dpkg.cfg; }

echo "image acceptance:"
check "guest agent enabled"       "systemctl is-enabled qemu-guest-agent.service"
check "guest agent running"       "systemctl is-active qemu-guest-agent.service"
check "time synchronisation"      "systemctl is-enabled chrony.service"
check "sshd config valid"         "sshd -t"
check "password login disabled"   pw_auth_off
check "sysctl applied"            syncookies_on
check "journals persistent"       "grep -q '^Storage=persistent' /etc/systemd/journald.conf.d/99-packer.conf"
check "root account locked"       root_locked
check "cloud-init present"        cloud_init_ok
check "resolver configured"       resolver_set
check "growpart available"        growpart_ready
check "root growth allowed"       growpart_on
check "cpu and memory hotplug"    hotplug_rules
check "serial console in cmdline" serial_console
check "serial getty enabled"      serial_getty
check "console resizes on login"  console_resize
check "efi fallback loader"       efi_fallback
check "no swap"                   no_swap
check "new nics get dhcp"         dhcp_catch_all
check "grub disk set per clone"   grub_dpkg_on

# What the image occupies: the build disk in ubuntu.pkr.hcl is sized after this.
df -m / /boot/efi

if [ "$fail" -ne 0 ]; then
    # Print what exactly disagrees: without this, troubleshooting turns into guessing.
    echo "--- diagnostics ---"
    ls -l /etc/resolv.conf 2>&1 || true
    sshd -T 2>/dev/null | grep -iE '^(passwordauthentication|permitrootlogin|kbdinteractive)' || true
    grep -rniE '^[[:space:]]*(PasswordAuthentication|PermitRootLogin)' \
        /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null || true
    echo "acceptance failed" >&2
    exit 1
fi
echo "acceptance passed"
