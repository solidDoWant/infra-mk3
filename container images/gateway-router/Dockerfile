ARG BASE_IMAGE=ubuntu:rolling
FROM ${BASE_IMAGE}

# Install conntrackd and keepalived, as well as nmap for health checks via nping.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends conntrackd keepalived nmap && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add a basic health check script.
COPY ping-via-gateway.sh /usr/bin/ping-via-gateway

# Most of the operations will require root specifically.
USER 0:0
