#!/usr/bin/env bash
# What turns an installed system into a cloud image: it has to fit the disk it is given,
# notice CPU and memory added while it runs, talk over the serial console and carry no swap.
# An image built from an installation ISO gets none of this by default, unlike a vendor
# cloud image.
set -euo pipefail

. /tmp/packer-lib.sh

# --- cloud-init runs on every clone -------------------------------------------------------
# A package installed into a chroot by the installer gets no preset applied, and an image whose
# cloud-init units are off boots with no user, no key and no hostname. Both naming schemes on
# purpose: cloud-init renamed its units around 24.x, and enabling only the old names leaves out
# cloud-init-local, the stage where NoCloud is found.
for unit in cloud-init-local.service cloud-init-main.service cloud-init-network.service \
    cloud-init.service cloud-config.service cloud-final.service cloud-init.target; do
    systemctl enable "$unit" >/dev/null 2>&1 || echo "unit $unit is absent, skipping"
done

# --- Growing into the disk -----------------------------------------------------------------
# A disk enlarged in the platform (or an image cloned onto a bigger one) is useless while the
# partition stays the size it was installed with. `devices: ['/']` means the device carrying
# the root mount, so /dev/sda is not hardcoded.
cat >/etc/cloud/cloud.cfg.d/90-growpart.cfg <<'EOF'
growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false
resize_rootfs: true
EOF
rm -f /etc/growroot-disabled

# --- The default user -----------------------------------------------------------------------
# Root is locked and the build user is removed on first boot, so the only way in is the account
# cloud-init creates. A bare `ssh_authorized_keys` in userData lands on this one; a full `users:`
# block, as every VM of the demo has, overrides it.
cat >/etc/cloud/cloud.cfg.d/99-default-user.cfg <<'EOF'
system_info:
  default_user:
    name: flant
    gecos: Default user
    lock_passwd: true
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    groups: [adm, sudo, systemd-journal]
EOF

# --- Hotplug of CPU and memory -------------------------------------------------------------
# The platform can add vCPUs and memory to a running machine, but the guest kernel leaves the
# new resources offline until someone onlines them. udev does it as they appear.
cat >/etc/udev/rules.d/80-hotplug-cpu-mem.rules <<'EOF'
# A vCPU added to a running machine arrives offline.
SUBSYSTEM=="cpu", ACTION=="add", TEST=="online", ATTR{online}=="0", ATTR{online}="1"
# Same for a memory block. `online_movable` keeps the block removable, so memory can also be
# taken away again; plain `online` would pin it forever.
SUBSYSTEM=="memory", ACTION=="add", TEST=="state", ATTR{state}=="offline", ATTR{state}="online_movable"
EOF

# --- Serial console ------------------------------------------------------------------------
# `d8 v console` speaks to the guest over the serial port, so the kernel and a getty have to
# be there. Without the kernel argument the boot messages never reach the console and a failed
# boot is invisible.
# console=tty0 first and console=ttyS0 last: the kernel sends /dev/console to the last one.
if ! grep -q 'console=ttyS0' /etc/default/grub; then
    sed -i 's/^\(GRUB_CMDLINE_LINUX="\?[^"]*\)/\1 console=tty0 console=ttyS0,115200n8/' /etc/default/grub
fi
# A silent boot is a boot nobody can debug.
sed -i -e 's/\bquiet\b//g' -e 's/\bsplash\b//g' /etc/default/grub
grep -q '^GRUB_TERMINAL' /etc/default/grub || echo 'GRUB_TERMINAL="console serial"' >>/etc/default/grub
grep -q '^GRUB_SERIAL_COMMAND' /etc/default/grub || echo 'GRUB_SERIAL_COMMAND="serial --speed=115200"' >>/etc/default/grub
# After a boot that did not finish Ubuntu shows the menu with no timeout, and the machine waits
# for a key nobody presses.
grep -q '^GRUB_RECORDFAIL_TIMEOUT' /etc/default/grub || echo 'GRUB_RECORDFAIL_TIMEOUT=5' >>/etc/default/grub
update-grub

# Enabled statically rather than with `--now`: the running kernel has no console=ttyS0 yet, so
# systemd-getty-generator has not created the unit. The symlink is what matters for the next boot.
systemctl enable serial-getty@ttyS0.service

