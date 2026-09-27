#!/usr/bin/env bash
# Shared helpers for the image preparation scripts. Uploaded to /tmp/packer-lib.sh and
# sourced by the rest. Ubuntu only: the demo builds nothing else.
set -euo pipefail

# The installed system may still be running apt on first boot and hold its locks.
# Without this wait the installation fails with "Could not get lock".
wait_for_package_manager() {
    # Time-boxed: on the first boot of a system installed from an ISO cloud-init has no data source
    # yet (datasource_list is narrowed later, by 40-cloud.sh) and walks through EC2, Azure and GCE
    # with their network timeouts. Waiting for it is worth a couple of minutes, not the build.
    echo "waiting for cloud-init to settle (up to 120s)"
    timeout 120 cloud-init status --wait >/dev/null 2>&1 || true
    echo "cloud-init: $(cloud-init status 2>/dev/null | head -1)"
    for _ in $(seq 1 60); do
        fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1 || return 0
        sleep 5
    done
    echo "apt stayed busy for over five minutes" >&2
    return 1
}
