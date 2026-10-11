# kubernetes_persistent_volume_claim -> _v1 and kubernetes_secret -> _v1. The
# provider can't `moved` across these types, so the old addresses are dropped
# from state without destroying the objects, and the existing objects are
# imported into the new ones. Each import only runs when its object exists, so
# new workspaces create theirs as usual. Remove once every workspace has been
# built on this version.
removed {
  from = kubernetes_persistent_volume_claim.persistent

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret.cloudinit

  lifecycle {
    destroy = false
  }
}

data "kubernetes_resources" "existing_persistent_pvc" {
  api_version    = "v1"
  kind           = "PersistentVolumeClaim"
  namespace      = local.namespace
  field_selector = "metadata.name=${local.name}-persistent"
}

data "kubernetes_resources" "existing_cloudinit_secret" {
  api_version    = "v1"
  kind           = "Secret"
  namespace      = local.namespace
  field_selector = "metadata.name=${local.name}-cloudinit"
}

import {
  for_each = length(data.kubernetes_resources.existing_persistent_pvc.objects) > 0 ? toset(["persistent"]) : toset([])

  to = kubernetes_persistent_volume_claim_v1.persistent
  id = "${local.namespace}/${local.name}-persistent"
}

import {
  for_each = length(data.kubernetes_resources.existing_cloudinit_secret.objects) > 0 ? toset(["cloudinit"]) : toset([])

  to = kubernetes_secret_v1.cloudinit
  id = "${local.namespace}/${local.name}-cloudinit"
}

# The workspace CNP was count-gated on start_count. This one can stay after the
# other migrations are removed.
moved {
  from = kubectl_manifest.netpol[0]
  to   = kubectl_manifest.netpol
}
