# GitHub access through githubgate interception. No GitHub credential of the
# owner's (no Coder GitHub login, no token) is ever in the workspace.
#
# githubgate's webhook injects its interceptor into the VM's launcher pod (the
# label and listen annotation in vm.tf); the guest image sends the three GitHub
# hosts to it (image modules/githubgate). The interceptor adds the launcher
# pod's ServiceAccount token, which never enters the guest, and the githubgate
# proxy decides each request by this workspace's GitHubAccessPolicy below,
# then sends it with an installation token of the App on the owner's account
# (GitHubInstallation ci/soliddowant). So:
# - PRs, issues and comments are made by the App (ghgate[bot]); commits are
#   the owner's, signed with the per-start key (signing-keys.tf).
# - Only the owner's repositories are writable, within the installation's
#   ceiling (contents, pull requests, issues, checks, statuses). Public
#   repositories of other owners are readable, and github.com downloads work.
# - git must use HTTPS; the image rewrites SSH GitHub URLs.

# Parameters
locals {
  github_integration_order_start = 0
  github_integration_size        = 3

  # The installation's owner, also the user the signing keys are added for
  # (GitHubUserAuthorization ci/soliddowant). Repository names in the policy
  # are under it. The id is GitHub's (public, fixed) user id.
  github_owner    = "solidDoWant"
  github_owner_id = 16456946
}

data "coder_parameter" "github_access" {
  name         = "github_access"
  display_name = "GitHub access"
  description  = <<-EOT
    What the workspace may do on your GitHub repositories (below), through
    githubgate. Nothing in the workspace holds a GitHub token. PRs, issues and
    comments are made by the GitHub App, commits are yours and signed.
    Contribute is for agents: changes reach the default branch only through
    PRs, which it can't merge, and branch names need a "/" (feat/x, fix/y).
  EOT
  default      = "contribute"
  type         = "string"
  form_type    = "radio"
  icon         = "/icon/github.svg"
  mutable      = true
  order        = local.github_integration_order_start + 0

  option {
    name        = "Read only"
    description = "Read code, PRs, issues and checks"
    value       = "read"
  }

  option {
    name        = "Contribute"
    description = "Push branches with a \"/\" in the name, open PRs and issues, comment. No pushes to the default branch, no merges"
    value       = "contribute"
  }

  option {
    name        = "Full"
    description = "Everything the GitHub App allows: push any branch, merge PRs, set statuses and checks"
    value       = "full"
  }

  option {
    name        = "None"
    description = "No access to your repositories; public repositories and github.com downloads only"
    value       = "none"
  }
}

data "coder_parameter" "github_repositories" {
  name         = "github_repositories"
  display_name = "GitHub repositories"
  description  = "Your repositories the access above applies to, comma-separated names (\"toolgate, vault-sync\") or \"*\" for all. Empty: the cloned repository, if it is one of yours."
  default      = ""
  type         = "string"
  icon         = "/icon/github.svg"
  mutable      = true
  order        = local.github_integration_order_start + 1

  validation {
    regex = "^[ ]*(\\*|[A-Za-z0-9._-]+)?([ ]*,[ ]*[A-Za-z0-9._-]+)*[ ]*$"
    error = "Use comma-separated repository names, or \"*\"."
  }
}

