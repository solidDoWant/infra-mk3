# Development Tools Installation
# Each tool has its own parameter(s) and separate installation script for parallel execution

# Parameter ordering
locals {
  tools_order_start = local.repo_setup_order_start + local.repo_setup_size
  tools_size        = 17 # Total number of tool parameters
}

# ============================================================================
# Go
# ============================================================================

data "coder_parameter" "enable_go" {
  type         = "bool"
  name         = "enable_go"
  display_name = "Install Go"
  default      = "false"
  description  = "Install the Go programming language"
  mutable      = true
  icon         = "/icon/go.svg"
  order        = local.go_enable_order
  form_type    = "checkbox"
}

locals {
  go_enable_order  = local.tools_order_start
  go_version_order = local.go_enable_order + 1
}

data "coder_parameter" "go_version" {
  type         = "string"
  name         = "go_version"
  display_name = "Go Version"
  default      = "1.23"
  description  = "The version of Go to install"
  mutable      = false
  icon         = "/icon/go.svg"
  order        = local.go_version_order

  option {
    name  = "1.21"
    value = "1.21"
  }
  option {
    name  = "1.22"
    value = "1.22"
  }
  option {
    name  = "1.23"
    value = "1.23"
  }
  option {
    name  = "Latest"
    value = "latest"
  }
}

resource "coder_script" "install_go" {
  count              = data.coder_parameter.enable_go.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Go"
  icon               = "/icon/go.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-go.sh.tftpl", {
    GO_VERSION = data.coder_parameter.go_version.value
  })
}

# ============================================================================
# .NET SDK
# ============================================================================

data "coder_parameter" "enable_dotnet" {
  type         = "bool"
  name         = "enable_dotnet"
  display_name = "Install .NET SDK"
  default      = "false"
  description  = "Install the .NET SDK"
  mutable      = true
  icon         = "/icon/dotnet.svg"
  order        = local.dotnet_enable_order
  form_type    = "checkbox"
}

locals {
  dotnet_enable_order  = local.go_version_order + 1
  dotnet_version_order = local.dotnet_enable_order + 1
}

data "coder_parameter" "dotnet_version" {
  type         = "string"
  name         = "dotnet_version"
  display_name = ".NET SDK Version"
  default      = "8.0"
  description  = "The version of .NET SDK to install"
  mutable      = false
  icon         = "/icon/dotnet.svg"
  order        = local.dotnet_version_order

  option {
    name  = "6.0"
    value = "6.0"
  }
  option {
    name  = "7.0"
    value = "7.0"
  }
  option {
    name  = "8.0 (LTS)"
    value = "8.0"
  }
  option {
    name  = "9.0"
    value = "9.0"
  }
  option {
    name  = "10.0"
    value = "10.0"
  }
}

resource "coder_script" "install_dotnet" {
  count              = data.coder_parameter.enable_dotnet.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install .NET SDK"
  icon               = "/icon/dotnet.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-dotnet.sh.tftpl", {
    DOTNET_VERSION = data.coder_parameter.dotnet_version.value
  })
}

# ============================================================================
# Docker CLI
# ============================================================================

data "coder_parameter" "enable_docker" {
  type         = "bool"
  name         = "enable_docker"
  display_name = "Install Docker CLI"
  default      = "false"
  description  = "Install Docker CLI and tools (docker, buildx, compose)"
  mutable      = true
  icon         = "/icon/docker.svg"
  order        = local.docker_enable_order
  form_type    = "checkbox"
}

locals {
  docker_enable_order = local.dotnet_version_order + 1
}

resource "coder_script" "install_docker" {
  count              = data.coder_parameter.enable_docker.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Docker CLI"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-docker.sh.tftpl", {})
}

# ============================================================================
# Python Tools (uv/uvx)
# ============================================================================

data "coder_parameter" "enable_python_tools" {
  type         = "bool"
  name         = "enable_python_tools"
  display_name = "Install Python Tools"
  default      = "false"
  description  = "Install uv and uvx for Python package management"
  mutable      = true
  icon         = "/icon/python.svg"
  order        = local.python_tools_enable_order
  form_type    = "checkbox"
}

locals {
  python_tools_enable_order = local.docker_enable_order + 1
}

