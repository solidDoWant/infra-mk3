#!/bin/sh
# UI changes don't persist — config.yaml is rewritten from the source
# Secret on every pod start (same model as seerr).
#
# - .auth.apikey shares API_KEY with exportarr, so the value isn't
#   duplicated across secrets.
# - .general.ip = "0.0.0.0" works around a socket-binding bug when IPv6
#   is disabled at the kernel level.
set -eu
mkdir -p /config/config

yq '
  .auth.apikey       = strenv(API_KEY) |
  .general.ip        = "0.0.0.0" |
  .general.hostname  = "bazarr." + strenv(PUBLIC_DOMAIN_NAME) |
  .sonarr.apikey     = strenv(SONARR_API_KEY) |
  .radarr.apikey     = strenv(RADARR_API_KEY)
' /etc/bazarr/config-source/config.yaml > /config/config/config.yaml

chmod 0640 /config/config/config.yaml
