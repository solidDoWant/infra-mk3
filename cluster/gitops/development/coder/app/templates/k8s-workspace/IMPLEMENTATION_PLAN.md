# Development Tools Installation - Implementation Plan

## Overview

Refactor the tools installation to support parallel execution with separate scripts per tool, proper version selection, and consistent installation methods.

## Key Changes

1. **Separate scripts**: Each tool/tool-group gets its own script file and `coder_script` resource
2. **Bash variable conversion**: Terraform vars converted to bash vars at script start with validation
3. **Version selection**: Support version parameters where applicable, defaulting to latest
4. **Installation hierarchy**: Prefer apt > dpkg > tarball > install script
5. **Global installation**: All tools installed system-wide, not per-user
6. **Remove enable_tools**: Tools available regardless of Claude Code setting
7. **Consistent locals blocks**: Add ordering locals after each enable parameter

## File Structure

### New Script Files (in current directory)

1. `install-go.sh.tftpl` - Go installation
2. `install-dotnet.sh.tftpl` - .NET SDK installation
3. `install-docker.sh.tftpl` - Docker CLI tools installation
4. `install-python-tools.sh.tftpl` - uv/uvx installation
5. `install-node.sh.tftpl` - Node.js/npm/npx installation
6. `install-kubectl.sh.tftpl` - kubectl installation
7. `install-flux.sh.tftpl` - Flux installation
8. `install-helm.sh.tftpl` - Helm installation
9. `install-krew.sh.tftpl` - Krew installation
10. `install-talos-tools.sh.tftpl` - talosctl and talhelper installation
11. `install-terraform-tools.sh.tftpl` - terraform and tflint installation
12. `install-postgresql.sh.tftpl` - PostgreSQL client installation
13. `install-teleport.sh.tftpl` - Teleport tsh installation

### Modified Files

1. `tools.tf` - Complete rewrite with:
   - Individual enable parameters for each tool
   - Version parameters where applicable
   - Separate `coder_script` resources for each tool
   - Proper ordering via locals blocks
   - Remove `enable_tools` master parameter

2. `claude.tf` - Update ordering to reference tools

3. Delete: `install-tools.sh.tftpl` (replaced by individual scripts)

## Parameter Structure

### Go
- `enable_go` (bool, default: false, icon: /icon/go.svg)
- `go_version` (string, default: "1.23", options: ["1.21", "1.22", "1.23", "latest"])

### .NET SDK
- `enable_dotnet` (bool, default: false, icon: /icon/dotnet.svg)
- `dotnet_version` (string, default: "8.0", options: ["6.0", "7.0", "8.0", "9.0", "10.0"])

### Docker CLI
- `enable_docker` (bool, default: false, icon: /icon/docker.svg)
- No version parameter (latest via apt)

### Python Tools (uv/uvx)
- `enable_python_tools` (bool, default: false, icon: /icon/python.svg)
- No version parameter (latest via tarball)

### Node.js
- `enable_node` (bool, default: false, icon: /icon/nodejs.svg)
- `node_version` (string, default: "20", options: ["18", "20", "22", "latest"])

### Kubernetes Tools
- `enable_kubectl` (bool, default: false, icon: /icon/k8s.svg)
- `kubectl_version` (string, default: "1.34", description: "Kubernetes version for kubectl")
- `enable_flux` (bool, default: false, icon: /icon/k8s.svg)
- `enable_helm` (bool, default: false, icon: /icon/k8s.svg)
- `enable_krew` (bool, default: false, icon: /icon/k8s.svg)

### Talos Tools
- `enable_talos_tools` (bool, default: false, icon: /icon/k8s.svg)
- No version parameters (latest via install script)

### Terraform Tools
- `enable_terraform_tools` (bool, default: false, icon: /icon/gateway.svg)
- `terraform_version` (string, default: "latest", description: "Terraform version")
- No tflint version (latest via apt)

### PostgreSQL Client
- `enable_postgresql` (bool, default: false, icon: /icon/postgres.svg)
- No version parameter (PostgreSQL 16 via apt)

### Teleport
- `enable_teleport` (bool, default: false, icon: /icon/terminal.svg)
- No version parameter (latest stable via apt)

