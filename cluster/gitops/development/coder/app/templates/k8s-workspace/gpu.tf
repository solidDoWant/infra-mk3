resource "kubectl_manifest" "gpu_claim_template" {
  count             = local.enable_gpu ? 1 : 0
  server_side_apply = true
  wait              = true
  ignore_fields     = ["status"]

  yaml_body = yamlencode({
    apiVersion = "resource.k8s.io/v1beta2"
    kind       = "ResourceClaimTemplate"
    metadata = {
      name      = "${local.name}-gpu"
      namespace = local.namespace
      labels    = local.labels
    }
    spec = {
      spec = {
        devices = {
          requests = [{
            name = "gpu"
            exactly = {
              deviceClassName = "gpu.intel.com"
              allocationMode  = "ExactCount"
              count           = 1
              adminAccess     = local.gpu_admin_access
              selectors = [{
                cel = {
                  expression = local.gpu_cel_selector
                }
              }]
            }
          }]
        }
      }
    }
  })
}
