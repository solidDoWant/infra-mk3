# toolgate: Claude Code in the workspace reaches MCP servers through the
# toolgate gateway, signed in as the workspace owner with no `toolgate login`.
#
# - User identity: Coder external auth `toolgate` (Authentik provider
#   `coder-toolgate`) holds the owner's consent. The CLI gets an access token
#   from `coder external-auth access-token toolgate`, set as the CLI's token
#   command with `toolgate configure` (not an environment variable: Claude
#   Code removes credential-like variables, such as *_TOKEN_*, from plugin
#   helpers).
# - Workspace attestation: the pod's projected service-account token with
#   audience `toolgate`, set with `toolgate configure`. The gateway checks
#   the pod's Coder labels against the user and marks the session attested as
#   coder/<owner>/<workspace>.

# Parameters
locals {
  toolgate_order_start = local.nix_order_start + local.nix_size
  toolgate_size        = 1
}

data "coder_parameter" "enable_toolgate" {
  name         = "enable_toolgate"
  display_name = "Enable toolgate"
  description  = "If enabled, installs the toolgate CLI and Claude Code plugin, and signs Claude Code in to the toolgate MCP gateway as you, with this workspace attested."
  default      = "true"
  type         = "bool"
  form_type    = "checkbox"
  icon         = "/emojis/1f6e1-fe0f.png"
  mutable      = true
  order        = local.toolgate_order_start + 0
}

locals {
  enable_toolgate = tobool(data.coder_parameter.enable_toolgate.value)
  # The public domain comes from the coder-workspace-cluster-info ConfigMap
  # (local.public_domain): the template never sees Flux substitution, and
  # Coder's access URL inside the cluster is the internal service URL.
  toolgate_gateway          = "https://toolgate.${local.public_domain}"
  toolgate_attestation_dir  = "/var/run/secrets/toolgate"
  toolgate_attestation_file = "${local.toolgate_attestation_dir}/token"
}

# Optional: a workspace still starts if the owner hasn't linked toolgate; the
# CLI then prints Coder's link message.
data "coder_external_auth" "toolgate" {
  count = local.enable_toolgate ? 1 : 0

  id       = "toolgate"
  optional = true
}

# Resources
resource "coder_env" "toolgate_gateway" {
  count = local.enable_toolgate ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "TOOLGATE_GATEWAY"
  value    = local.toolgate_gateway
}

# Installs the latest toolgate CLI (checksum-verified) and the toolgate Claude
# Code plugin, with its gateway URL. The Claude Code module installs `claude`
# in parallel, so wait for it.
resource "coder_script" "install_toolgate" {
  count = local.enable_toolgate ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Install toolgate"
  icon         = "/emojis/1f6e1-fe0f.png"

  run_on_start       = true
  start_blocks_login = false
  timeout            = 600 # seconds

  script = <<-EOT
    #!/usr/bin/env bash

    set -euo pipefail

    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"

    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    BASE="https://github.com/solidDoWant/toolgate/releases/latest/download"
    curl -fsSL -o "$WORK/toolgate-linux-amd64" "$BASE/toolgate-linux-amd64"
    curl -fsSL -o "$WORK/checksums.txt" "$BASE/checksums.txt"
    (cd "$WORK" && grep ' toolgate-linux-amd64$' checksums.txt | sha256sum -c -)
    install -m 0755 "$WORK/toolgate-linux-amd64" "$BIN_DIR/toolgate"
    echo "Installed $(toolgate version)"

    # Sign-in settings go in the CLI's config file: the plugin's helpers
    # don't get credential-like environment variables. The token command reads
    # the agent token from a 0600 file for the same reason.
    install -d -m 700 "$HOME/.config/coder"
    (umask 077 && printf '%s' "$CODER_AGENT_TOKEN" > "$HOME/.config/coder/agent-token")
    toolgate configure \
      --gateway "${local.toolgate_gateway}" \
      --token-command "coder external-auth access-token toolgate --agent-token-file $HOME/.config/coder/agent-token" \
      --attestation-token-file "${local.toolgate_attestation_file}"

    for _ in $(seq 1 120); do
      command -v claude >/dev/null 2>&1 && break
      sleep 5
    done
    if ! command -v claude >/dev/null 2>&1; then
      echo "Claude Code isn't installed; skipping the toolgate plugin."
      exit 0
    fi

    claude plugin marketplace add solidDoWant/toolgate || claude plugin marketplace update toolgate
    claude plugin install toolgate@toolgate --scope user || true
    printf '{"gateway_url":"%s"}' "${local.toolgate_gateway}" | claude plugin configure toolgate@toolgate --values-stdin
  EOT
}
