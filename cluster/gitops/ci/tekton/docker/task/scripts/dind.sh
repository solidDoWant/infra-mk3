#!/bin/sh
# Entrypoint for the docker Task's dind sidecar: mounts the build's Docker
# cache volume and starts dockerd on it.
set -eu

# The volume is a raw block device. A blank one (no golden cache snapshot to
# clone yet) gets a filesystem; a clone already has one. BusyBox blkid exits 0
# even when it finds no filesystem, so check its output instead.
if [ -z "$(blkid /dev/docker-disk)" ]; then
  echo "docker cache: blank volume, formatting"
  # The docker:dind image doesn't ship e2fsprogs. Only a project's first
  # builds (before a golden cache exists) get here.
  command -v mkfs.ext4 >/dev/null || apk add --no-cache --quiet e2fsprogs
  mkfs.ext4 -q /dev/docker-disk
else
  echo "docker cache: warm volume"
fi
mkdir -p /var/lib/docker
mount -t ext4 /dev/docker-disk /var/lib/docker

# Keep the build cache well under the volume size.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "12GB"
    }
  }
}
JSON

# Only reachable from inside the pod.
exec dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock
