# Desktop access for the workspace.
#
# The desktop is not served by the Coder agent and there is no local port to
# tunnel: the guest's Teleport agent runs Teleport's Linux desktop service (see
# ../image/os-config/modules/desktop), and the Teleport proxy brokers the
# connection, enforces its own RBAC (linux_desktop_labels / linux_desktop_logins)
# and records the session. So this is an external link into the Teleport Web UI
# rather than a proxied coder_app - it exists to save the user from hunting for
# their workspace in the Teleport resource list.
#
# Only rendered for desktop workspaces; the base image advertises no desktop and
# the link would 404.
resource "coder_app" "desktop" {
  count = local.enable_desktop ? 1 : 0

  agent_id     = coder_agent.main.id
  slug         = "desktop"
  display_name = "Desktop"
  icon         = "/emojis/1f5a5-fe0f.png"
  external     = true
  order        = 0

  # The resources list, pre-filtered to this workspace, rather than a direct
  # /linux_desktops/<name>/<login> session link.
  #
  # A direct link is not constructible here: for a Linux desktop the Web UI puts
  # the agent's Teleport HOST UUID in that path segment (see
  # UnifiedResources/ResourceActionButton.tsx - it passes desktop.host_id, unlike
  # Windows desktops which use the resource name). That UUID is generated inside
  # the guest on first boot and persisted to /var/lib/teleport, so Terraform has
  # no way to know it. The registered resource's own name is a UUID too; only its
  # `hostname` field is the workspace name.
  #
  # The clusterId segment is the Teleport cluster name, which this cluster sets to
  # its own proxy FQDN (clusterName in security/teleport/cluster/hr.yaml).
  url = "https://teleport.${local.public_domain}/web/cluster/teleport.${local.public_domain}/resources?search=${urlencode(data.coder_workspace.me.name)}"
}
