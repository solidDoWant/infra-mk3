# Parameters
locals {
  code_server_order_start = local.coder_order_start + local.workspace_resources_size
  code_server_size        = 1
}

data "coder_parameter" "trust_workspace" {
  name         = "trust_workspace"
  display_name = "Trust workspace automatically"
  description  = "True if the workspace should be trusted automatically, false to always prompt"
  default      = "true"
  type         = "bool"
  icon         = "/emojis/1f512.png" # TODO change to /emojis/1f6e1.png once https://github.com/coder/coder/issues/20836 is fixed
  mutable      = true
  order        = local.code_server_order_start + 0

  form_type = "switch"
}

locals {
  code_server_icon = "/icon/code-insiders.svg"
  code_server_name = "VS Code Web"
  code_server_slug = "code-server"

  port           = "13337"
  base_url       = "http://localhost:${local.port}"
  open_directory = local.repo_directory
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = local.code_server_slug
  display_name = local.code_server_name
  icon         = local.code_server_icon

  url       = "${local.base_url}?folder=${local.open_directory}"
  open_in   = "tab"
  subdomain = true

  healthcheck {
    url       = "${local.base_url}/healthz"
    interval  = 3
    threshold = 10
  }
}

resource "coder_script" "code_server" {
  agent_id     = coder_agent.main.id
  display_name = local.code_server_name
  icon         = local.code_server_icon

  run_on_start       = true
  start_blocks_login = true
  timeout            = 90 # seconds

  script = templatefile("./install-code-server.sh.tftpl", {
    PORT            = local.port
    TRUST_WORKSPACE = data.coder_parameter.trust_workspace.value
  })
}
