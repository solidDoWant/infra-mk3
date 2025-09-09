ARG BASE_IMAGE=ubuntu:rolling
FROM ${BASE_IMAGE}

# Install conntrackd and keepalived, as well as nmap for health checks via nping.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends conntrackd keepalived nmap && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add a basic health check script.
RUN <<EOF
cat << EOF_SCRIPT > /usr/bin/ping-via-gateway
#!/bin/bash
set -euo pipefail

GATEWAY_ADDRESS="\$(nmap -sn "\${1}" | grep 'MAC Address' | cut -d' ' -f3)"
if [ -z "\${GATEWAY_ADDRESS}" ]; then
    >&2 echo "Could not determine gateway address"
    exit 1
fi

exec nping --icmp --count 1 --dest-mac "\${GATEWAY_ADDRESS}" "\${2}"
EOF_SCRIPT

chmod +x /usr/bin/ping-via-gateway
EOF

# Most of the operations will require root specifically.
USER 0:0
