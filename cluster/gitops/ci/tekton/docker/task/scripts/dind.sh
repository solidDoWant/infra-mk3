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

# Kata boots the pod's VM with little memory and adds the pod's share after
# boot, but the kernel sizes its TCP memory limit (tcp_mem) once, at boot. That
# left builds with ~13 MB of socket buffers for the whole VM: a download over
# many connections went over it, and the kernel then shrank every connection's
# receive window to four segments (the Project Zomboid game download took
# ~180-330s instead of ~60s). Set it the way the kernel would have for the
# memory the VM has now. It only ever raises the limit, so where the kernel
# sized it from the real memory this is a no-op.
pages=$(($(awk '/^MemTotal:/ { print $2 }' /proc/meminfo) / 4))
limit=$((pages / 16))
pressure=$(awk '{ print $2 }' /proc/sys/net/ipv4/tcp_mem)
if [ "$pressure" -lt "$limit" ]; then
  echo "$((limit / 4 * 3)) $limit $((limit / 4 * 3 * 2))" > /proc/sys/net/ipv4/tcp_mem
  echo "tcp_mem: raised from $pressure to $limit pages before memory pressure"
fi

# Only reachable from inside the pod.
exec dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock
