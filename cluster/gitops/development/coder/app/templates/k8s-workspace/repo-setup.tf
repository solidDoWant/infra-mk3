# Parameters
locals {
  repo_setup_order_start = local.github_integration_order_start + local.github_integration_size
  repo_setup_size        = 1 + local.repo_clone_size + local.repo_create_size
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
    name  = "Create new repository"
    value = "create"
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

# Create parameters
locals {
  repo_create_order_start = local.repo_clone_order_start + local.repo_clone_size
  repo_create_size        = 4
}

data "coder_parameter" "create_repo_name" {
  count = local.repo_should_create ? 1 : 0

  name         = "create_repo_name"
  display_name = "Repository name"
  description  = "The name of the repository to create."
  type         = "string"
  icon         = "/icon/git.svg"
  mutable      = false
  order        = local.repo_create_order_start + 0
}

data "coder_parameter" "create_github_repo" {
  count = local.repo_should_create && local.github_provisioner_token_available ? 1 : 0

  name         = "create_github_repo"
  display_name = "Create GitHub repository"
  description  = "Whether to create an upstream GitHub repository."
  default      = "true"
  type         = "bool"
  icon         = "/icon/github.svg"
  mutable      = false
  order        = local.repo_create_order_start + 1
}

locals {
  # Magic value that is used to indicate "use the current user"
  repo_create_default_owner = "<current user>"
}

data "coder_parameter" "github_repo_owner" {
  count = local.repo_create_github_repo && local.github_provisioner_token_available ? 1 : 0

  name         = "github_repo_owner"
  display_name = "GitHub Repository owner"
  description  = "The GitHub user or organization under which to create the repository."
  default      = local.repo_create_default_owner
  type         = "string"
  icon         = "/icon/github.svg"
  mutable      = false
  order        = local.repo_create_order_start + 2
}

data "coder_parameter" "github_repo_private" {
  count = local.repo_create_github_repo && local.github_provisioner_token_available ? 1 : 0

  name         = "github_repo_private"
  display_name = "GitHub repository visibility"
  description  = "True to create a private repository, false for public."
  default      = "false"
  type         = "bool"
  icon         = "/icon/github.svg"
  mutable      = false
  order        = local.repo_create_order_start + 3
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

  repo_should_create      = data.coder_parameter.repo_setup.value == "create"
  repo_create_name        = local.repo_should_create ? data.coder_parameter.create_repo_name[0].value : ""
  repo_create_github_repo = local.repo_should_create && tobool(data.coder_parameter.create_github_repo[0].value)
  repo_create_github_owner = local.repo_should_create && local.repo_create_github_repo ? (
    data.coder_parameter.github_repo_owner[0].value != local.repo_create_default_owner ? data.coder_parameter.github_repo_owner[0].value : ""
  ) : ""
  repo_create_github_repo_private = local.repo_should_create && local.repo_create_github_repo && data.coder_parameter.github_repo_private[0].value
  repo_create_directory           = local.repo_should_create ? "${local.repo_base_directory}/${local.repo_create_name}" : ""

  repo_directory = local.repo_should_clone ? local.repo_clone_directory : (local.repo_should_create ? local.repo_create_directory : local.repo_base_directory)
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

# Create resources
resource "coder_script" "create_repo" {
  count = local.repo_should_create ? 1 : 0

  agent_id     = coder_agent.main.id
  display_name = "Create repository"
  icon         = local.repo_create_github_repo ? "/icon/github.svg" : "/icon/git.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 30 # seconds

  script = templatefile("./create-repo.sh.tftpl", {
    REPO_NAME                = local.repo_create_name
    CREATE_GITHUB_REPO       = local.repo_create_github_repo
    GITHUB_OWNER             = local.repo_create_github_owner
    MAKE_GITHUB_REPO_PRIVATE = local.repo_create_github_repo_private
    REPO_DIR                 = local.repo_create_directory
  })
}
