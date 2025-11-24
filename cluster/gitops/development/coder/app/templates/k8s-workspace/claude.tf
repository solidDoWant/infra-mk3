locals {
  claude_code_group   = "claude-users"
  allow_claude_access = contains(data.coder_workspace_owner.me.groups, local.claude_code_group)
}

# Parameters
locals {
  claude_order_start = local.tools_order_start + local.tools_size
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
data "kubernetes_secret" "claude_oauth_token" {
  count = local.allow_claude_access ? 1 : 0

  metadata {
    name      = "coder-claude-oauth-token"
    namespace = local.namespace
  }
}

module "claude_code" {
  count = local.enable_claude_code ? 1 : 0

  source  = "registry.coder.com/coder/claude-code/coder"
  version = "~> 4.2"

  agent_id            = coder_agent.main.id
  disable_autoupdater = true
  cli_app             = true

  subdomain = true

  model                        = "sonnet"
  workdir                      = local.repo_directory
  dangerously_skip_permissions = true
  permission_mode              = "bypassPermissions"

  # mcp = "" # TODO

  claude_code_oauth_token = data.kubernetes_secret.claude_oauth_token[0].data["CLAUDE_CODE_OAUTH_TOKEN"]
}

# ***************************************
# TODO enable these in the future once tasks work better. Not enabling this now because task parameters cannot be configured yet, except for the prompt.
# ***************************************
# data "coder_parameter" "ai_prompt" {
#   count = local.enable_claude_code ? 1 : 0
#
#   type = "string"
#   name = "AI Prompt"
#   # default     = ""
#   # description = "Initial task prompt for Claude Code."
#   # mutable     = true
# }
#
# resource "coder_ai_task" "task" {
#   count = local.enable_claude_code ? 1 : 0
#
#   app_id = module.claude_code.task_app_id
# }
