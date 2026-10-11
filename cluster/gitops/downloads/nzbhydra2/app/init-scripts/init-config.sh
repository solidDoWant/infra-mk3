#!/bin/sh
# Sets OIDC auth and the API key in nzbhydra.yml; the rest of the file stays
# UI-managed.
#
# - The API key comes from a Secret so the exporter can read it: Hydra stores
#   it obfuscated in nzbhydra.yml, and accepts a plaintext value.
# - Every user Authentik admits maps to the single `admin` user via the
#   `nzbhydra2_user` claim (nzbhydra2 scope, see the Authentik blueprint).
#   Hydra rejects OIDC logins for usernames not in `users`.
# - All restrict* flags are on, so the UI needs a login. The newznab/torznab
#   API, apikey download links and /api/stats stay apikey-authenticated.
set -eu
config=/config/nzbhydra.yml

# First start: the image entrypoint creates the file from its defaults, and
# the next pod start applies these settings.
if [ ! -f "$config" ]; then
  echo "$config not found, skipping"
  exit 0
fi

yq -i '
  .main.apiKey                   = strenv(API_KEY) |
  .auth.authType                 = "OIDC" |
  .auth.restrictSearch           = true |
  .auth.restrictAdmin            = true |
  .auth.restrictStats            = true |
  .auth.restrictDetailsDl        = true |
  .auth.restrictIndexerSelection = true |
  .auth.oidcIssuerUri            = "https://openid-configuration-proxy.security.svc.cluster.local/application/o/nzbhydra2/" |
  .auth.oidcClientId             = strenv(OIDC_CLIENT_ID) |
  .auth.oidcClientSecret         = strenv(OIDC_CLIENT_SECRET) |
  .auth.oidcRedirectUri          = "https://nzbhydra2." + strenv(PUBLIC_DOMAIN_NAME) + "/login/oauth2/code/nzbhydra2" |
  .auth.oidcScopes               = ["openid", "profile", "nzbhydra2"] |
  .auth.oidcUsernameClaim        = "nzbhydra2_user" |
  .auth.users = [{
    "username": "admin",
    "maySeeAdmin": true,
    "maySeeDetailsDl": true,
    "maySeeStats": true,
    "showIndexerSelection": true
  }]
' "$config"
