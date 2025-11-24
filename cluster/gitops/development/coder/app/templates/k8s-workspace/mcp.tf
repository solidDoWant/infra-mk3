# MCP Servers Configuration
# This section allows users to enable MCP (Model Context Protocol) servers
# for enhanced AI capabilities in their workspace.

# Parameters
locals {
  mcp_order_start = local.claude_order_start + local.claude_size
  mcp_size        = 7 # enable_mcp + 6 individual servers
}

# Top-level MCP toggle
data "coder_parameter" "enable_mcp_servers" {
  count = local.enable_claude_code ? 1 : 0

  type        = "bool"
  name        = "Enable MCP Servers"
  default     = "false"
  description = "Enable MCP (Model Context Protocol) servers for enhanced AI capabilities."
  mutable     = true
  icon        = "/icon/widgets.svg"
  order       = local.mcp_order_start + 0
}

locals {
  enable_mcp_servers = local.enable_claude_code && length(data.coder_parameter.enable_mcp_servers) > 0 && tobool(data.coder_parameter.enable_mcp_servers[0].value)
}

# Individual MCP server toggles

# Playwright MCP
data "coder_parameter" "enable_mcp_playwright" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "Playwright MCP"
  default     = "false"
  description = "Browser automation using Playwright. Enables web scraping and testing capabilities."
  mutable     = true
  icon        = "/icon/playwright.svg"
  order       = local.mcp_order_start + 1
}

# Coder MCP
data "coder_parameter" "enable_mcp_coder" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "Coder MCP"
  default     = "false"
  description = "Interact with the Coder API for workspace and template management."
  mutable     = true
  icon        = "/icon/coder.svg"
  order       = local.mcp_order_start + 2
  styling     = local.coder_login ? null : jsonencode({ disabled = true })
}

# Kubernetes MCP
data "coder_parameter" "enable_mcp_kubernetes" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "Kubernetes MCP"
  default     = "false"
  description = "Query Kubernetes resources in the cluster."
  mutable     = true
  icon        = "/icon/k8s.svg"
  order       = local.mcp_order_start + 3
}

# GitHub MCP
data "coder_parameter" "enable_mcp_github" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "GitHub MCP"
  default     = "false"
  description = "Access GitHub issues, PRs, and repository information."
  mutable     = true
  icon        = "/icon/github.svg"
  order       = local.mcp_order_start + 4
}

# Memory MCP
data "coder_parameter" "enable_mcp_memory" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "Memory MCP"
  default     = "false"
  description = "Persistent memory using a local knowledge graph. Remembers information across sessions."
  mutable     = true
  icon        = "/icon/memory.svg"
  order       = local.mcp_order_start + 5
}

# Context7 MCP
data "coder_parameter" "enable_mcp_context7" {
  count = local.enable_mcp_servers ? 1 : 0

  type        = "bool"
  name        = "Context7 MCP"
  default     = "false"
  description = "Context7 documentation lookup for libraries and frameworks."
  mutable     = true
  icon        = "/icon/book.svg"
  order       = local.mcp_order_start + 6
}

# Compute which servers are enabled
locals {
  mcp_playwright_enabled  = local.enable_mcp_servers && length(data.coder_parameter.enable_mcp_playwright) > 0 && tobool(data.coder_parameter.enable_mcp_playwright[0].value)
  mcp_coder_enabled       = local.enable_mcp_servers && local.coder_login && length(data.coder_parameter.enable_mcp_coder) > 0 && tobool(data.coder_parameter.enable_mcp_coder[0].value)
  mcp_kubernetes_enabled  = local.enable_mcp_servers && length(data.coder_parameter.enable_mcp_kubernetes) > 0 && tobool(data.coder_parameter.enable_mcp_kubernetes[0].value)
  mcp_github_enabled      = local.enable_mcp_servers && length(data.coder_parameter.enable_mcp_github) > 0 && tobool(data.coder_parameter.enable_mcp_github[0].value)
  mcp_memory_enabled      = local.enable_mcp_servers && length(data.coder_parameter.enable_mcp_memory) > 0 && tobool(data.coder_parameter.enable_mcp_memory[0].value)
  mcp_context7_enabled    = local.enable_mcp_servers && length(data.coder_parameter.enable_mcp_context7) > 0 && tobool(data.coder_parameter.enable_mcp_context7[0].value)
}

# Build the MCP configuration object
locals {
  mcp_servers = merge(
    local.mcp_playwright_enabled ? {
      playwright = {
        command = "npx"
        args    = ["@playwright/mcp@0.0.48"]
      }
    } : {},
    local.mcp_coder_enabled ? {
      coder = {
        command = "coder"
        args    = ["exp", "mcp", "server"]
      }
    } : {},
    local.mcp_kubernetes_enabled ? {
      kubernetes = {
        command = "npx"
        args    = ["-y", "kubernetes-mcp-server@0.0.54"]
      }
    } : {},
    local.mcp_github_enabled ? {
      github = {
        serverUrl = "https://api.githubcopilot.com/mcp/"
      }
    } : {},
    local.mcp_memory_enabled ? {
      memory = {
        command = "npx"
        args    = ["-y", "@modelcontextprotocol/server-memory@0.6.3"]
        env = {
          MEMORY_FILE_PATH = "/home/coder/.claude/memory.json"
        }
      }
    } : {},
    local.mcp_context7_enabled ? {
      context7 = {
        command = "npx"
        args    = ["-y", "@upstash/context7-mcp@1.0.29"]
      }
    } : {}
  )

  # Only include mcpServers wrapper if there are servers enabled
  mcp_config = length(local.mcp_servers) > 0 ? jsonencode({
    mcpServers = local.mcp_servers
  }) : null
}

# Kubernetes service account for MCP server
resource "kubernetes_service_account" "mcp_k8s_viewer" {
  count = local.mcp_kubernetes_enabled ? 1 : 0

  metadata {
    name        = "${local.name}-mcp-k8s"
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }
}
