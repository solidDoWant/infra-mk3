# Parameters
locals {
  nix_order_start = local.code_server_order_start + local.code_server_size
  nix_size        = 2
}

data "coder_parameter" "enable_nix" {
  name         = "enable_nix"
  display_name = "Install Nix (daemonless)"
  description  = "If enabled, installs Nix in single-user (daemonless) mode. Nix will be available in the workspace shell after startup."
  default      = "false"
  type         = "bool"
  form_type    = "checkbox"
  icon         = "/icon/nix.svg"
  mutable      = true
  order        = local.nix_order_start + 0
}

data "coder_parameter" "nix_store_disk_size" {
  name         = "nix_store_disk_size"
  display_name = "Nix store disk size"
  description  = "Size of the persistent /nix store cache disk in GB. Only used when Nix is enabled."
  default      = "20"
  type         = "number"
  icon         = "/icon/nix.svg"
  mutable      = true
  order        = local.nix_order_start + 1

  validation {
    min       = 1
    max       = 100
    monotonic = "increasing"
  }
}

locals {
  enable_nix = tobool(data.coder_parameter.enable_nix.value)
}

# Resources
resource "coder_script" "install_nix" {
  count = local.enable_nix ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Install Nix"
  icon         = "/icon/nix.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 300 # seconds — nix download can be slow

  script = <<-EOT
    #!/usr/bin/env bash

    set -euo pipefail

    if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      echo "Nix is already installed, skipping."
      exit 0
    fi

    curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
  EOT
}
