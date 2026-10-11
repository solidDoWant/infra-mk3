locals {
  claude_code_group   = "claude-users"
  allow_claude_access = contains(data.coder_workspace_owner.me.groups, local.claude_code_group)
}

# Parameters
locals {
  claude_order_start = local.repo_setup_order_start + local.repo_setup_size
  claude_size        = 1
}

data "coder_parameter" "enable_claude_code" {
  count = local.allow_claude_access ? 1 : 0

  type        = "bool"
  name        = "Enable Claude Code"
  default     = "true"
  description = "Enable Claude Code AI assistant in this workspace."
  mutable     = true
  icon        = "/icon/claude.svg"
  order       = local.claude_order_start + 0
}

locals {
  enable_claude_code = local.allow_claude_access && tobool(data.coder_parameter.enable_claude_code[0].value)
}

# Resources
data "kubernetes_secret_v1" "claude_oauth_token" {
  count = local.allow_claude_access ? 1 : 0

  metadata {
    name      = "coder-claude-oauth-token"
    namespace = local.namespace
  }
}

module "claude_code" {
  count = local.enable_claude_code ? 1 : 0

  source  = "registry.coder.com/coder/claude-code/coder"
  version = "~> 5.5"

  agent_id            = coder_agent.main.id
  disable_autoupdater = true
  model               = "sonnet"
  workdir             = local.repo_directory

  # Start every session in bypassPermissions without the one-time confirmation.
  managed_settings = {
    permissions = {
      defaultMode = "bypassPermissions"
    }
    skipDangerousModePermissionPrompt = true
  }

  # mcp = "" # TODO

  claude_code_oauth_token = data.kubernetes_secret_v1.claude_oauth_token[0].data["CLAUDE_CODE_OAUTH_TOKEN"]
}

# The module creates no app; this launches an interactive session in the
# workspace directory.
resource "coder_app" "claude_code" {
  count = local.enable_claude_code ? 1 : 0

  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    set -e
    cd "${local.repo_directory}"
    exec claude
  EOT
}
