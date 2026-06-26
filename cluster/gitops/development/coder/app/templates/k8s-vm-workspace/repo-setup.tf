# Parameters
locals {
  repo_setup_order_start = local.github_integration_order_start + local.github_integration_size
  repo_setup_size        = 1 + local.repo_clone_size
}

data "coder_parameter" "repo_setup" {
  name         = "repo_setup"
  display_name = "Repository setup"
  description  = "Choose how to set up your workspace repository."
  default      = "clone"
  type         = "string"
  form_type    = "radio"
  icon         = "/icon/git.svg"
  mutable      = false
  order        = local.repo_setup_order_start + 0

  option {
    name  = "Clone existing repository"
    value = "clone"
  }

  option {
    name  = "Do nothing"
    value = "none"
  }
}

# Clone parameters
locals {
  repo_clone_order_start = local.repo_setup_order_start + 1
  repo_clone_size        = 2
}

data "coder_parameter" "clone_repo_url" {
  count = data.coder_parameter.repo_setup.value == "clone" ? 1 : 0

  name         = "clone_repo_url"
  display_name = "Repository URL"
  description  = "The URL of the repository to clone."
  default      = ""
  type         = "string"
  icon         = "/icon/git.svg"
  mutable      = false
  order        = local.repo_clone_order_start + 0

  validation {
    error = "The repository URL must be a valid Git HTTPS URL ending with .git"
    # This conditional is needed because of https://github.com/coder/coder/issues/12686
    regex = local.is_workspace_plan ? trimspace(<<-EOT
      ^https:\/\/(?:[\w\-\.]+@)?[\w\-\.]+\/[\w\-\.\/]+(?:\.git)?$
    EOT
    ) : ".*"
  }
}

locals {
  # Magic value that is used to indicate "use the default branch"
  default_branch_value = "<default branch>"
}

data "coder_parameter" "clone_repo_branch" {
  count = data.coder_parameter.repo_setup.value == "clone" ? 1 : 0

  name         = "clone_repo_branch"
  display_name = "Repository branch"
  description  = "The branch of the repository to clone."
  default      = local.default_branch_value
  type         = "string"
  icon         = "/icon/git.svg"
  mutable      = false
  order        = local.repo_clone_order_start + 1
}

# Coalesce parameter values
locals {
  repo_base_directory = "/workspace"

  repo_should_clone = data.coder_parameter.repo_setup.value == "clone"
  repo_clone_url    = local.repo_should_clone ? data.coder_parameter.clone_repo_url[0].value : ""
  repo_clone_branch = local.repo_should_clone ? (
    data.coder_parameter.clone_repo_branch[0].value != local.default_branch_value ? data.coder_parameter.clone_repo_branch[0].value : ""
  ) : ""
  repo_clone_url_parts = local.repo_should_clone ? split("/", local.repo_clone_url) : []
  repo_clone_directory = local.repo_should_clone ? "${local.repo_base_directory}/${trimsuffix(local.repo_clone_url_parts[length(local.repo_clone_url_parts) - 1], ".git")}" : ""

  repo_directory = local.repo_should_clone ? local.repo_clone_directory : local.repo_base_directory
}

# Clone resources
resource "coder_script" "clone_repo" {
  count = local.repo_should_clone ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Clone repository"
  icon         = "/icon/git.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 300 # seconds

  script = templatefile("./clone-repo.sh.tftpl", {
    REPO_URL    = local.repo_clone_url
    REPO_BRANCH = local.repo_clone_branch
    REPO_DIR    = local.repo_clone_directory
  })
}
