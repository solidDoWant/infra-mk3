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

  # MCP configuration is screwed up due to a dumb bug in the module. Work around this by patching the .claude.json file with jq.
  # See https://github.com/coder/registry/issues/562
  # mcp = local.mcp_servers_encoded
  post_install_script = local.mcp_servers_json != null ? (
    <<-EOT
    #!/bin/bash
    set -euo pipefail

    CLAUDE_CONFIG_PATH="$HOME/.claude.json"
    MCP_SERVERS="$(echo ${base64encode(local.mcp_servers_json)} | base64 --decode)"

    if [ ! -f "$CLAUDE_CONFIG_PATH" ]; then
      2>&1 echo "Claude config file not found at $CLAUDE_CONFIG_PATH"
      exit 1
    fi

    # Use jq to patch each object under '.projects' with the MCP configuration
    jq --argjson mcpServers "$MCP_SERVERS" '
      .projects |= with_entries(
        .value.mcpServers = $mcpServers.mcpServers + (.value.mcpServers // {})
      )
    ' "$CLAUDE_CONFIG_PATH" > "$${CLAUDE_CONFIG_PATH}.tmp"
    mv "$${CLAUDE_CONFIG_PATH}.tmp" "$CLAUDE_CONFIG_PATH"
  EOT
  ) : null

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