## Installation Methods by Tool

### 1. Go (`install-go.sh.tftpl`)
**Method**: APT for versions 1.21-1.23, Tarball for "latest"
```bash
if [ "$GO_VERSION" = "latest" ]; then
  # Download and install latest from go.dev
  wget https://go.dev/dl/go<version>.linux-amd64.tar.gz
  sudo tar -C /usr/local -xzf go<version>.linux-amd64.tar.gz
  # Add to PATH via /etc/profile.d/go.sh
else
  sudo apt-get update
  sudo apt-get install -y golang-${GO_VERSION}
fi
```

### 2. .NET SDK (`install-dotnet.sh.tftpl`)
**Method**: APT (use backports PPA for 9.0+)
```bash
if [ "$DOTNET_VERSION" = "8.0" ]; then
  sudo apt-get update
  sudo apt-get install -y dotnet-sdk-8.0
else
  sudo add-apt-repository ppa:dotnet/backports -y
  sudo apt-get update
  sudo apt-get install -y dotnet-sdk-${DOTNET_VERSION}
fi
```

### 3. Docker CLI (`install-docker.sh.tftpl`)
**Method**: APT (Docker official repository)
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt-get update
sudo apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin
```

### 4. Python Tools (`install-python-tools.sh.tftpl`)
**Method**: Tarball to /usr/local/bin
```bash
cd /tmp
wget https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-gnu.tar.gz
sudo tar xf uv-x86_64-unknown-linux-gnu.tar.gz --strip-components=1 -C /usr/local/bin \
  uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx
rm uv-x86_64-unknown-linux-gnu.tar.gz
```

### 5. Node.js (`install-node.sh.tftpl`)
**Method**: APT (NodeSource PPA for specific versions, tarball for latest)
```bash
if [ "$NODE_VERSION" = "latest" ]; then
  # Download and install latest LTS tarball
  wget https://nodejs.org/dist/v<latest>/node-v<latest>-linux-x64.tar.xz
  sudo tar --strip-components 1 -xf node-v<latest>-linux-x64.tar.xz --directory /usr/local
else
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
```

### 6. kubectl (`install-kubectl.sh.tftpl`)
**Method**: APT (Kubernetes official repository)
```bash
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBECTL_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

### 7. Flux (`install-flux.sh.tftpl`)
**Method**: Install script (tarball)
```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```

### 8. Helm (`install-helm.sh.tftpl`)
**Method**: APT (Helm community repository)
```bash
sudo apt-get install -y curl gpg apt-transport-https
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | \
  gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | \
  sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm
```

### 9. Krew (`install-krew.sh.tftpl`)
**Method**: Install script (per-user, then make global)
```bash
# Install krew for the coder user
cd "$(mktemp -d)"
OS="$(uname | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64$/arm64/')"
KREW="krew-${OS}_${ARCH}"
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
tar zxf "${KREW}.tar.gz"
./"${KREW}" install krew

# Add to PATH in /etc/profile.d/
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' | sudo tee /etc/profile.d/krew.sh
```

### 10. Talos Tools (`install-talos-tools.sh.tftpl`)
**Method**: Install scripts
```bash
# Install talosctl
curl -sL https://talos.dev/install | sudo sh

# Install talhelper
curl -sL https://i.jpillora.com/talhelper | sudo bash
```

### 11. Terraform Tools (`install-terraform-tools.sh.tftpl`)
**Method**: APT for both (HashiCorp repository)
```bash
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update

# Install terraform (version specific if not latest)
if [ "$TERRAFORM_VERSION" = "latest" ]; then
  sudo apt-get install -y terraform
else
  sudo apt-get install -y terraform=${TERRAFORM_VERSION}
fi

# Install tflint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | sudo bash
```

### 12. PostgreSQL Client (`install-postgresql.sh.tftpl`)
**Method**: APT
```bash
sudo apt-get update
sudo apt-get install -y postgresql-client
```

### 13. Teleport (`install-teleport.sh.tftpl`)
**Method**: APT (Teleport official repository)
```bash
sudo curl -fsSL https://deb.releases.teleport.dev/teleport-pubkey.asc \
  -o /usr/share/keyrings/teleport-archive-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] https://apt.releases.teleport.dev/ubuntu noble stable" | \
  sudo tee /etc/apt/sources.list.d/teleport.list
sudo apt-get update
sudo apt-get install -y teleport
```

