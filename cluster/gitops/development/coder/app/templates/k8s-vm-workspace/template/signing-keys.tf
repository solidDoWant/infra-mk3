# Per-start SSH signing key for Verified commits, registered on the owner's
# GitHub account through githubgate. No GitHub token of the owner's is used here
# or reaches the guest.
#
# Every start makes a new ed25519 key (it is destroyed with the start_count, so
# a stop drops it). A Job adds its public key to the account; at stop another
# Job deletes it. The guest gets the private key from a Secret, shared with the
# VM over virtiofs (vm.tf, image modules/git-signing); it is never written in
# the guest, and it goes with the Secret at stop. The Jobs run as this
# workspace's coder-signing-keys-<id> ServiceAccount, whose githubgate policy
# lets it list, create and delete the owner's signing keys with the owner's
# user access token (GitHubUserAuthorization ci/soliddowant). The account,
# policy and netpol live as long as the workspace, so githubgate's audit log
# names the workspace behind every key change. Their pods are intercepted by githubgate, so they call
# api.github.com with no credentials. The guest gets only the private key, and
# cannot add or delete keys.
#
# Deleting a RUNNING workspace runs `terraform destroy` with no stop first, so
# its key stays on the account. Its private key is gone with the VM, so the
# leftover key signs nothing new; delete it in the GitHub settings.
locals {
  # Every running workspace signs; this does not depend on the GitHub
  # integration parameter.
  signing_key_enabled = data.coder_workspace.me.start_count == 1

  # The script matches keys by the "(<workspace id>)" suffix, so renaming the
  # workspace keeps working.
  signing_key_title = "Coder ${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name} (${data.coder_workspace.me.id})"

  signing_key_secret = "${local.name}-git-signing-key"
  # Not under coder-vm-workspace-*: the launcher pod's account must never get
  # a user rule (the coder Kyverno policy in coder/app/rbac.yaml).
  signing_key_account = "coder-signing-keys-${data.coder_workspace.me.id}"
  # In the guest: the Secret's `key`, through the image's git-signing module.
  signing_key_path = "/run/coder-git-signing/key"

  signing_key_job_labels = merge(local.labels, {
    # Overrides the coder-workspace name: the workspace netpol must not select
    # these pods; the signing-key netpol below does.
    "app.kubernetes.io/name"     = "coder-signing-keys"
    "app.kubernetes.io/instance" = local.signing_key_account
    # githubgate injects its interceptor into labelled pods only.
    "githubgate.soliddowant.dev/inject" = "true"
  })

  # curl, jq and bash. Same image and digest as the zfs pool jobs.
  signing_key_job_image = "mirror.gcr.io/alpine/k8s:1.37.2@sha256:dcb7185e112a453aa72f426754849a97357727ef8f40168fb208c8cf59952042"
}

resource "kubernetes_service_account_v1" "signing_keys" {
  metadata {
    name        = local.signing_key_account
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  # githubgate mounts its own projected token in the interceptor only.
  automount_service_account_token = false
}

resource "kubectl_manifest" "signing_keys_policy" {
  server_side_apply = true
  wait              = false
  ignore_fields     = ["status"]

  yaml_body = yamlencode({
    apiVersion = "githubgate.soliddowant.dev/v1alpha1"
    kind       = "GitHubAccessPolicy"
    metadata = {
      name        = local.signing_key_account
      namespace   = local.namespace
      labels      = local.labels
      annotations = local.annotations
    }
    spec = {
      serviceAccounts = [kubernetes_service_account_v1.signing_keys.metadata[0].name]
      rules = [
        {
          name = "signing-keys"
          userAuthorizationRef = {
            namespace = "ci"
            name      = "soliddowant"
          }
          proxy = {
            enabled = true
            allowOperations = [
              "users/list-ssh-signing-keys-for-authenticated-user",
              "users/create-ssh-signing-key-for-authenticated-user",
              "users/delete-ssh-signing-key-for-authenticated-user",
            ]
          }
        }
      ]
    }
  })
}

# The Jobs' pods reach only DNS and githubgate's proxy, which the injected
# interceptor sends the GitHub requests to. Nothing goes to GitHub directly.
resource "kubectl_manifest" "signing_keys_netpol" {
  server_side_apply = true
  # cilium-operator writes derived state back (see the workspace netpol).
  force_conflicts = true
  wait            = true
  ignore_fields   = ["status"]

  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = local.signing_key_account
      namespace = local.namespace
      # The coder-workspace label: the coder SA may only manage those netpols.
      labels = local.labels
    }
    specs = [
      {
        description = "coder-signing-keys"
        endpointSelector = {
          matchLabels = {
            "app.kubernetes.io/name"     = "coder-signing-keys"
            "app.kubernetes.io/instance" = local.signing_key_account
          }
        }
        egress = [
          {
            toEndpoints = [
              {
                matchLabels = {
                  "io.kubernetes.pod.namespace"             = "networking"
                  "endpoints.netpols.home.arpa/cluster-dns" = "true"
                }
              }
            ]
            toPorts = [
              {
                ports = [
                  {
                    port     = "53"
                    protocol = "UDP"
                  },
                  {
                    port     = "53"
                    protocol = "TCP"
                  }
                ]
                rules = {
                  dns = [
                    {
                      matchPattern = "*"
                    }
                  ]
                }
              }
            ]
          },
          {
            toEndpoints = [
              {
                matchLabels = {
                  "io.kubernetes.pod.namespace" = "ci"
                  "app.kubernetes.io/name"      = "githubgate"
                  "app.kubernetes.io/instance"  = "githubgate"
                }
              }
            ]
            toPorts = [
              {
                ports = [
                  {
                    port     = "9443"
                    protocol = "TCP"
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  })
}

resource "tls_private_key" "git_signing" {
  count = local.signing_key_enabled ? 1 : 0

  algorithm = "ED25519"
}

resource "kubernetes_secret_v1" "git_signing" {
  count = local.signing_key_enabled ? 1 : 0

  metadata {
    name        = local.signing_key_secret
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  data = {
    key = tls_private_key.git_signing[0].private_key_openssh
  }
}

locals {
  # Exactly one of the two Jobs exists: add while the workspace runs, remove
  # while it is stopped.
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

  depends_on = [
    kubectl_manifest.signing_keys_policy,
    kubectl_manifest.signing_keys_netpol,
  ]

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
        service_account_name = kubernetes_service_account_v1.signing_keys.metadata[0].name
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
      # No key (the share is missing): don't leave git pointing at a missing
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
