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

# kind: the same interception for a kind cluster's nodes, whose containerd
# uses neither this container's /etc/hosts nor dockerd's certs.d. These files
# are for the nodes to mount (kind extraMounts), so their paths are this
# container's; kind-patch.yaml lists the mounts and the kubelet flags (see the
# Task). The kubelet gets the pod's registrygate token from a credential
# provider that reads the token file on every call, so rotation needs nothing.
KIND_DIR=/run/ci-kind
hosts=$(awk -v marker="$marker" '{ m = 0; for (i = 2; i <= NF; i++) if ($i == marker) m = 1 } m { for (i = 2; i <= NF; i++) if ($i != marker) print $i }' /etc/hosts)
if [ -n "$hosts" ] && [ -f /etc/registrygate/ca.crt ]; then
  mkdir -p "$KIND_DIR/certs.d" "$KIND_DIR/kubelet/bin"
  {
    echo "127.0.0.1 localhost"
    echo "::1 localhost ip6-localhost ip6-loopback"
    awk -v marker="$marker" '{ for (i = 2; i <= NF; i++) if ($i == marker) { print; next } }' /etc/hosts
  } > "$KIND_DIR/hosts"
  match_images=""
  auth_hosts=""
  for host in $hosts; do
    # containerd calls Docker Hub docker.io and reaches it at
    # registry-1.docker.io; index.docker.io is a name only Docker uses.
    case "$host" in
      index.docker.io|registry-1.docker.io) continue ;;
      docker.io) server=registry-1.docker.io ;;
      *) server=$host ;;
    esac
    mkdir -p "$KIND_DIR/certs.d/$host"
    cp /etc/registrygate/ca.crt "$KIND_DIR/certs.d/$host/ca.crt"
    cat > "$KIND_DIR/certs.d/$host/hosts.toml" <<TOML
server = "https://$server"

[host."https://$server"]
  capabilities = ["pull", "resolve"]
  ca = "/etc/containerd/certs.d/$host/ca.crt"
TOML
    match_images="$match_images      - $host
"
    auth_hosts="$auth_hosts $host"
  done
  cat > "$KIND_DIR/kubelet/credential-provider.yaml" <<YAML
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: registrygate
    apiVersion: credentialprovider.kubelet.k8s.io/v1
    defaultCacheDuration: 1m
    matchImages:
$match_images
YAML
  # The kubelet's credential provider protocol: a request on stdin, a
  # response with a username and password per registry host on stdout. The
  # proxy takes the token as the password and ignores the username.
  {
    echo "#!/bin/sh"
    echo "hosts=\"$auth_hosts\""
    cat <<'SH'
cat >/dev/null
token=$(cat /var/run/secrets/registrygate/token)
printf '{"apiVersion":"credentialprovider.kubelet.k8s.io/v1","kind":"CredentialProviderResponse","cacheKeyType":"Registry","cacheDuration":"1m","auth":{'
sep=
for host in $hosts; do
  printf '%s"%s":{"username":"registrygate","password":"%s"}' "$sep" "$host" "$token"
  sep=,
done
printf '}}\n'
SH
  } > "$KIND_DIR/kubelet/bin/registrygate"
  chmod 755 "$KIND_DIR/kubelet/bin/registrygate"
  # kubeadm v1beta4 takes kubeletExtraArgs as a list of name/value pairs,
  # v1beta3 as a map, and kind writes whichever its version uses (toolgate's
  # kind writes v1beta3 for Kubernetes 1.35, the others v1beta4). A patch
  # that names its apiVersion only applies to a config of that version, so
  # each is given in both forms and exactly one applies.
  kubelet_args_v1beta4='        - name: image-credential-provider-config
          value: /etc/ci-kind/kubelet/credential-provider.yaml
        - name: image-credential-provider-bin-dir
          value: /etc/ci-kind/kubelet/bin'
  kubelet_args_v1beta3='        image-credential-provider-config: /etc/ci-kind/kubelet/credential-provider.yaml
        image-credential-provider-bin-dir: /etc/ci-kind/kubelet/bin'
  cat > "$KIND_DIR/kind-patch.yaml" <<YAML
