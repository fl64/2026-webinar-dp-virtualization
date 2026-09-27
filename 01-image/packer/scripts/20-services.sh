#!/usr/bin/env bash
# Services without which a DVP image is not finished: the guest agent (machine status, IP
# address, filesystem freeze for consistent snapshots) and time synchronisation.
set -euo pipefail

. /tmp/packer-lib.sh

systemctl enable --now qemu-guest-agent.service chrony.service

# Journals: persistent storage with a size cap — otherwise a cloned machine either loses its
# logs on reboot or fills the disk with them.
install -d -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-packer.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=512M
RuntimeMaxUse=64M
MaxRetentionSec=1month
EOF

timedatectl set-timezone UTC 2>/dev/null || true

# Automatic security updates.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "services configured"