resource "coder_script" "install_python_tools" {
  count              = data.coder_parameter.enable_python_tools.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Python Tools"
  icon               = "/icon/python.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-python-tools.sh.tftpl", {})
}

# ============================================================================
# Node.js
# ============================================================================

data "coder_parameter" "enable_node" {
  type         = "bool"
  name         = "enable_node"
  display_name = "Install Node.js"
  default      = "false"
  description  = "Install Node.js, npm, and npx"
  mutable      = true
  icon         = "/icon/nodejs.svg"
  order        = local.node_enable_order
  form_type    = "checkbox"
}

locals {
  node_enable_order  = local.python_tools_enable_order + 1
  node_version_order = local.node_enable_order + 1
}

data "coder_parameter" "node_version" {
  type         = "string"
  name         = "node_version"
  display_name = "Node.js Version"
  default      = "20"
  description  = "The version of Node.js to install"
  mutable      = false
  icon         = "/icon/nodejs.svg"
  order        = local.node_version_order

  option {
    name  = "18 LTS"
    value = "18"
  }
  option {
    name  = "20 LTS"
    value = "20"
  }
  option {
    name  = "22"
    value = "22"
  }
  option {
    name  = "Latest"
    value = "latest"
  }
}

resource "coder_script" "install_node" {
  count              = data.coder_parameter.enable_node.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Node.js"
  icon               = "/icon/nodejs.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-node.sh.tftpl", {
    NODE_VERSION = data.coder_parameter.node_version.value
  })
}

# ============================================================================
# kubectl
# ============================================================================

data "coder_parameter" "enable_kubectl" {
  type         = "bool"
  name         = "enable_kubectl"
  display_name = "Install kubectl"
  default      = "false"
  description  = "Install Kubernetes kubectl CLI"
  mutable      = true
  icon         = "/icon/k8s.svg"
  order        = local.kubectl_enable_order
  form_type    = "checkbox"
}

locals {
  kubectl_enable_order  = local.node_version_order + 1
  kubectl_version_order = local.kubectl_enable_order + 1
}

data "coder_parameter" "kubectl_version" {
  type         = "string"
  name         = "kubectl_version"
  display_name = "kubectl Version"
  default      = "1.34"
  description  = "The Kubernetes version for kubectl (e.g., 1.34)"
  mutable      = false
  icon         = "/icon/k8s.svg"
  order        = local.kubectl_version_order

  option {
    name  = "1.31"
    value = "1.31"
  }
  option {
    name  = "1.32"
    value = "1.32"
  }
  option {
    name  = "1.33"
    value = "1.33"
  }
  option {
    name  = "1.34"
    value = "1.34"
  }
}

resource "coder_script" "install_kubectl" {
  count              = data.coder_parameter.enable_kubectl.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install kubectl"
  icon               = "/icon/k8s.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-kubectl.sh.tftpl", {
    KUBECTL_VERSION = data.coder_parameter.kubectl_version.value
  })
}

# ============================================================================
# Flux
# ============================================================================

data "coder_parameter" "enable_flux" {
  type         = "bool"
  name         = "enable_flux"
  display_name = "Install Flux"
  default      = "false"
  description  = "Install Flux CLI for GitOps"
  mutable      = true
  icon         = "/icon/k8s.svg"
  order        = local.flux_enable_order
  form_type    = "checkbox"
}

locals {
  flux_enable_order = local.kubectl_version_order + 1
}

resource "coder_script" "install_flux" {
  count              = data.coder_parameter.enable_flux.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Flux"
  icon               = "/icon/k8s.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-flux.sh.tftpl", {})
}

# ============================================================================
# Helm
# ============================================================================

data "coder_parameter" "enable_helm" {
  type         = "bool"
  name         = "enable_helm"
  display_name = "Install Helm"
  default      = "false"
  description  = "Install Helm package manager for Kubernetes"
  mutable      = true
  icon         = "/icon/k8s.svg"
  order        = local.helm_enable_order
  form_type    = "checkbox"
}

locals {
  helm_enable_order = local.flux_enable_order + 1
}

resource "coder_script" "install_helm" {
  count              = data.coder_parameter.enable_helm.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Helm"
  icon               = "/icon/k8s.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-helm.sh.tftpl", {})
}

# ============================================================================
# Krew
# ============================================================================

