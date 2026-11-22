# Per-start SSH signing key for Verified commits, registered on the owner's
# GitHub account through githubgate. No GitHub token of the owner's is used here
# or reaches the guest.
#
# Every start makes a new ed25519 key (it is destroyed with the start_count, so
# a stop drops it). A Job adds its public key to the account; at stop another
# Job deletes it. The Jobs run as development/coder-signing-keys, whose
# githubgate policy (coder/signing-keys) lets it list, create and delete the
# owner's signing keys with the owner's user access token (GitHubUserAuthorization
# ci/soliddowant). Their pods are intercepted by githubgate, so they call
# api.github.com with no credentials. The guest gets only the private key, from
# the cloud-init Secret into /run (tmpfs), and cannot add or delete keys.
#
# Deleting a RUNNING workspace runs `terraform destroy` with no stop first, so
# its key stays on the account. Its private key is gone with the VM, so the
# leftover key signs nothing new; delete it in the GitHub settings.
locals {
  signing_key_enabled = local.enable_github_integration && data.coder_workspace.me.start_count == 1

  # The script matches keys by the "(<workspace id>)" suffix, so renaming the
  # workspace keeps working.
  signing_key_title = "Coder ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name} (${data.coder_workspace.me.id})"

  # In the guest: written at every boot by cloud-init (bootcmd), on /run so it
  # never reaches the persistent disk.
  signing_key_dir  = "/run/coder-git-signing"
  signing_key_path = "${local.signing_key_dir}/key"

  signing_key_job_labels = merge(local.labels, {
    # Overrides the coder-workspace name: the coder-signing-keys netpol selects
    # these pods, the workspace netpol must not.
    "app.kubernetes.io/name"     = "coder-signing-keys"
    "app.kubernetes.io/instance" = "coder-signing-keys-${data.coder_workspace.me.id}"
    # githubgate injects its interceptor into labelled pods only.
    "githubgate.soliddowant.dev/inject" = "true"
  })

  # curl, jq and bash. Same image and digest as the zfs pool jobs.
  signing_key_job_image = "mirror.gcr.io/alpine/k8s:1.37.2@sha256:dcb7185e112a453aa72f426754849a97357727ef8f40168fb208c8cf59952042"
}

resource "tls_private_key" "git_signing" {
  count = local.signing_key_enabled ? 1 : 0

  algorithm = "ED25519"
}

locals {
  # Exactly one of the two Jobs exists: add while the workspace runs with the
  # integration on, remove otherwise (also when the integration is turned off
  # on a running workspace).
  signing_key_jobs = local.signing_key_enabled ? {
    add = {
      PUBLIC_KEY = trimspace(tls_private_key.git_signing[0].public_key_openssh)
    }
    } : {
    remove = {}
  }
}

resource "kubernetes_job_v1" "signing_key" {
  for_each = local.signing_key_jobs

  metadata {
    name        = "${local.name}-signing-key-${each.key}"
    namespace   = local.namespace
    labels      = local.signing_key_job_labels
    annotations = local.annotations
  }

  spec {
    backoff_limit           = 2
    active_deadline_seconds = 180

    template {
      metadata {
        labels      = local.signing_key_job_labels
        annotations = local.annotations
      }

      spec {
        service_account_name = "coder-signing-keys"
        # githubgate mounts its own projected token in the interceptor only.
        automount_service_account_token = false
        restart_policy                  = "Never"

        security_context {
          run_as_non_root = true
          run_as_user     = 65534
          run_as_group    = 65534
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name    = "signing-key"
          image   = local.signing_key_job_image
          command = ["bash", "-c", file("${path.module}/signing-key.sh")]

          env {
            name  = "MODE"
            value = each.key
          }
          env {
            name  = "TITLE"
            value = local.signing_key_title
          }
          env {
            name  = "WORKSPACE_ID"
            value = data.coder_workspace.me.id
          }
          dynamic "env" {
            for_each = each.value
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              memory = "64Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }

  # A start fails if the key can't be added, rather than letting the
  # workspace push unverified commits. The remove script never fails.
  wait_for_completion = true

  timeouts {
    create = "4m"
    update = "4m"
  }
}

# Point git at the key. In ~/.gitconfig (persistent), so every process signs,
# not only those the agent starts. Also cleans up what the coder
# git-commit-signing module left behind: it signed with the owner's Coder SSH
# key, which stayed on the account for good.
resource "coder_script" "git_signing" {
  agent_id     = coder_agent.main.id
  display_name = "Configure commit signing"
  icon         = "/icon/git.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 30 # seconds

  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    rm -rf "$HOME/.ssh/git-commit-signing"

    if [ -s "${local.signing_key_path}" ]; then
      git config --global gpg.format ssh
      git config --global user.signingkey "${local.signing_key_path}"
      git config --global commit.gpgsign true
      git config --global tag.gpgsign true
      echo "Commits are signed with this workspace's key (${local.signing_key_path})"
    else
      # No key (GitHub integration off): don't leave git pointing at a missing
      # key, or every commit fails.
      case "$(git config --global --get user.signingkey || true)" in
      "${local.signing_key_path}" | *git-commit-signing/coder)
        git config --global --unset user.signingkey
        git config --global --unset commit.gpgsign || true
        git config --global --unset tag.gpgsign || true
        ;;
      esac
      echo "No signing key: commits are not signed"
    fi
  EOT
}
