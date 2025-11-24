---
display_name: Workspace on Kubernetes (standard)
description: Provision a workspace using Kubernetes resources directly
icon: /icon/k8s.svg
maintainer_github: solidDoWant
verified: true
tags: [kubernetes, container]
---

# Workspace on Kubernetes (standard)

Create a new workspace in a Kubernetes pod. Full root, kernel, and egress internet access is available. Connect via the web or local [VS Code](https://code.visualstudio.com/).

Image is based on [this](https://github.com/coder/images/tree/main/images/base).

> [!WARNING]
> Only the user's home directory (`~/`) is saved across restarts.