# Merge into a kind cluster config: extraMounts into every node,
# kubeadmConfigPatches into the cluster's. See the docker Task.
extraMounts:
  - hostPath: $KIND_DIR/hosts
    containerPath: /etc/hosts
    readOnly: true
  - hostPath: $KIND_DIR/certs.d
    containerPath: /etc/containerd/certs.d
    readOnly: true
  - hostPath: $KIND_DIR/kubelet
    containerPath: /etc/ci-kind/kubelet
    readOnly: true
  - hostPath: /var/run/secrets/registrygate
    containerPath: /var/run/secrets/registrygate
    readOnly: true
kubeadmConfigPatches:
  - |
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
$kubelet_args_v1beta4
  - |
    apiVersion: kubeadm.k8s.io/v1beta4
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
$kubelet_args_v1beta4
  - |
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
$kubelet_args_v1beta3
  - |
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
$kubelet_args_v1beta3
YAML
  echo "kind: node config for registrygate in $KIND_DIR/kind-patch.yaml"
fi

# kind nodes' image caches: each node's whole /var/lib/containerd (images,
# unpacked layers and containerd's own state) is kept on this volume, so the
# next build's cluster of the same name starts with every image already
# there. Docker names a kind node's container after the node, so two nodes
# can never run on one cache at once: kind can't create the second.

# ci-kind-config, on the step's PATH: prints a kind config with
# kind-patch.yaml merged in and the nodes' image caches mounted.
mkdir -p "$KIND_DIR/bin"
cat > "$KIND_DIR/bin/ci-kind-config" <<'SH'
#!/bin/sh
# Usage:
#   ci-kind-config [--name NAME --image IMAGE] [FILE] | kind create cluster --config=-
#
# Prints the kind config in FILE ("-" for stdin; none for kind's default
# cluster) with what this build's kind nodes need:
# - with registrygate, mounts for every node and the kubelet's flags, so that
#   their image pulls go through it like Docker's do;
# - with --name and --image, the cluster's name and node image, and an image
#   cache for every node: its containerd store is kept on the build's Docker
#   volume, so a cluster of the same name in a later build starts with the
#   images it pulled. Pass these here instead of to kind. The first use of a
#   cache, or a new node image, seeds it from the node image (a few seconds).
#   A cache that has grown more than 2 GiB past its seed is reseeded. Its size
#   is measured in the background after the claim, never on the way to kind
#   create: walking a few GB of containerd store on a busy disk took 16-47 s.
set -eu
patch=/run/ci-kind/kind-patch.yaml
yq=/opt/ci-kind/yq/usr/bin/yq
# On dockerd's side: kind's mounts and docker run -v name paths there.
caches=/var/lib/docker/ci-kind
# Reseed a node's cache once it has grown this much (KiB) past its seed. CI
# clusters are never deleted, so every run leaves its containers' snapshots
# and replaced images behind in the store.
grow_kib=$((2 * 1024 * 1024))
name=
image=
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name=$2; shift 2 ;;
    --name=*) name=${1#*=}; shift ;;
    --image) image=$2; shift 2 ;;
    --image=*) image=${1#*=}; shift ;;
    --) shift; break ;;
    -?*) echo "ci-kind-config: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [ $# -eq 0 ]; then
  config='kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4'
else
  config=$(cat -- "$1")
fi
# kind's default when a config lists no nodes is one control-plane node.
config=$(printf '%s\n' "$config" | "$yq" '.nodes = (.nodes // [{"role": "control-plane"}])')
if [ -n "$name" ]; then
  config=$(printf '%s\n' "$config" | NAME=$name "$yq" '.name = strenv(NAME)')
