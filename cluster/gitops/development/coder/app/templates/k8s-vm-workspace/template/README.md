---
display_name: Workspace on Kubernetes (VM)
description: Provision a workspace as a NixOS KubeVirt virtual machine
icon: /icon/k8s.svg
maintainer_github: solidDoWant
verified: true
tags: [kubernetes, vm, kubevirt, nixos]
---

# Workspace on Kubernetes (VM)

Create a workspace running in a full **KubeVirt virtual machine** (NixOS) instead
of a container. Unlike the standard (Kata container) template, this gives a real,
mutable kernel — you can **load kernel modules and make kernel-level changes**
(`modprobe`, out-of-tree module builds, etc.).

Use this template when a project needs kernel-level access; otherwise prefer the
lighter standard container template.

## Image

The VM boots a NixOS image built from the sibling
[`../image`](../image) directory and pushed to
Harbor (`harbor.<domain>/coder/nixos-workspace`). The image build lives outside
this `template/` directory on purpose: Coder bundles the whole pushed directory
(`template/`) on push, and a `nix/` subtree inside it breaks Coder's
dynamic-parameter evaluation. Keeping it at `../image` (a sibling of `template/`,
not under it) avoids that.
Tooling is declarative: add packages, kernel modules, and services to
`os-config/configuration.nix`, rebuild, and push a new image — the running system
always matches the image.

To build and publish the image:

```sh
cd ../image
make vm-image PUSH_ALL=true
```

## Persistence

The system root is **ephemeral** — it is reset from the image on every boot, so
updating the base image is just a tag bump (no in-place upgrades, no drift).
Durable state lives on a **single persistent disk**:

- `/home/coder` and `/workspace` — persisted via bind mounts (impermanence).
- `/var/lib/nixos`, `/var/lib/teleport` — stable system ids + Teleport identity.

> [!NOTE]
> `/nix` comes from the image, so packages installed *at runtime*
> (`nix profile install`) do **not** persist across reboots — add durable tooling
> declaratively in the image flake instead (the intended workflow). A persistent
> `/nix/store` overlay was prototyped but disabled: the initrd
> overlay-over-its-own-lowerdir dropped the VM to emergency mode, so it needs the
> bind-the-lowerdir-first pattern before it can ship.

## Access

Connect via the Coder web terminal, or over SSH: the VM joins the Teleport
cluster as an SSH node on boot (kubernetes join method), so `tsh ssh
coder@<workspace-name>` works, with enhanced session recording.

## Live migration

The VM uses RWX-block storage and `evictionStrategy: LiveMigrate`, so a draining
node live-migrates the workspace instead of killing it. KubeVirt manages the
disruption budget automatically.

## Not supported

- **GPU passthrough** — CPU-only. Use the standard container template for GPU
  workspaces.