data "coder_parameter" "enable_krew" {
  type         = "bool"
  name         = "enable_krew"
  display_name = "Install Krew"
  default      = "false"
  description  = "Install Krew kubectl plugin manager"
  mutable      = true
  icon         = "/icon/k8s.svg"
  order        = local.krew_enable_order
  form_type    = "checkbox"
}

locals {
  krew_enable_order = local.helm_enable_order + 1
}

resource "coder_script" "install_krew" {
  count              = data.coder_parameter.enable_krew.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Krew"
  icon               = "/icon/k8s.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-krew.sh.tftpl", {})
}

# ============================================================================
# Talos Tools
# ============================================================================

data "coder_parameter" "enable_talos_tools" {
  type         = "bool"
  name         = "enable_talos_tools"
  display_name = "Install Talos Tools"
  default      = "false"
  description  = "Install talosctl and talhelper for Talos Linux"
  mutable      = true
  icon         = "/icon/k8s.svg"
  order        = local.talos_tools_enable_order
  form_type    = "checkbox"
}

locals {
  talos_tools_enable_order = local.krew_enable_order + 1
}

resource "coder_script" "install_talos_tools" {
  count              = data.coder_parameter.enable_talos_tools.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Talos Tools"
  icon               = "/icon/k8s.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-talos-tools.sh.tftpl", {})
}

# ============================================================================
# Terraform Tools
# ============================================================================

data "coder_parameter" "enable_terraform_tools" {
  type         = "bool"
  name         = "enable_terraform_tools"
  display_name = "Install Terraform Tools"
  default      = "false"
  description  = "Install Terraform and tflint"
  mutable      = true
  icon         = "/icon/gateway.svg"
  order        = local.terraform_tools_enable_order
  form_type    = "checkbox"
}

locals {
  terraform_tools_enable_order  = local.talos_tools_enable_order + 1
  terraform_tools_version_order = local.terraform_tools_enable_order + 1
}

data "coder_parameter" "terraform_version" {
  type         = "string"
  name         = "terraform_version"
  display_name = "Terraform Version"
  default      = "latest"
  description  = "The version of Terraform to install"
  mutable      = false
  icon         = "/icon/gateway.svg"
  order        = local.terraform_tools_version_order

  option {
    name  = "Latest"
    value = "latest"
  }
  option {
    name  = "1.9.0"
    value = "1.9.0"
  }
  option {
    name  = "1.8.0"
    value = "1.8.0"
  }
  option {
    name  = "1.7.0"
    value = "1.7.0"
  }
}

resource "coder_script" "install_terraform_tools" {
  count              = data.coder_parameter.enable_terraform_tools.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Terraform Tools"
  icon               = "/icon/gateway.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-terraform-tools.sh.tftpl", {
    TERRAFORM_VERSION = data.coder_parameter.terraform_version.value
  })
}

# ============================================================================
# PostgreSQL Client
# ============================================================================

data "coder_parameter" "enable_postgresql" {
  type         = "bool"
  name         = "enable_postgresql"
  display_name = "Install PostgreSQL Client"
  default      = "false"
  description  = "Install PostgreSQL command-line client (psql)"
  mutable      = true
  icon         = "/icon/postgres.svg"
  order        = local.postgresql_enable_order
  form_type    = "checkbox"
}

locals {
  postgresql_enable_order = local.terraform_tools_version_order + 1
}

resource "coder_script" "install_postgresql" {
  count              = data.coder_parameter.enable_postgresql.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install PostgreSQL Client"
  icon               = "/icon/postgres.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-postgresql.sh.tftpl", {})
}

# ============================================================================
# Teleport
# ============================================================================

data "coder_parameter" "enable_teleport" {
  type         = "bool"
  name         = "enable_teleport"
  display_name = "Install Teleport"
  default      = "false"
  description  = "Install Teleport CLI (tsh)"
  mutable      = true
  icon         = "/icon/terminal.svg"
  order        = local.teleport_enable_order
  form_type    = "checkbox"
}

locals {
  teleport_enable_order = local.postgresql_enable_order + 1
}

resource "coder_script" "install_teleport" {
  count              = data.coder_parameter.enable_teleport.value ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Install Teleport"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false
  timeout            = 300

  script = templatefile("./install-teleport.sh.tftpl", {})
}
