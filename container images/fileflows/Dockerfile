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
RUN mkdir /comskip && \
    git clone --depth 1 --branch "${COMSKIP_VERSION}" https://github.com/erikkaashoek/Comskip.git /comskip && \
    cd /comskip && \
    ./autogen.sh && \
    ./configure && \
    make "-j$(nproc)"

FROM ${BASE_IMAGE} AS video2x

# Build video2x against the base image dependencies
# Roughly based on https://github.com/k4yt3x/video2x/blob/master/.justfile ubuntu2204 target but
# without using the ffmpeg PPA, because 24.04 and newer have ffmpeg 7 already.

# Install dev dependencies
RUN \
    export DEBIAN_FRONTEND=noninteractive && \
    apt update && \
    apt install -y --no-install-recommends \
        ca-certificates \
        git \
        build-essential \
        cmake \
        ninja-build \
        pkgconf \
        libavcodec-dev \
        libavdevice-dev \
        libavfilter-dev \
        libavformat-dev \
        libavutil-dev \
        libswscale-dev \
        libvulkan-dev \
        glslang-tools \
        libomp-dev \
        libboost-program-options-dev \
        g++

ARG VIDEO2X_VERSION=6.4.0

# Clone and build video2x
RUN \
    git clone --depth 1 --branch "${VIDEO2X_VERSION}" --recurse-submodules -j32 https://github.com/k4yt3x/video2x.git && \
    cd video2x && \
    cmake -G Ninja -B build -S . \
        -DVIDEO2X_USE_EXTERNAL_NCNN=OFF \
        -DVIDEO2X_USE_EXTERNAL_SPDLOG=OFF \
        -DCMAKE_CXX_COMPILER=g++ \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=video2x-linux-ubuntu-amd64/usr \
        && \
    ninja -v -C build/ install && \
    mkdir -p video2x-linux-ubuntu-amd64/DEBIAN && \
    cp packaging/debian/control.ubuntu2404 video2x-linux-ubuntu-amd64/DEBIAN/control && \
    dpkg-deb --build video2x-linux-ubuntu-amd64 video2x.deb

FROM ${BASE_IMAGE}

ARG FILEFLOWS_VERSION=25.5.9.5493

# Based on https://github.com/revenz/FileFlows/blob/99720c34082d1f7306288f7799a5542944584f62/xBuild/DockerfileModded

# Copy built dependencies
COPY --from=comskip /comskip/comskip /usr/bin/comskip
COPY --from=video2x /video2x/video2x.deb /tmp/video2x.deb

ENV PATH=/dotnet:/dotnet/tools:$PATH \
    DOTNET_ROOT=/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=true

RUN \
    export DEBIAN_FRONTEND=noninteractive && \
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
    # video2x
    apt install -y --no-install-recommends /tmp/video2x.deb mesa-vulkan-drivers && \
    rm /tmp/video2x.deb && \
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

# The container has a long, nasty startup script that does a lot of unnecessary things that
# require additional permissions. Just run the application itself.
USER 1000:1000
WORKDIR /app/Server
ENTRYPOINT ["dotnet"]
