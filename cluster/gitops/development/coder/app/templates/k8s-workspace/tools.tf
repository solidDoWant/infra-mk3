# Parameters
locals {
  tools_order_start = local.repo_setup_order_start + local.repo_setup_size
  tools_size        = 1 + local.go_size + local.dotnet_size + local.docker_size + local.python_tools_size + local.node_tools_size + local.k8s_tools_size + local.terraform_tools_size + local.psql_size + local.teleport_size
}

data "coder_parameter" "enable_tools" {
  count = local.allow_claude_access ? 1 : 0

  type         = "bool"
  name         = "enable_tools"
  display_name = "Enable Development Tools"
  default      = "false"
  description  = "Enable installation of development tools in this workspace."
  mutable      = true
  icon         = "/icon/wrench.svg"
  order        = local.tools_order_start + 0
  form_type    = "switch"
}

locals {
  enable_tools = local.allow_claude_access && local.enable_claude_code && tobool(data.coder_parameter.enable_tools[0].value)
}

# Go parameters
locals {
  go_order_start = local.tools_order_start + 1
  go_size        = 2
}

data "coder_parameter" "enable_go" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_go"
  display_name = "Install Go"
  default      = "false"
  description  = "Install the Go programming language."
  mutable      = true
  icon         = "/icon/go.svg"
  order        = local.go_order_start + 0
  form_type    = "checkbox"
}

data "coder_parameter" "go_version" {
  count = local.enable_tools && tobool(data.coder_parameter.enable_go[0].value) ? 1 : 0

  type         = "string"
  name         = "go_version"
  display_name = "Go version"
  default      = "1.23.5"
  description  = "The version of Go to install."
  mutable      = true
  icon         = "/icon/go.svg"
  order        = local.go_order_start + 1
}

locals {
  enable_go  = local.enable_tools && tobool(data.coder_parameter.enable_go[0].value)
  go_version = local.enable_go ? data.coder_parameter.go_version[0].value : ""
}

# .NET SDK parameters
locals {
  dotnet_order_start = local.go_order_start + local.go_size
  dotnet_size        = 2
}

data "coder_parameter" "enable_dotnet" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_dotnet"
  display_name = "Install .NET SDK"
  default      = "false"
  description  = "Install the .NET SDK."
  mutable      = true
  icon         = "/icon/dotnet.svg"
  order        = local.dotnet_order_start + 0
  form_type    = "checkbox"
}

data "coder_parameter" "dotnet_version" {
  count = local.enable_tools && tobool(data.coder_parameter.enable_dotnet[0].value) ? 1 : 0

  type         = "string"
  name         = "dotnet_version"
  display_name = ".NET version"
  default      = "9.0"
  description  = "The version of .NET SDK to install."
  mutable      = true
  icon         = "/icon/dotnet.svg"
  order        = local.dotnet_order_start + 1
}

locals {
  enable_dotnet  = local.enable_tools && tobool(data.coder_parameter.enable_dotnet[0].value)
  dotnet_version = local.enable_dotnet ? data.coder_parameter.dotnet_version[0].value : ""
}

# Docker parameters
locals {
  docker_order_start = local.dotnet_order_start + local.dotnet_size
  docker_size        = 1
}

data "coder_parameter" "enable_docker" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_docker"
  display_name = "Install Docker"
  default      = "false"
  description  = "Install Docker CLI and tools."
  mutable      = true
  icon         = "/icon/docker.svg"
  order        = local.docker_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_docker = local.enable_tools && tobool(data.coder_parameter.enable_docker[0].value)
}

# Python tools parameters
locals {
  python_tools_order_start = local.docker_order_start + local.docker_size
  python_tools_size        = 1
}

data "coder_parameter" "enable_python_tools" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_python_tools"
  display_name = "Install Python Tools (uv, uvx)"
  default      = "false"
  description  = "Install uv and uvx for Python package management."
  mutable      = true
  icon         = "/icon/python.svg"
  order        = local.python_tools_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_python_tools = local.enable_tools && tobool(data.coder_parameter.enable_python_tools[0].value)
}

