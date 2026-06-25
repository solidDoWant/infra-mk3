# Trust the cluster PKI root CA in the workspace's system trust store.
#
# The deployment mounts the root-ca-pub-cert secret's ca.crt at
# /usr/local/share/ca-certificates/cluster-pki-root.crt (see kubernetes.tf). The
# container rootfs is ephemeral, so the system bundle must be rebuilt on every
# start; update-ca-certificates appends the mounted cert to the existing bundle
# rather than replacing it, preserving the public CAs.
resource "coder_script" "trust_cluster_ca" {
  agent_id     = coder_agent.main.id
  display_name = "Trust cluster PKI root CA"
  icon         = "/icon/lock.svg"

  run_on_start       = true
  start_blocks_login = true
  timeout            = 30 # seconds

  script = <<-EOT
    #!/usr/bin/env bash

    set -euo pipefail

    if [ ! -f "${local.cluster_ca_mount_path}" ]; then
      echo "Cluster PKI root CA not mounted at ${local.cluster_ca_mount_path}, skipping."
      exit 0
    fi

    sudo update-ca-certificates
  EOT
}
