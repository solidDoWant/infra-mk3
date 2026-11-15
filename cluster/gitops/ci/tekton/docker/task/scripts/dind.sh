#!/bin/sh
# Entrypoint for the docker Task's dind sidecar: mounts the build's Docker
# cache volume and starts dockerd on it.
set -eu

DISK=/dev/docker-disk
# mkfs.ext4 and resize2fs, from the e2fsprogs image volume.
PATH="/opt/e2fsprogs/sbin:$PATH"

# The volume is a raw block device. A blank one (no golden cache snapshot to
# clone yet) gets a filesystem; a clone already has one. BusyBox blkid exits 0
# even when it finds no filesystem, so check its output instead.
if [ -z "$(blkid "$DISK")" ]; then
  echo "docker cache: blank volume, formatting"
  mkfs.ext4 -q "$DISK"
else
  echo "docker cache: warm volume"
fi
mkdir -p /var/lib/docker
mount -t ext4 "$DISK" /var/lib/docker

# A clone can be bigger than the snapshot it came from (the project's cache
# size was raised), so grow the filesystem to fill the volume. Online, and a
# no-op when it already does.
if ! resized=$(resize2fs "$DISK" 2>&1); then
  echo "$resized" >&2
  exit 1
fi
case "$resized" in
  *"Nothing to do"*) ;;
  *) echo "docker cache: grew the filesystem to $(($(blockdev --getsize64 "$DISK") >> 30))GiB" ;;
esac
disk_bytes=$(blockdev --getsize64 "$DISK")

# Keep the build cache to 60% of the volume, leaving the rest for images and
# containers.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<JSON
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "$((disk_bytes * 6 / 10 >> 20))MB"
    }
  }
}
JSON

# Only reachable from inside the pod.
exec dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock
