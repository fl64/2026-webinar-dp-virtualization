#!/usr/bin/env bash
# Preparing the image for cloning. Everything that would make two machines built from one
# image indistinguishable has to go: identifiers, host keys, cloud-init state, logs.
set -euo pipefail

. /tmp/packer-lib.sh

# The update timestamp goes along with the package lists: tools that trust it (the Ansible
# apt module, for one) would otherwise consider an empty cache fresh.
apt-get clean
rm -rf /var/lib/apt/lists/* /var/lib/apt/periodic/*

# cloud-init has to run again on every new machine.
cloud-init clean --logs --seed
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/instance

# Host keys are regenerated on the first boot; otherwise every clone shares a fingerprint.
rm -f /etc/ssh/ssh_host_*

# machine-id: emptied rather than removed, so systemd generates a new one on first boot.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# DHCP leases and network interface naming rules inherited from the build machine.
rm -rf /var/lib/dhcp/* 2>/dev/null || true
rm -f /etc/udev/rules.d/70-persistent-net.rules

journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

rm -f /root/.bash_history /home/*/.bash_history
rm -rf /tmp/packer-* /tmp/sshd-hardening.conf /tmp/sysctl-hardening.conf

# Discarding free space makes the next image import noticeably smaller.
fstrim -av || true
# The build user must not survive into the image, but it cannot be removed here: Packer's next step
# is `sudo shutdown -h now` as that user, and without the account, its sudoers file or an unlocked
# password (Ubuntu's sudo refuses a locked account) the guest never powers off and the build ends
# with no image. So only its keys go now, and a unit removes the account on the first boot.
build_user="${SUDO_USER:-}"
if [ -n "$build_user" ] && [ "$build_user" != root ] && id "$build_user" >/dev/null 2>&1; then
    home=$(getent passwd "$build_user" | cut -d: -f6)
    [ -n "$home" ] && rm -rf "${home:?}/.ssh"
    cat >/etc/systemd/system/packer-remove-build-user.service <<UNIT
[Unit]
Description=Remove the build user left by the image build, once
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-/bin/sh -c 'userdel -rf ${build_user}'
ExecStart=-/bin/rm -f /etc/sudoers.d/${build_user}
ExecStart=-/bin/sh -c 'systemctl disable packer-remove-build-user.service'
ExecStart=-/bin/rm -f /etc/systemd/system/packer-remove-build-user.service

[Install]
WantedBy=multi-user.target
UNIT
    install -d -m 0755 /etc/systemd/system/multi-user.target.wants
    ln -sf ../packer-remove-build-user.service \
        /etc/systemd/system/multi-user.target.wants/packer-remove-build-user.service
    echo "disarmed the build user $build_user; it is removed on the first boot"
fi

sync
echo "cleanup done"
