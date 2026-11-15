#!/bin/sh
# Entrypoint for the docker Task's dind sidecar: mounts the build's Docker
# cache volume and starts dockerd on it.
set -eu

DISK=/dev/docker-disk

# The volume is a raw block device. A blank one (no golden cache snapshot to
# clone yet) gets a filesystem; a clone already has one. BusyBox blkid exits 0
# even when it finds no filesystem, so check its output instead.
if [ -z "$(blkid "$DISK")" ]; then
  echo "docker cache: blank volume, formatting"
  # The docker:dind image doesn't ship e2fsprogs. Only a project's first
  # builds (before a golden cache exists) get here.
  command -v mkfs.ext4 >/dev/null || apk add --no-cache --quiet e2fsprogs
  mkfs.ext4 -q "$DISK"
else
  echo "docker cache: warm volume"
fi
mkdir -p /var/lib/docker
mount -t ext4 "$DISK" /var/lib/docker

# A clone can be bigger than the snapshot it came from (the project's cache
# size was raised). Grow the filesystem to fill it. The filesystem's size comes
# from the ext4 superblock (at byte 1024: the block count at +4, the block size
# as log2(size) - 10 at +24), as the image has no e2fsprogs to ask.
disk_bytes=$(blockdev --getsize64 "$DISK")
fs_blocks=$(od -An -tu4 -j1028 -N4 "$DISK" | tr -d ' ')
block_size=$((1024 << $(od -An -tu4 -j1048 -N4 "$DISK" | tr -d ' ')))
if [ $((disk_bytes / block_size)) -gt "$fs_blocks" ]; then
  echo "docker cache: growing the filesystem to $((disk_bytes >> 30))GiB"
  command -v resize2fs >/dev/null || apk add --no-cache --quiet e2fsprogs-extra
  # Online: ext4 grows while mounted.
  resize2fs "$DISK" >/dev/null
fi

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
