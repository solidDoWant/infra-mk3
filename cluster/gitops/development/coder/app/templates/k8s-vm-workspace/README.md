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

The VM boots a NixOS image built from [`./nix`](./nix) and pushed to Harbor
(`harbor.<domain>/coder/nixos-workspace`). Tooling is declarative: add packages,
kernel modules, and services to `nix/os-config/configuration.nix`, rebuild, and
push a new image — the running system always matches the image.

To build and publish the image:

```sh
cd nix
make vm-image PUSH_ALL=true
```

## Persistence

The system root is **ephemeral** — it is reset from the image on every boot, so
updating the base image is just a tag bump (no in-place upgrades, no drift). All
durable state lives on a **single persistent disk**:

- `/home/coder` and `/workspace` — persisted via bind mounts (impermanence).
- `/nix/store` — a persistent overlay so packages installed at runtime
  (`nix profile install`, `nix develop`) survive reboots and base-image updates.

> [!WARNING]
> The persistent `/nix/store` overlay keeps user-installed store paths at the
> file level, but the nix database lives on the ephemeral root and resets each
> boot. Do **not** run `nix-collect-garbage` in this workspace, and prefer adding
> durable tooling declaratively in the image flake. (This overlay is the piece to
> validate first when bringing the template up.)

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