# A serial line carries no window size: the kernel keeps whatever getty started with (80x24), and
# a window resized after login leaves long lines wrapping over themselves. The size is asked from
# the terminal itself: park the cursor far beyond the screen, read where it ended up (CPR), tell
# the tty. Raw mode keeps the reply out of the shell, the scroll region reset lets the cursor reach
# the real bottom.
cat >/etc/profile.d/99-resize-terminal.sh <<'EOF'
if [ "${BASH_VERSION-}" != "" ] && [ "${PS1-}" != "" ] && [[ "$(tty)" =~ "/dev/tty"* ]]; then
  if [ ! -f "/usr/bin/resize" ]; then
    resize() {
      old=$(stty -g)
      stty raw -echo min 0 time 5
      printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
      IFS='[;R' read -r _ rows cols _ < /dev/tty
      stty "$old"
      stty cols "$cols" rows "$rows"
    }
  fi

  resize

  export TERM=screen-256color
fi
EOF
chmod 0644 /etc/profile.d/99-resize-terminal.sh

# --- cloud-init looks only where it can find something --------------------------------------
# The platform hands the configuration over on a NoCloud medium; probing EC2, Azure, GCE and the
# rest costs tens of seconds of network timeouts on every boot.
cat >/etc/cloud/cloud.cfg.d/95-datasource.cfg <<'EOF'
datasource_list: [NoCloud, None]
EOF

# --- Discarding blocks all the time, not only at build time --------------------------------
# The storage is thin-provisioned, so blocks a guest stops using are worth returning.
systemctl enable fstrim.timer

# --- Time after a snapshot or a pause ------------------------------------------------------
# A machine resumed from a snapshot wakes up with a clock far behind. `makestep` lets chrony jump
# instead of slewing for as long as the drift; -1 means no limit on how many times.
grep -q '^makestep' /etc/chrony/chrony.conf || echo 'makestep 1.0 -1' >>/etc/chrony/chrony.conf

# --- Nothing waits for the network ---------------------------------------------------------
# An interface that never gets a lease holds this unit for its full timeout, and the boot with it.
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

# --- No swap -------------------------------------------------------------------------------
# kubelet refuses to start with swap on. The installer creates none; this is the guarantee.
swapoff -a || true
sed -i '/\sswap\s/d' /etc/fstab
rm -f /swapfile /swap.img
systemctl mask swap.target 2>/dev/null || true

# --- Predictable networking ----------------------------------------------------------------
# A clone gets a new MAC, and a rule pinned to the old one leaves it without an interface.
rm -f /etc/udev/rules.d/70-persistent-net.rules /etc/udev/rules.d/80-net-setup-link.rules

# Names follow the PCI slot (enp1s0) rather than the onboard index or probe order. Only PCI
# devices match, so the virtual links of a container runtime keep the names of 99-default.link.
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/10-pci-path.link <<'EOF'
[Match]
Path=pci-*
[Link]
NamePolicy=path
AlternativeNamesPolicy=database onboard slot path
MACAddressPolicy=persistent
EOF

# --- Every ethernet interface asks for DHCP -------------------------------------------------
# A second or third interface given to the machine stays down without configuration. cloud-init
# rewrites 50-cloud-init.yaml on every boot; a 99- file is read after it and adds the catch-all
# without fighting over the same keys.
cat >/etc/netplan/99-ethernet-dhcp.yaml <<'EOF'
network:
  version: 2
  ethernets:
    catch-all-ethernet:
      match:
        name: "e*"
      dhcp4: true
      dhcp6: true
      # Do not hold the boot waiting for an interface nobody plugged anything into.
      optional: true
EOF
chmod 0600 /etc/netplan/99-ethernet-dhcp.yaml
netplan generate

# --- Who answers a name lookup --------------------------------------------------------------
# With `resolve` in the hosts line glibc asks systemd-resolved first, and resolved refuses every
# name under .local unless a link carries a routing domain for it: the cluster domain lies inside
# that zone. /etc/resolv.conf gets the servers from the lease instead of the 127.0.0.53 stub, and
# glibc queries them itself. resolved keeps running, networkd writes the lease into it.
if systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    sed -i -E '/^hosts:/ s/[[:blank:]]+resolve([[:blank:]]+\[[^]]*\])?//' /etc/nsswitch.conf
    echo "name lookup: $(grep '^hosts:' /etc/nsswitch.conf)"
fi

echo "cloud preparation done"
