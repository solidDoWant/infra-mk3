{
  lib,
  config,
  pkgs,
  ...
}:
# Runtime trust for the cluster PKI root CA and githubgate's per-pod CA.
#
# Both are mounted via virtiofs so the image stays generic and tracks rotation -
# they are NOT baked in:
# - the cluster root CA, from the root-ca-pub-cert secret;
# - the CA of githubgate's interceptor in this VM's launcher pod (../githubgate),
#   which signs github.com, api.github.com and uploads.github.com. It is new
#   for every launcher pod, so a live migration changes it.
# NixOS assembles the system CA bundle at build time, so a mounted cert cannot
# go into security.pki.certificateFiles; instead a oneshot concatenates the
# build-time system bundle with the mounted CAs into a combined bundle, and the
# whole system is pointed at it via SSL_CERT_FILE (+ friends). A timer rebuilds
# it every minute, so new processes pick up the CA of a new launcher pod after
# a live migration (virtiofs passes no inotify events from the host).
#
# This covers Go (SSL_CERT_FILE) - the Coder agent, Teleport, and user-written Go
# code - plus curl/git/nix and node, in both services and interactive shells.
let
  clusterCA = "/mnt/root-ca/ca.crt";
  githubgateCA = "/mnt/githubgate-trust/ca.crt";
  bundlePath = "/run/cluster-ca/ca-bundle.crt";
  # The extra CAs alone, for NODE_EXTRA_CA_CERTS (node adds them to its own
  # roots).
  extraPath = "/run/cluster-ca/extra-ca.crt";

  buildBundle = pkgs.writeShellScript "cluster-ca-bundle" ''
    set -eu
    # virtiofsd may serve a share only to its own uid (107, the virtiofs
    # user, see ../teleport-node), so fall back to reading as that uid.
    read_ca() {
      [ -e "$1" ] || return 0
      cat "$1" 2>/dev/null ||
        ${pkgs.util-linux}/bin/setpriv --reuid=107 --regid=107 --clear-groups cat "$1" 2>/dev/null ||
        true
    }

    dir=/run/cluster-ca
    extra="$(mktemp "$dir/.extra.XXXXXX")"
    bundle="$(mktemp "$dir/.bundle.XXXXXX")"
    trap 'rm -f "$extra" "$bundle"' EXIT
    { read_ca ${clusterCA}; read_ca ${githubgateCA}; } > "$extra"
    cat ${config.security.pki.caBundle} "$extra" > "$bundle"
    chmod 0644 "$extra" "$bundle"

    # Replace atomically, and only on a change, so readers never see a
    # partial file.
    ${pkgs.diffutils}/bin/cmp -s "$extra" ${extraPath} || mv -f "$extra" ${extraPath}
    ${pkgs.diffutils}/bin/cmp -s "$bundle" ${bundlePath} || mv -f "$bundle" ${bundlePath}
  '';
in
{
  # Mount the cluster root CA (virtiofs share from the root-ca-pub-cert secret).
  fileSystems."/mnt/root-ca" = {
    device = "root-ca";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  # githubgate's trust directory from the launcher pod (a containerPath share,
  # see the template's vm.tf). nofail: absent when the pod isn't intercepted.
  fileSystems."/mnt/githubgate-trust" = {
    device = "githubgate-trust";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
    ];
  };

  # Build the combined bundle at boot. Falls back to the system bundle alone if
  # the CA mounts are somehow absent, so SSL_CERT_FILE always points at a valid
  # file (a dangling SSL_CERT_FILE would break TLS in every Go program).
  systemd.services.cluster-ca-bundle = {
    description = "Assemble combined CA bundle (system trust + cluster root CA + githubgate CA)";
    wantedBy = [ "multi-user.target" ];
    # Order after the virtiofs mounts (and before the consumers below). Wants
    # for githubgate's: without interception there is no share.
    unitConfig = {
      RequiresMountsFor = "/mnt/root-ca";
      WantsMountsFor = "/mnt/githubgate-trust";
    };
    before = [
      "teleport.service"
      "coder-agent.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "cluster-ca";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = true;
      ExecStart = buildBundle;
    };
  };

  # Rebuild every minute for a live migration's new githubgate CA.
  systemd.services.cluster-ca-bundle-refresh = {
    description = "Rebuild the combined CA bundle if a mounted CA changed";
    after = [ "cluster-ca-bundle.service" ];
    requires = [ "cluster-ca-bundle.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = buildBundle;
    };
  };
  systemd.timers.cluster-ca-bundle-refresh = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };

  # Interactive shells (user-run Go binaries, curl, git, nix, node, ...).
  environment.variables = {
    SSL_CERT_FILE = bundlePath;
    NIX_SSL_CERT_FILE = bundlePath;
    GIT_SSL_CAINFO = bundlePath;
    CURL_CA_BUNDLE = bundlePath;
    REQUESTS_CA_BUNDLE = bundlePath;
    NODE_EXTRA_CA_CERTS = extraPath;
  };

  # systemd services do not inherit environment.variables, so set it explicitly
  # on the Go services that may reach cluster-cert endpoints, ordered after the
  # bundle exists. (These attrs merge with the services defined elsewhere.)
  systemd.services.teleport = {
    after = [ "cluster-ca-bundle.service" ];
    requires = [ "cluster-ca-bundle.service" ];
    environment.SSL_CERT_FILE = bundlePath;
  };
  systemd.services.coder-agent = {
    after = [ "cluster-ca-bundle.service" ];
    environment = {
      SSL_CERT_FILE = bundlePath;
      NIX_SSL_CERT_FILE = bundlePath;
      GIT_SSL_CAINFO = bundlePath;
      CURL_CA_BUNDLE = bundlePath;
      REQUESTS_CA_BUNDLE = bundlePath;
      GH_TOKEN = "githubgate";
    };
  };
}
