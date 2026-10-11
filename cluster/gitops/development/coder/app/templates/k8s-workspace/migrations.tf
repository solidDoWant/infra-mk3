# kubernetes_persistent_volume_claim -> kubernetes_persistent_volume_claim_v1.
# The provider can't `moved` across these types, so the old address is dropped
# from state without destroying the PVC, and the existing PVC is imported into
# the new one. The import only runs when the PVC exists, so new workspaces create
# theirs as usual. Remove once every workspace has been built on this version.
removed {
  from = kubernetes_persistent_volume_claim.pvcs

  lifecycle {
    destroy = false
  }
}

data "kubernetes_resources" "existing_pvcs" {
  for_each = local.pvcs

  api_version    = "v1"
  kind           = "PersistentVolumeClaim"
  namespace      = local.namespace
  field_selector = "metadata.name=${local.name}-${each.key}"
}

import {
  for_each = { for k, v in local.pvcs : k => v if length(data.kubernetes_resources.existing_pvcs[k].objects) > 0 }

  to = kubernetes_persistent_volume_claim_v1.pvcs[each.key]
  id = "${local.namespace}/${local.name}-${each.key}"
}

# The workspace CNP was count-gated on start_count. This one can stay after the
# other migrations are removed.
moved {
  from = kubectl_manifest.netpol[0]
  to   = kubectl_manifest.netpol
}
