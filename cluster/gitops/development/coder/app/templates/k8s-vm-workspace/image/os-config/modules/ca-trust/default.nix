{
  lib,
  config,
  pkgs,
  ...
}:
# Runtime trust for the cluster PKI root CA.
#
# The CA is mounted via virtiofs (from the root-ca-pub-cert secret) so the image
# stays generic and tracks CA rotation - it is NOT baked in. NixOS assembles the
# system CA bundle at build time, so a mounted cert cannot go into
# security.pki.certificateFiles; instead a boot oneshot concatenates the
# build-time system bundle with the mounted cluster CA into a combined bundle,
# and the whole system is pointed at it via SSL_CERT_FILE (+ friends).
#
# This covers Go (SSL_CERT_FILE) - the Coder agent, Teleport, and user-written Go
# code - plus curl/git and node, in both services and interactive shells.
let
  clusterCA  = "/mnt/root-ca/ca.crt";
  bundlePath = "/run/cluster-ca/ca-bundle.crt";
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

  # Build the combined bundle at boot. Falls back to the system bundle alone if
  # the CA mount is somehow absent, so SSL_CERT_FILE always points at a valid
  # file (a dangling SSL_CERT_FILE would break TLS in every Go program).
  systemd.services.cluster-ca-bundle = {
    description = "Assemble combined CA bundle (system trust + cluster root CA)";
    wantedBy = [ "multi-user.target" ];
    # Order after the virtiofs mount (and before the consumers below).
    unitConfig.RequiresMountsFor = "/mnt/root-ca";
    before = [
      "teleport.service"
      "coder-agent.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "cluster-ca";
      RuntimeDirectoryMode = "0755";
      ExecStart = pkgs.writeShellScript "cluster-ca-bundle" ''
        if [ -f ${clusterCA} ]; then
          cat ${config.security.pki.caBundle} ${clusterCA} > ${bundlePath}
        else
          cp ${config.security.pki.caBundle} ${bundlePath}
        fi
      '';
    };
  };

  # Interactive shells (user-run Go binaries, curl, git, node, ...).
  environment.variables = {
    SSL_CERT_FILE       = bundlePath;
    NIX_SSL_CERT_FILE   = bundlePath;
    GIT_SSL_CAINFO      = bundlePath;
    CURL_CA_BUNDLE      = bundlePath;
    NODE_EXTRA_CA_CERTS = clusterCA;
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
    environment.SSL_CERT_FILE = bundlePath;
  };
}
