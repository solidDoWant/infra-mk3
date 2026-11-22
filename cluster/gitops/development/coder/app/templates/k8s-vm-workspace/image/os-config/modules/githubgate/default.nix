{ ... }:
# GitHub through githubgate interception, with no GitHub credentials in the VM.
#
# githubgate's webhook injects its interceptor into the VM's virt-launcher pod
# (the template labels it), listening on masquerade's guest gateway, 10.0.2.1,
# port 443. The guest sends github.com, api.github.com and uploads.github.com
# there; the interceptor adds the launcher pod's ServiceAccount token (which
# never enters the guest) and forwards to the githubgate proxy, which decides
# each request by the workspace's GitHubAccessPolicy (template/github.tf) and
# sends it to GitHub with an installation token.
#
# The interceptor's per-pod CA (it signs the three names) arrives in the
# githubgate-trust virtiofs share; ../ca-trust adds it to the system bundle.
# See githubgate's docs/admin/interception-setup.md, "VM workspaces".
let
  gateway = "10.0.2.1";
in
{
  networking.hosts.${gateway} = [
    "api.github.com"
    "uploads.github.com"
    "github.com"
  ];

  # gh refuses to run without a token. This one is a placeholder: the
  # interceptor replaces whatever credential a request carries.
  environment.variables.GH_TOKEN = "githubgate";

  # Interception covers HTTPS only; git over SSH would go straight to GitHub
  # with no credential, so send it through HTTPS too.
  programs.git.config.url."https://github.com/".insteadOf = [
    "git@github.com:"
    "ssh://git@github.com/"
  ];
}
