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
  icon         = "/emojis/1f5a5.png"
  external     = true
  order        = 0

  # Teleport's route is /web/cluster/<clusterId>/linux_desktops/<desktopName>/<login>:
  #   clusterId   - the Teleport cluster name. This cluster names itself after its
  #                 own proxy FQDN (clusterName in security/teleport/cluster/hr.yaml).
  #   desktopName - the desktop registers under the guest's Teleport nodename,
  #                 which is the OS hostname, which cloud-init sets to the
  #                 workspace name (see cloud-init.yaml.tftpl / coder-set-hostname).
  #   login       - the local account, always coder in this image.
  url = "https://teleport.${local.public_domain}/web/cluster/teleport.${local.public_domain}/linux_desktops/${data.coder_workspace.me.name}/coder"
}
