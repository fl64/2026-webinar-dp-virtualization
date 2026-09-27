#!/usr/bin/env bash
# Baseline hardening: sshd accepts keys only, sane network sysctls, higher limits.
# Everything goes into separate drop-in files so a package upgrade cannot wipe it.
set -euo pipefail

. /tmp/packer-lib.sh

# sshd applies the FIRST occurrence of a directive, and cloud-init ships its own
# 50-cloud-init.conf with PasswordAuthentication yes. Hence the leading zeros in the file
# name, plus silencing the conflicting directives in the other files.
install -d -m 0755 /etc/ssh/sshd_config.d
cp /tmp/sshd-hardening.conf /etc/ssh/sshd_config.d/00-packer-hardening.conf
chmod 0644 /etc/ssh/sshd_config.d/00-packer-hardening.conf

for f in /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config; do
    [ "$f" = /etc/ssh/sshd_config.d/00-packer-hardening.conf ] && continue
    [ -f "$f" ] || continue
    sed -i -E 's/^[[:space:]]*(PasswordAuthentication|PermitRootLogin|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]/# disabled during image build: \1 /I' "$f"
done

# sshd is socket-activated on Ubuntu 26.04, and without its runtime directory `sshd -t` fails
# with "Missing privilege separation directory" on a valid configuration.
install -d -m 0755 /run/sshd
sshd -t
echo "sshd config valid"

cp /tmp/sysctl-hardening.conf /etc/sysctl.d/99-packer.conf
chmod 0644 /etc/sysctl.d/99-packer.conf
sysctl --system >/dev/null

install -d -m 0755 /etc/security/limits.d
cat > /etc/security/limits.d/99-packer.conf <<'EOF'
*  soft  nofile  65535
*  hard  nofile  65535
EOF

# The root password is locked: login by key only, as the baseline policy requires.
passwd -l root >/dev/null 2>&1 || true

echo "hardening applied"