# Node tools parameters
locals {
  node_tools_order_start = local.python_tools_order_start + local.python_tools_size
  node_tools_size        = 1
}

data "coder_parameter" "enable_node_tools" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_node_tools"
  display_name = "Install Node Tools (node, npm, npx)"
  default      = "false"
  description  = "Install Node.js, npm, and npx."
  mutable      = true
  icon         = "/icon/node.svg"
  order        = local.node_tools_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_node_tools = local.enable_tools && tobool(data.coder_parameter.enable_node_tools[0].value)
}

# Kubernetes tools parameters
locals {
  k8s_tools_order_start = local.node_tools_order_start + local.node_tools_size
  k8s_tools_size        = 1
}

data "coder_parameter" "enable_k8s_tools" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_k8s_tools"
  display_name = "Install Kubernetes Tools"
  default      = "false"
  description  = "Install kubectl, flux, helm, krew, talosctl, and talhelper."
  mutable      = true
  icon         = "/icon/kubernetes.svg"
  order        = local.k8s_tools_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_k8s_tools = local.enable_tools && tobool(data.coder_parameter.enable_k8s_tools[0].value)
}

# Terraform tools parameters
locals {
  terraform_tools_order_start = local.k8s_tools_order_start + local.k8s_tools_size
  terraform_tools_size        = 1
}

data "coder_parameter" "enable_terraform_tools" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_terraform_tools"
  display_name = "Install Terraform Tools"
  default      = "false"
  description  = "Install terraform and tflint."
  mutable      = true
  icon         = "/icon/terraform.svg"
  order        = local.terraform_tools_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_terraform_tools = local.enable_tools && tobool(data.coder_parameter.enable_terraform_tools[0].value)
}

# PostgreSQL client parameters
locals {
  psql_order_start = local.terraform_tools_order_start + local.terraform_tools_size
  psql_size        = 1
}

data "coder_parameter" "enable_psql" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_psql"
  display_name = "Install PostgreSQL Client (psql)"
  default      = "false"
  description  = "Install the PostgreSQL command-line client."
  mutable      = true
  icon         = "/icon/postgres.svg"
  order        = local.psql_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_psql = local.enable_tools && tobool(data.coder_parameter.enable_psql[0].value)
}

# Teleport parameters
locals {
  teleport_order_start = local.psql_order_start + local.psql_size
  teleport_size        = 1
}

data "coder_parameter" "enable_teleport" {
  count = local.enable_tools ? 1 : 0

  type         = "bool"
  name         = "enable_teleport"
  display_name = "Install Teleport"
  default      = "false"
  description  = "Install Teleport CLI (tsh)."
  mutable      = true
  icon         = "/icon/teleport.svg"
  order        = local.teleport_order_start + 0
  form_type    = "checkbox"
}

locals {
  enable_teleport = local.enable_tools && tobool(data.coder_parameter.enable_teleport[0].value)
}

# Installation script
resource "coder_script" "install_tools" {
  count = local.enable_tools ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Install Development Tools"
  icon         = "/icon/wrench.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 600 # seconds (10 minutes)

  script = templatefile("./install-tools.sh.tftpl", {
    ENABLE_GO              = local.enable_go
    GO_VERSION             = local.go_version
    ENABLE_DOTNET          = local.enable_dotnet
    DOTNET_VERSION         = local.dotnet_version
    ENABLE_DOCKER          = local.enable_docker
    ENABLE_PYTHON_TOOLS    = local.enable_python_tools
    ENABLE_NODE_TOOLS      = local.enable_node_tools
    ENABLE_K8S_TOOLS       = local.enable_k8s_tools
    ENABLE_TERRAFORM_TOOLS = local.enable_terraform_tools
    ENABLE_PSQL            = local.enable_psql
    ENABLE_TELEPORT        = local.enable_teleport
  })
}
