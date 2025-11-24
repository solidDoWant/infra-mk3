# Parameters
locals {
  coder_order_start = local.workspace_resources_order_start + local.workspace_resources_size
  coder_size        = 1
}

data "coder_parameter" "coder_login" {
  type        = "bool"
  name        = "Coder Token"
  default     = "true"
  description = "True to load the Coder session token into the environment, false otherwise. WARNING: This will expose your Coder session token to Claude Code if enabled."
  icon        = "/icon/coder.svg"
  mutable     = true
  order       = local.coder_order_start + 0
}

locals {
  coder_login = tobool(data.coder_parameter.coder_login.value)
}

# Resources
resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  dynamic "metadata" {
    for_each = local.pvcs
    content {
      display_name = title("${metadata.key} Disk")
      key          = "${index(keys(local.pvcs), metadata.key) + 2}_disk"
      script       = "coder stat disk --path \"${metadata.value.mount_path}\""
      interval     = 60
      timeout      = 1
    }
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "${length(local.pvcs) + 2}_load_host"
    # get load avg scaled by number of cores
    script   = <<-EOT
      echo "$(cat /proc/loadavg | awk '{ print $1 }') $(nproc)" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  api_key_scope      = "all"
  connection_timeout = 30 # seconds

  resources_monitoring {
    memory {
      enabled   = true
      threshold = 80
    }

    dynamic "volume" {
      for_each = local.pvcs
      content {
        enabled   = true
        threshold = 90
        path      = volume.value.mount_path
      }
    }
  }
}

resource "coder_env" "coder_session_token" {
  count = local.coder_login ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "CODER_SESSION_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "coder_url" {
  count = local.coder_login ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "CODER_URL"
  value    = data.coder_workspace.me.access_url
}

locals {
  # This is the best indicator available for whether or not the plan is actually running for a workspace or not.
  is_workspace_plan = local.github_provisioner_token_available
}