## Script Template Pattern

All scripts will follow this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Convert Terraform variables to bash variables
# shellcheck disable=SC2269
TOOL_VAR="${TOOL_VAR}"
: "${TOOL_VAR:?TOOL_VAR is not set}"

# Optional variable (may be empty)
# shellcheck disable=SC2269
OPTIONAL_VAR="${OPTIONAL_VAR}"

# Installation logic here
echo "Installing [tool] version $${TOOL_VAR}..."

# Installation commands

# Verify installation
command -v tool_binary || { echo "Installation failed"; exit 1; }
```

## Terraform Resource Pattern

Each tool gets a `coder_script` resource:

```hcl
resource "coder_script" "install_tool" {
  count            = data.coder_parameter.enable_tool.value ? 1 : 0
  agent_id         = coder_agent.main.id
  display_name     = "Install Tool"
  icon             = "/icon/tool.svg"
  run_on_start     = true
  start_blocks_login = false
  timeout          = 300

  script = templatefile("${path.module}/install-tool.sh.tftpl", {
    TOOL_VAR = data.coder_parameter.tool_var.value
  })
}
```

## Parameter Ordering

Current ordering (from research):
- workspace_resources: start=0, size=2
- coder: start=2, size=3
- code_server: start=5, size=1

New ordering:
- workspace_resources: start=0, size=2
- coder: start=2, size=3
- code_server: start=5, size=1
- **tools: start=6, size=~25** (will calculate exact size)
  - Go: 2 parameters (enable, version)
  - .NET: 2 parameters (enable, version)
  - Docker: 1 parameter (enable)
  - Python tools: 1 parameter (enable)
  - Node: 2 parameters (enable, version)
  - kubectl: 2 parameters (enable, version)
  - Flux: 1 parameter (enable)
  - Helm: 1 parameter (enable)
  - Krew: 1 parameter (enable)
  - Talos tools: 1 parameter (enable)
  - Terraform tools: 2 parameters (enable, version)
  - PostgreSQL: 1 parameter (enable)
  - Teleport: 1 parameter (enable)
  - **Total: 17 parameters**

Updated ordering in claude.tf:
```hcl
locals {
  claude_order_start = local.tools_order_start + local.tools_size
  claude_size        = 1
}
```

## Icon Mapping

Based on verification, use these icons:
- Go: `/icon/go.svg` ✓
- .NET: `/icon/dotnet.svg` ✓
- Docker: `/icon/docker.svg` ✓
- Python tools: `/icon/python.svg` ✓
- Node: `/icon/nodejs.svg` (not node.svg)
- kubectl: `/icon/k8s.svg` (not kubernetes.svg)
- Flux: `/icon/k8s.svg`
- Helm: `/icon/k8s.svg`
- Krew: `/icon/k8s.svg`
- Talos tools: `/icon/k8s.svg`
- Terraform tools: `/icon/gateway.svg` (not terraform.svg)
- PostgreSQL: `/icon/postgres.svg` ✓
- Teleport: `/icon/terminal.svg` (not teleport.svg)

## Implementation Steps

1. Create all 13 script template files
2. Rewrite tools.tf with:
   - Parameter definitions
   - Locals blocks for ordering
   - coder_script resources
3. Update claude.tf ordering reference
4. Delete old install-tools.sh.tftpl
5. Test with Terraform validation
6. Push new template version to Coder
7. Test workspace creation with various tool combinations

## Testing Strategy

1. Validate Terraform configuration
2. Create test workspace with all tools enabled
3. Verify each tool installs correctly
4. Check tool versions match requested versions
5. Verify tools are in PATH and executable
6. Test parallel execution timing

## Notes

- All scripts use `set -euo pipefail` for safety
- All scripts validate required variables with `: "${VAR:?message}"`
- All scripts use `sudo` for global installation
- Scripts timeout at 300 seconds (5 minutes) - may need adjustment for slow connections
- Some tools (krew) are inherently per-user but we add to system PATH
- Version "latest" requires special handling (dynamic version detection)