data "coder_parameter" "github_workflows" {
  name         = "github_workflows"
  display_name = "GitHub workflow changes"
  description  = <<-EOT
    With Full access, also let the workspace change files under
    .github/workflows (GitHub's "workflows" permission). Only repositories
    the installation's ceiling allows it for accept it (ci/githubgate/config/app.yaml);
    on any other repository the policy is rejected.
  EOT
  default      = "false"
  type         = "bool"
  icon         = "/icon/github.svg"
  mutable      = true
  order        = local.github_integration_order_start + 2
}

locals {
  github_access = data.coder_parameter.github_access.value

  # The cloned repository's name, when it is one of the owner's on github.com.
  github_cloned_repository = try(
    regex("(?i)^https://github\\.com/${local.github_owner}/([^/]+?)(?:\\.git)?/?$", local.repo_clone_url)[0],
    "",
  )
  github_repositories_param = compact([for name in split(",", data.coder_parameter.github_repositories.value) : trimspace(name)])
  github_repositories       = length(local.github_repositories_param) > 0 ? local.github_repositories_param : compact([local.github_cloned_repository])

  # Each preset within the installation's ceiling (ci/githubgate/config/app.yaml).
  github_presets = {
    read = {
      permissions = {
        contents      = "read"
        pull_requests = "read"
        issues        = "read"
        checks        = "read"
        statuses      = "read"
      }
      proxy = {}
    }
    contribute = {
      permissions = {
        contents      = "write"
        pull_requests = "write"
        issues        = "write"
        checks        = "read"
        statuses      = "read"
      }
      proxy = {
        # Branches whose name has a "/" (a `*` segment never spans "/"), so
        # never a default branch like master or main, and no tags. With
        # pushRefs set, githubgate also refuses PR merges and contents-API
        # writes, whose branch it can't check.
        pushRefs = ["refs/heads/*/**"]
      }
    }
    full = {
      permissions = {
        contents      = "write"
        pull_requests = "write"
        issues        = "write"
        checks        = "write"
        statuses      = "write"
      }
      proxy = {}
    }
  }

  # A GraphQL request gets one token for every exact repository name in the
  # caller's rules, at the lowest level any of them has (githubgate can't tell
  # which repositories a query touches). So the rules below never put an
  # exact repository with less access next to the chosen ones: a read-only
  # one would make every GraphQL write (gh pr create) fail. Rules with only
  # `*` patterns don't take part in GraphQL tokens.
  github_main_rule_exact = length([for name in local.github_repositories : name if !strcontains(name, "*")]) > 0
  github_main_rule       = local.github_access != "none" && length(local.github_repositories) > 0

  # Public repositories of other owners (git clone, nix flake inputs, the REST
  # API) and github.com downloads (releases). publicRead needs a rule naming a
  # repository without `*`, so it goes on the main rule when that names one.
  github_public_proxy = {
    publicRead = true
    webPaths   = true
  }

  github_repository_rules = local.github_main_rule ? [
    {
      name = "repositories"
      installationRef = {
        namespace = "ci"
        name      = "soliddowant"
      }
      repositories = local.github_repositories
      permissions = merge(
        local.github_presets[local.github_access].permissions,
        local.github_access == "full" && data.coder_parameter.github_workflows.value ? { workflows = "write" } : {},
      )
      proxy = merge(
        { enabled = true },
        local.github_presets[local.github_access].proxy,
        local.github_main_rule_exact ? local.github_public_proxy : {},
      )
    }
  ] : []

  github_other_rules = concat(
    [
      # Reading toolgate, whose Claude Code plugin marketplace the workspace
      # clones (toolgate.tf). A pattern, so it stays out of GraphQL tokens.
      {
        name = "toolgate"
        installationRef = {
          namespace = "ci"
          name      = "soliddowant"
        }
        repositories = ["toolgate*"]
        permissions = {
          contents = "read"
        }
        proxy = {
          enabled = true
        }
      }
    ],
    # Without a main rule naming an exact repository (None, or "*"), public
    # reads need a rule of their own. GraphQL then reaches only toolgate,
    # read-only; with "*" it can't reach the chosen repositories anyway
    # (githubgate needs exact names for GraphQL).
    local.github_main_rule_exact ? [] : [
      {
        name = "public"
        installationRef = {
          namespace = "ci"
          name      = "soliddowant"
        }
        repositories = ["toolgate"]
        permissions = {
          contents = "read"
        }
        proxy = merge({ enabled = true }, local.github_public_proxy)
      }
    ],
  )
}

# Resources

# The launcher pod's identity, one per workspace so each gets its own policy.
# It has no RBAC. Teleport (teleport-vm-workspace.yaml) and the token policy
# (vm-workspace-tokens.yaml) admit coder-vm-workspace-*.
resource "kubernetes_service_account_v1" "workspace" {
  metadata {
    name        = local.name
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  automount_service_account_token = false
}

resource "kubectl_manifest" "github_policy" {
  server_side_apply = true
  wait              = false
  ignore_fields     = ["status"]

  yaml_body = yamlencode({
    apiVersion = "githubgate.soliddowant.dev/v1alpha1"
    kind       = "GitHubAccessPolicy"
    metadata = {
      name        = local.name
      namespace   = local.namespace
      labels      = local.labels
      annotations = local.annotations
    }
    spec = {
      serviceAccounts = [kubernetes_service_account_v1.workspace.metadata[0].name]
      rules           = concat(local.github_repository_rules, local.github_other_rules)
    }
  })
}

# git identity. For GitHub to show a commit as Verified, the committer email
# must belong to the account the signing key is on (signing-keys.tf: the
# GitHubUserAuthorization's login). The account's noreply address always
# does; the Coder account's email may not (it gave "unknown_key").
locals {
  git_name  = data.coder_workspace_owner.me.full_name != "" ? data.coder_workspace_owner.me.full_name : data.coder_workspace_owner.me.name
  git_email = "${local.github_owner_id}+${local.github_owner}@users.noreply.github.com"
}

resource "coder_env" "git_author_name" {
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_NAME"
  value    = local.git_name
}

resource "coder_env" "git_committer_name" {
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_NAME"
  value    = local.git_name
}

resource "coder_env" "git_author_email" {
  agent_id = coder_agent.main.id
  name     = "GIT_AUTHOR_EMAIL"
  value    = local.git_email
}

resource "coder_env" "git_committer_email" {
  agent_id = coder_agent.main.id
  name     = "GIT_COMMITTER_EMAIL"
  value    = local.git_email
}

# gh needs a token to run; the interceptor replaces this placeholder. The
# image sets it too, for shells not started by the agent.
resource "coder_env" "gh_token" {
  agent_id = coder_agent.main.id
  name     = "GH_TOKEN"
  value    = "githubgate"
}

# Earlier template versions authenticated gh with Coder's GitHub login: a
# wrapper in ~/.local/bin (persistent) that fetches a token from the agent, and
# possibly a stored login. Both would now fail or bypass githubgate.
resource "coder_script" "github_cleanup" {
  agent_id     = coder_agent.main.id
  display_name = "Remove the old GitHub login"
  icon         = "/icon/github.svg"

  run_on_start       = true
  start_blocks_login = false
  timeout            = 30 # seconds

  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    wrapper="$HOME/.local/bin/gh"
    if [ -f "$wrapper" ] && grep -q 'Generated by the "Authenticate GitHub CLI" coder_script' "$wrapper"; then
      rm -f "$wrapper"
      echo "Removed the old gh wrapper"
    fi
    env -u GH_TOKEN -u GITHUB_TOKEN /run/current-system/sw/bin/gh auth logout --hostname github.com </dev/null >/dev/null 2>&1 || true
  EOT
}
