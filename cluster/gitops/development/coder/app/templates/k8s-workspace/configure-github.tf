# Parameters
locals {
  github_integration_order_start = 0
  github_integration_size        = 3
}

data "coder_parameter" "enable_github_integration" {
  name         = "enable_github_integration"
  display_name = "Enable GitHub integration"
  description  = "If enabled, configures Git to use your GitHub identity and uploads your SSH public key to GitHub for authentication."
  default      = "true"
  type         = "bool"
  form_type    = "checkbox"
  icon         = "/icon/github.svg"
  mutable      = true
  order        = local.github_integration_order_start + 0
}

locals {
  enable_github_integration = tobool(data.coder_parameter.enable_github_integration.value)
}

data "coder_parameter" "github_external_auth_permissions" {
  count = local.enable_github_integration ? 1 : 0

  name         = "github_external_auth_permissions"
  display_name = "GitHub workspace permissions"
  description  = "Select the GitHub external auth to use within the workspace. WARNING: This will expose your GitHub access token to Claude Code if enabled."
  default      = "github-restricted"
  type         = "string"
  form_type    = "radio"
  icon         = "/icon/github.svg"
  mutable      = true
  order        = local.github_integration_order_start + 1

  option {
    name  = "Default"
    value = "github"
  }

  option {
    name  = "Restricted - basic repo access only"
    value = "github-restricted"
  }

  option {
    name  = "None"
    value = ""
  }
}

locals {
  github_enable_in_workspace_auth = tobool(data.coder_parameter.enable_github_integration.value) && data.coder_parameter.github_external_auth_permissions[0].value != ""
  github_workspace_auth_id        = local.github_enable_in_workspace_auth ? data.coder_parameter.github_external_auth_permissions[0].value : ""
  github_workspace_token = local.github_enable_in_workspace_auth ? (
    local.github_workspace_auth_id == "github" ? data.coder_external_auth.github_in_workspace_full[0].access_token :
    local.github_workspace_auth_id == "github-restricted" ? data.coder_external_auth.github_in_workspace_restricted[0].access_token :
    ""
  ) : ""
}

data "coder_parameter" "install_github_cli" {
  count = local.github_enable_in_workspace_auth ? 1 : 0

  name         = "install_github_cli"
  display_name = "Install GitHub CLI"
  description  = "If enabled, installs the GitHub CLI (gh) in the workspace."
  default      = "true"
  type         = "bool"
  form_type    = "checkbox"
  icon         = "/icon/github.svg"
  order        = local.github_integration_order_start + 2
  mutable      = true
}

locals {
  install_github_cli = local.github_enable_in_workspace_auth && tobool(data.coder_parameter.install_github_cli[0].value)
}

# Resources
locals {
  # This can be "" in two cases:
  # * GitHub integration is disabled.
  # * The GitHub external auth is not available, which can happen when planning outside of a workspace context (like uploading a new version of this module).
  # This needs to be checked anywhere that depends on the provider being authenticated as the user.
  github_provisioner_token           = local.enable_github_integration ? data.coder_external_auth.github_provisioner[0].access_token : ""
  github_provisioner_token_available = local.github_provisioner_token != ""
}

provider "github" {
  token = local.enable_github_integration ? data.coder_external_auth.github_provisioner[0].access_token : ""
}

data "coder_external_auth" "github_provisioner" {
  count = local.enable_github_integration ? 1 : 0

  id = "github"
}

# For some weird reason there needs to be a data source for each option
data "coder_external_auth" "github_in_workspace_full" {
  count = local.enable_github_integration ? 1 : 0

  id = "github"
}

data "coder_external_auth" "github_in_workspace_restricted" {
  count = local.enable_github_integration ? 1 : 0

  id = "github-restricted"
}

module "git_commit_signing" {
  count   = local.enable_github_integration ? 1 : 0
  source  = "registry.coder.com/coder/git-commit-signing/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
}

data "github_user" "current" {
  count = local.github_provisioner_token_available ? 1 : 0

  username = ""
}

data "github_rest_api" "current_user_public_email" {
  count = local.github_provisioner_token_available ? 1 : 0

  endpoint = "/user/public_emails"
}

locals {
  pseudonym_email = local.github_provisioner_token_available ? "${data.github_user.current[0].id}+${data.github_user.current[0].login}@users.noreply.github.com" : ""
  public_emails   = local.github_provisioner_token_available ? [for email in jsondecode(data.github_rest_api.current_user_public_email[0].body) : email.email if email.primary && email.visibility == "public"] : []
  public_email    = length(local.public_emails) > 0 ? local.public_emails[0] : ""

  git_name = local.github_provisioner_token_available ? (
    data.github_user.current[0].name != "" ? data.github_user.current[0].name : data.github_user.current[0].login
  ) : ""
  git_email = local.github_provisioner_token_available ? (
    local.public_email != "" ? local.public_email : local.pseudonym_email
  ) : ""
}

resource "coder_env" "git_author_name" {
  count = local.git_name != "" ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_NAME"
  value    = local.git_name
}

resource "coder_env" "git_commmiter_name" {
  count = local.git_name != "" ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_NAME"
  value    = local.git_name
}

resource "coder_env" "git_author_email" {
  count = local.git_email != "" ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_EMAIL"
  value    = local.git_email
}

resource "coder_env" "git_commmiter_email" {
  count = local.git_email != "" ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_EMAIL"
  value    = local.git_email
}

resource "coder_script" "configure_git" {
  count = local.enable_github_integration ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Configure git"
  icon         = "/icon/git.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 15 # seconds

  script = file("./configure-git.sh")
}

resource "coder_script" "install_github_cli" {
  count = local.install_github_cli ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Install GitHub CLI"
  icon         = "/icon/github.svg"

  run_on_start       = true
  start_blocks_login = false
  timeout            = 30 # seconds

  script = <<-EOT
    #!/usr/bin/env bash

    set -euo pipefail

    sudo apt update
    DEBIAN_FRONTEND=noninteractive sudo apt install --no-install-recommends -y gh
    # This must be done via `gh auth login` because code-server filters out this variable specifically,
    # causing terminal subprocesses to not have it set.
    unset GITHUB_TOKEN
    echo "${local.github_workspace_token}" | gh auth login --with-token
    gh auth status
  EOT
}

# Set this mainly for other setup scripts that might need it, like code-server startup.
resource "coder_env" "github_token" {
  count = local.install_github_cli ? 1 : 0

  agent_id = coder_agent.main.id
  name     = "GITHUB_TOKEN"
  value    = local.github_workspace_token
}

# This can't use a github provider terraform resource because the key is account-specific,
# not workspace-specific. This would cause conflicts if multiple workspaces tried to manage it.
resource "coder_script" "github_upload_ssh_signing_keys" {
  count = local.github_provisioner_token_available ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Upload SSH Signing Keys to GitHub"
  icon         = "/icon/github.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 30 # seconds

  script = templatefile("./upload-ssh-signing-keys.sh.tftpl", {
    GITHUB_TOKEN     = local.github_provisioner_token
    PUBLIC_KEY       = trimspace(data.coder_workspace_owner.me.ssh_public_key)
    SIGNING_KEY_NAME = "Coder @ ${data.coder_workspace.me.access_url}"
  })
}
