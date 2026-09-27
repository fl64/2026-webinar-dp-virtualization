#!/usr/bin/env bash
# Base package set. Every package is image size, so no recommends and no optional extras.
set -euo pipefail

. /tmp/packer-lib.sh

wait_for_package_manager

export DEBIAN_FRONTEND=noninteractive
# Deliberately not quiet: a step that says nothing for tens of minutes gets its connection
# closed by whatever sits in between (NAT, ingress, apiserver), and the whole build dies with
# "script disconnected unexpectedly". Output is what keeps the channel alive.
apt-get update
# cloud-init and growpart come from the server-minimal source, but are named so a changed
# source cannot drop them silently: without them the image is not a cloud image.
apt-get install -y --no-install-recommends \
    qemu-guest-agent chrony ca-certificates curl sudo openssh-server \
    cloud-init cloud-guest-utils

echo "packages installed"
