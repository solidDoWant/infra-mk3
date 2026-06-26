---
display_name: Workspace on Kubernetes (virtual machine)
description: Provision a workspace as a NixOS KubeVirt virtual machine
icon: /icon/desktop.svg
maintainer_github: solidDoWant
verified: true
tags: [kubernetes, vm, kubevirt, nixos]
---

# Workspace on Kubernetes (virtual machine)

A workspace that runs as a full virtual machine (NixOS) instead of a container.
Unlike the standard workspace, it has a real, mutable kernel — you can **load
kernel modules and make kernel-level changes**: `modprobe`, building and inserting
out-of-tree modules, tweaking kernel parameters, etc. You also get passwordless
`sudo`.

Pick this template when your project needs kernel-level access. For everything
else, the standard (container) workspace is lighter and starts faster.

## What survives a restart

Stopping and starting the workspace (or restarting it) keeps:

- **`/home/coder`** — your home directory.
- **`/workspace`** — your project working directory.
- **Packages you install with Nix** (`nix profile install`, `nix develop`,
  `nix-shell`) — these are cached on a persistent disk, so a restart doesn't
  re-download or rebuild them.

Everything else is **rebuilt from the base image on each boot**, so anything
outside the list above resets — system packages installed outside Nix, edits to
`/etc`, and so on. To keep a tool around permanently, install it with Nix (it
persists) or ask the template maintainer to add it to the base image.

A nice consequence: base-image updates are seamless. You pick up the new system on
your next restart with your home directory, workspace, and Nix packages intact.

## Connecting

- **Web terminal / IDE** — open the workspace from the Coder dashboard, same as
  any other workspace.
- **SSH** — the VM joins Teleport automatically on boot, so
  `tsh ssh coder@<workspace-name>` works (sessions are recorded).

## Good to know

- **CPU-only** — no GPU. Use the standard container template if you need a GPU.
- **Node maintenance won't interrupt you** — the VM live-migrates to another node
  rather than being killed.
- The base image is managed declaratively by the template maintainer in
  [`../image`](../image); installing tooling the NixOS way is the intended
  workflow.
