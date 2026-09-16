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

Everything else lives on a **disposable root disk**. It survives an ordinary
restart, but it is **rebuilt from the base image whenever the template picks up a
new one**, so anything outside the list above — system packages installed outside
Nix, edits to `/etc`, and so on — is not durable. To keep a tool around
permanently, install it with Nix (it persists) or ask the template maintainer to
add it to the base image.

A nice consequence: base-image updates are seamless. You pick up the new system on
your next restart with your home directory, workspace, and Nix packages intact.

## Connecting

- **Web terminal / IDE** — open the workspace from the Coder dashboard, same as
  any other workspace.
- **SSH** — the VM joins Teleport automatically on boot, so
  `tsh ssh coder@<workspace-name>` works (sessions are recorded).
- **Desktop** — only with the `enable_desktop` parameter (see below).

## Desktop environment

Turning on **`enable_desktop`** gives the workspace a graphical Xfce desktop. It
is served by Teleport, not by Coder: open the Teleport **Web UI**, find your
workspace under **Resources**, and hit Connect — or use the **Desktop** button on
the workspace page, which opens that list pre-filtered. Log in as `coder`.

Two navigation gotchas: it lives in the general **Resources** list, not the
**Desktops** page (that one is Windows-only), and **Teleport Connect cannot open
it** — the desktop app supports Windows desktops only, so use a browser.

Nothing runs until you connect; Teleport starts a virtual display and the session
on demand, so an idle desktop workspace costs nothing extra at runtime.

Two things to know before turning it on:

- **It swaps the base image.** The desktop is a separate, larger base image, so
  toggling this reimports the root disk exactly like a base-image upgrade. Do it
  while the workspace is **stopped** (Stop → Update → Start). `/home/coder`,
  `/workspace`, and your Nix packages are untouched; give the workspace a larger
  **root disk** than the default when you enable it.
- **Software rendering only.** There is no GPU, so everything renders on the CPU
  via Mesa's llvmpipe. Fine for a browser, editors, and GUI tooling; slow for
  anything seriously 3D.

Your Xfce settings (panel layout, theme, xfconf) live in `/home/coder`, so they
survive restarts and base-image upgrades.

## Good to know

- **CPU-only** — no GPU. Use the standard container template if you need a GPU.
- **Node maintenance won't interrupt you** — the VM live-migrates to another node
  rather than being killed.
- The base image is managed declaratively by the template maintainer in
  [`../image`](../image); installing tooling the NixOS way is the intended
  workflow.
