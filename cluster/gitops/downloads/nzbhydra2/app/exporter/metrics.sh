#!/bin/sh
# Serves a single HTTP request on stdin/stdout. Spawned per connection by
# `nc -lk -e`, so stderr is pointed back at the container log.
exec 2>/proc/1/fd/2

read -r _ path _
while read -r line && [ -n "${line%?}" ]; do :; done

printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nConnection: close\r\n\r\n'
[ "$path" = /metrics ] || exit 0

api_key=$(sed -n '/^main:/,/^[^ ]/s/^  apiKey: "\(.*\)"$/\1/p' /config/nzbhydra.yml)

api() {
  curl -sSf --max-time 30 -H 'Content-Type: application/json' -d "$2" "${NZBHYDRA2_URL}$1"
}

# Both endpoints need "Allow stats access via API" enabled in NZBHydra2.
if statuses=$(api /api/stats/indexers "$(jq -n --arg key "$api_key" '{apikey: $key}')") &&
  stats=$(api /api/stats "$(jq -n --arg key "$api_key" '{
    apikey: $key,
    request: {
      after: (now - 6 * 3600 | todate),
      before: (now | todate),
      includeDisabled: true,
      indexerApiAccessStats: true
    }
  }')"); then
  echo "$statuses" | jq -r '
    "# TYPE nzbhydra2_indexer_state gauge",
    (.[] | "nzbhydra2_indexer_state{indexer=\(.indexer | tojson),state=\(.state | tojson)} 1"),
    "# TYPE nzbhydra2_indexer_vip_expiry_timestamp_seconds gauge",
    (.[] | select(.vipExpirationDate != null and .vipExpirationDate != "Lifetime")
      | try "nzbhydra2_indexer_vip_expiry_timestamp_seconds{indexer=\(.indexer | tojson)} \(.vipExpirationDate | strptime("%Y-%m-%d") | mktime)"
        catch empty)'
  # Hydra re-enables a failing indexer within minutes and records a successful
  # access next to each failed one, so neither state nor its error level stays
  # put during an outage. The success ratio over the window does (~0.5 when
  # broken). Indexers with no accesses in the window are omitted.
  echo "$stats" | jq -r '
    "# TYPE nzbhydra2_indexer_api_success_ratio gauge",
    (.indexerApiAccessStats[] | select(.averageAccessesPerDay != null)
      | "nzbhydra2_indexer_api_success_ratio{indexer=\(.indexerName | tojson)} \((.percentSuccessful // 0) / 100)")'
  up=1
else
  up=0
fi
printf '# TYPE nzbhydra2_up gauge\nnzbhydra2_up %s\n' "$up"