fi
if [ -n "$image" ]; then
  config=$(printf '%s\n' "$config" | IMAGE=$image "$yq" '.nodes[] |= (.image = (.image // strenv(IMAGE)))')
fi
if [ -f "$patch" ]; then
  config=$(printf '%s\n' "$config" | "$yq" eval-all '
    select(fileIndex == 1) as $patch
    | select(fileIndex == 0)
    | .nodes[] |= (.extraMounts = (.extraMounts // []) + $patch.extraMounts)
    | .kubeadmConfigPatches = (.kubeadmConfigPatches // []) + $patch.kubeadmConfigPatches
  ' - "$patch")
fi
# etcd on the node's /tmp, which kind mounts as tmpfs. CI clusters are thrown
# away after the build, and on the build's Docker disk (Ceph RBD) etcd's WAL
# fsyncs took 35 ms on average and its commits 83 ms (toolgate e2e, 2026-11-24):
# every API write waited on them, so parallel tests slowed each other 2-3x
# while the CPUs idled. Appended last, so it wins over a dataDir in FILE;
# CI_KIND_ETCD_ON_DISK=1 keeps etcd on disk. dataDir alone, as it reads the
# same in every kubeadm config version.
if [ "${CI_KIND_ETCD_ON_DISK:-}" != 1 ]; then
  config=$(printf '%s\n' "$config" | "$yq" '.kubeadmConfigPatches = (.kubeadmConfigPatches // []) + ["kind: ClusterConfiguration\netcd:\n  local:\n    dataDir: /tmp/etcd\n"]')
fi
if [ -z "$name" ] || [ -z "$image" ]; then
  printf '%s\n' "$config"
  exit 0
fi

# The nodes' container names, as kind names them: <name>-control-plane,
# <name>-control-plane2, ..., <name>-worker, <name>-worker2, ...
keys=
cp=0
wk=0
for role in $(printf '%s\n' "$config" | "$yq" '.nodes[].role'); do
  if [ "$role" = control-plane ]; then cp=$((cp + 1)); n=$cp; else wk=$((wk + 1)); n=$wk; fi
  if [ "$n" -gt 1 ]; then keys="$keys $name-$role$n"; else keys="$keys $name-$role"; fi
done

# Seed each node's cache in a container of the node image itself,
# which has the store to seed from. kind would pull the image anyway; skip
# the registry round trip when it's already here (it's pinned by digest).
docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null
id=$(docker image inspect -f '{{.Id}}' "$image")
# The sizes come from the files the background measurement (below) and the
# seed write: <key>.size and <key>.seed-size, in KiB. A cache without a seed
# size (made before these files existed) is reseeded once.
# shellcheck disable=SC2016,SC2086 # expanded in the container; keys split
claimed=$(docker run --rm -v "$caches:/c" --entrypoint sh "$image" -c '
  id=$1; grow=$2; shift 2
  mkdir -p /c/cache
  for key in "$@"; do
    dir=/c/cache/$key
    size=$(cat "$dir.size" 2>/dev/null || echo 0)
    seed=$(cat "$dir.seed-size" 2>/dev/null || echo 0)
    if [ "$(cat "$dir.image" 2>/dev/null)" != "$id" ] || [ "${seed:-0}" -eq 0 ] || [ "${size:-0}" -gt $((seed + grow)) ]; then
      rm -rf "$dir" "$dir.image" "$dir.size" "$dir.seed-size"
      mkdir -p "$dir"
      cp -a /var/lib/containerd/. "$dir/"
      seed=$(du -sk "$dir" | cut -f1)
      echo "$seed" > "$dir.seed-size"
      echo "$seed" > "$dir.size"
      echo "$id" > "$dir.image"
      echo "ci-kind-config: $key: seeded its image cache from the node image ($((seed / 1024)) MiB)" >&2
    else
      echo "ci-kind-config: $key: using its image cache ($((size / 1024)) MiB at its last measurement, seed $((seed / 1024)) MiB)" >&2
    fi
    echo "$key"
  done
' sh "$id" "$grow_kib" $keys)

# Measure the claimed caches for the next build, in the background and at low
# priority, so it's off the way to kind create. An unfinished measurement
# leaves the previous size in place (written to a temporary file, then moved).
# shellcheck disable=SC2016,SC2086 # expanded in the container; keys split
docker run -d --rm -v "$caches:/c" --entrypoint sh "$image" -c '
  for key in "$@"; do
    dir=/c/cache/$key
    size=$(nice -n 19 du -sk "$dir" | cut -f1) && echo "$size" > "$dir.size.tmp" && mv "$dir.size.tmp" "$dir.size"
  done
' sh $claimed >/dev/null

i=0
for key in $keys; do
  if printf '%s\n' "$claimed" | grep -qx "$key"; then
    config=$(printf '%s\n' "$config" | I=$i DIR="$caches/cache/$key" "$yq" \
      '.nodes[env(I)].extraMounts = ((.nodes[env(I)].extraMounts // []) + [{"hostPath": strenv(DIR), "containerPath": "/var/lib/containerd"}])')
  fi
  i=$((i + 1))
done
printf '%s\n' "$config"
SH
chmod 755 "$KIND_DIR/bin/ci-kind-config"

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

# inotify instances for the whole VM (this container runs as root in it). The
# kernel's default of 128 per user runs out with several kind clusters: each
# node's kubelet, containerd and controllers (kube-proxy first) open their
# own, and then crash with "failed to create fsnotify watcher: too many open
# files". The watches limit is raised by the kata kernel_params.
sysctl -w fs.inotify.max_user_instances=8192 >/dev/null

# Kubelet mounts an image volume as overlayfs with `volatile`, and the kernel
# refuses such a mount (EIO, "upperdir has an unseen error") once the disk's
# filesystem has had a write error that no syncfs has reported yet. The kind
# nodes' containerd stores are on this disk, so after one such error every
# image volume fails until something syncs it (githubgate e2e: pods stuck on
# ImageVolumeMountFailed ... input/output error). Copy the kernel's storage
# errors into this log, where a build's own logs can't see them (the VM's
# kernel log is only readable here), and sync the disk when the kernel asks
# for it.
(
  # Says whether the watch works: silence after this means no storage errors.
  if lines=$(dmesg 2>&1 | wc -l) && dmesg >/dev/null 2>&1; then
    echo "kernel watch: reading the VM's kernel log ($lines lines so far)"
  else
    echo "kernel watch: can't read the VM's kernel log: $(dmesg 2>&1 | head -1)"
  fi
  seen=0
  while sleep 5; do
    log=$(dmesg 2>/dev/null) || continue
    n=$(printf '%s\n' "$log" | wc -l)
    [ "$n" -lt "$seen" ] && seen=0
    new=$(printf '%s\n' "$log" | tail -n +"$((seen + 1))")
    seen=$n
    printf '%s\n' "$new" | grep -i -E 'unseen error|EXT4-fs (error|warning)|I/O error|writeback error|lost async page write' | sed 's/^/kernel: /'
    if printf '%s\n' "$new" | grep -q 'unseen error'; then
      sync -f /var/lib/docker && echo "kernel watch: synced /var/lib/docker to clear its unseen write error"
    fi
  done
) &

# Started through the image's own dind wrapper, which sets up cgroup v2
# nesting first: it moves this process out of the root cgroup and delegates
# every controller to the children. Without that, systemd in a container
# can't start, so kind (and anything else that runs systemd) fails. It also
# mounts securityfs, and a tmpfs on /tmp if nothing is mounted there.
# Only reachable from inside the pod.
exec dind dockerd --host=tcp://127.0.0.1:2375 --host=unix:///var/run/docker.sock
