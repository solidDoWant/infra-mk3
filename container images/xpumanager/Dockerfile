# Needed until https://github.com/intel/xpumanager/issues/100 is fixed

ARG BASE_IMAGE=ubuntu:rolling

FROM ${BASE_IMAGE}

ARG XPUMANAGER_VERSION=V1.2.41

RUN \
    export DEBIAN_FRONTEND=noninteractive && \
    # Add the Intel repository
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        && \
    curl -fsSL https://repositories.intel.com/gpu/intel-graphics.key | \
        gpg --dearmor -o /usr/share/keyrings/intel-graphics.gpg \
        && \
    . /etc/os-release && \
    echo "deb [signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu ${VERSION_CODENAME} unified" > \
        /etc/apt/sources.list.d/intel-gpu.list \
        && \
    # Determine the URL for the package to download
    apt update && \
    apt install -y --no-install-recommends jq && \
    curl -fsSL "https://api.github.com/repos/intel/xpumanager/releases/tags/${XPUMANAGER_VERSION}" | \
        jq -r '.assets[] | select(.name | test("xpumanager.*[\\._]u24\\.04_amd64\\.deb$")) | .browser_download_url' | \
        xargs -I {} curl -fsSL -o /tmp/xpumanager.deb {} \
        && \
    # Install the package
    apt install -y --no-install-recommends /tmp/xpumanager.deb && \
    # Install dependencies from https://github.com/intel/xpumanager/blob/master/deployment/docker/Dockerfile.ubuntu.22.04
    apt install -y --no-install-recommends \
        pciutils \
        dmidecode \
        libcurl4 \
        iproute2 \
        python3 \
        libnl-genl-3-200 \
        intel-gsc \
        intel-level-zero-gpu \
        level-zero \
        libdrm2 \
        intel-metrics-discovery \
        intel-metrics-library \
        && \
    # Install the exporter
    apt install -y --no-install-recommends python3-pip && \
    python3 -m pip install --break-system-packages --no-cache-dir -r /usr/lib/xpum/rest/requirements.txt && \
    # Clean up
    rm -f /tmp/xpumanager.deb && \
    apt remove -y --purge \
        ca-certificates \
        curl \
        gnupg \
        jq \
        python3-pip && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "/usr/bin/xpumd" ]
