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

# registrygate: trust its CA for exactly the registry hosts /etc/hosts sends
# to it, the other names on the line with its Service name (added by the
# ci-registrygate-intercept Kyverno policy). The CA's name constraints limit it
# to those hosts anyway.
marker=registrygate.ci.svc.cluster.local
if [ -f /etc/registrygate/ca.crt ]; then
  for host in $(awk -v marker="$marker" '{ m = 0; for (i = 2; i <= NF; i++) if ($i == marker) m = 1 } m { for (i = 2; i <= NF; i++) if ($i != marker) print $i }' /etc/hosts); do
    mkdir -p "/etc/docker/certs.d/$host"
    cp /etc/registrygate/ca.crt "/etc/docker/certs.d/$host/ca.crt"
    echo "registrygate: trusting its CA for $host"
  done
fi

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

# Kata gives privileged containers none of the VM's devices, so there's no
# /dev/kmsg, and a kind node's kubelet won't start without it (it gets the
# devices of this container). Same device numbers as the kernel's.
[ -e /dev/kmsg ] || mknod -m 600 /dev/kmsg c 1 11

# Started through the image's own dind wrapper, which sets up cgroup v2
# nesting first: it moves this process out of the root cgroup and delegates
# every controller to the children. Without that, systemd in a container
# can't start, so kind (and anything else that runs systemd) fails. It also
# mounts securityfs, and a tmpfs on /tmp if nothing is mounted there.
# Only reachable from inside the pod.
exec dind dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock
