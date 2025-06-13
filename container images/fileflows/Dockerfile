ARG BASE_IMAGE=ubuntu:rolling

FROM ${BASE_IMAGE} AS comskip

# Install dev dependencies
RUN apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        autoconf \
        automake \
        libtool \
        git \
        build-essential \
        libargtable2-dev \
        libavformat-dev \
        libsdl1.2-compat-dev \
        libswscale-dev

ARG COMSKIP_VERSION=V0.83

# Clone and build comskip
RUN mkdir -p /comskip && \
    git clone --depth 1 --branch "${COMSKIP_VERSION}" https://github.com/erikkaashoek/Comskip.git /comskip && \
    cd /comskip && \
    ./autogen.sh && \
    ./configure && \
    make "-j$(nproc)"

FROM ${BASE_IMAGE}

ARG FILEFLOWS_VERSION=25.5.9.5493

# Based on https://github.com/revenz/FileFlows/blob/99720c34082d1f7306288f7799a5542944584f62/xBuild/DockerfileModded

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/dotnet:/dotnet/tools:$PATH \
    DOTNET_ROOT=/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=true

RUN \
    # Install dependencies
    apt update && \
    apt install -y --no-install-recommends \
        tzdata \
        wget \
        ca-certificates \
        gnupg \
        curl \
        tar \
        xz-utils \
        libssl-dev \
        openssl \
        locales \
        libfontconfig1 \
        libfreetype6 \
        pciutils \
        vainfo \
        git \
        pip \
        unzip \
        && \
    # Install additional tools for use by plugins
    apt install -y --no-install-recommends \
        mkvtoolnix \
        aom-tools \
        svt-av1 \
        x265 \
        x264 \
        nano \
        p7zip-full \
        htop \
        imagemagick \
        vainfo \
        libva-dev \
        mesa-va-drivers \
        intel-media-va-driver-non-free \
        i965-va-driver-shaders \
        libmfx-gen1.2 \
        libvpl2 \
        libigfxcmrt7 \
        rar \
        unrar \
        ffmpeg \
        && \
    # Needed for certain ffmpeg commands to work when called via FileFlows
    ln -s /usr/bin/ffmpeg /usr/local/bin/ffmpeg && \
    # Install dependencies that are available via apt in 24.04, but not anything newer
    # comskip
    apt install -y --no-install-recommends \
        libargtable2-0 \
        libavformat61 \
        libsdl1.2-compat \
        libswscale8 \
        && \
    # Install .NET SDK
    mkdir -m 0775 /dotnet && \
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- -c 8.0 --install-dir /dotnet && \
    # The containers will fail to start if these does not exist, and the root filesystem is read-only.
    mkdir -m 0775 \
        /app \
        /app/common \
        /app/ManuallyAdded \
        /app/Data \
        /app/Data/Data \
        /app/DockerMods \
        /app/Logs \
        /app/Plugins \
        /app/Templates && \
    # Install FileFlows
    curl -fsSL "https://fileflows.com/downloads/Zip/${VERSION}" -o /tmp/fileflows.zip && \
    unzip -q /tmp/fileflows.zip -d /app && \
    rm /tmp/fileflows.zip && \
    rm -rf \
        /app/{FlowRunner,Node,Server}/{runtimes,*.exe} \
        /app/Server/Nodes \
        /app/*.* \
        && \
    # Make the user the owner of the /app directory
    chown -R 1000:1000 /app

# Copy built dependencies
COPY --from=comskip /comskip/comskip /usr/bin/comskip

# The container has a long, nasty startup script that does a lot of unnecessary things that
# require additional permissions. Just run the application itself.
USER 1000:1000
WORKDIR /app/Server
ENTRYPOINT ["dotnet"]
