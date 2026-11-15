# Statically linked e2fsprogs tools (mkfs.ext4, resize2fs, e2fsck, ...) and nothing else, for
# other images to use without installing packages, e.g. mounted as an image volume. Static, so
# they run whatever the libc of the image they're used from.

ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} AS build

ARG E2FSPROGS_VERSION
ARG E2FSPROGS_COMMIT

RUN apk add --no-cache build-base git linux-headers

RUN git clone --depth 1 --branch "${E2FSPROGS_VERSION}" https://github.com/tytso/e2fsprogs /src
WORKDIR /src
# Tags can be moved; refuse to build anything other than the reviewed commit.
RUN test "$(git rev-parse HEAD)" = "${E2FSPROGS_COMMIT}"
# The bundled libuuid and libblkid, so nothing links against the build image's. No fuse2fs (it
# needs libfuse) and no translations.
RUN ./configure \
        --prefix=/usr \
        --enable-libuuid \
        --enable-libblkid \
        --disable-fuse2fs \
        --disable-nls \
        LDFLAGS=-static
RUN make -j"$(nproc)" && make install DESTDIR=/out
# Keep only the ext4 tools, stripped (all of them unstripped come to ~40MB), and fail if any
# still wants a dynamic loader.
RUN mkdir -p /image/sbin && cd /out/usr/sbin && \
    cp -a mke2fs mkfs.ext4 resize2fs e2fsck fsck.ext4 tune2fs dumpe2fs /image/sbin/ && \
    strip /image/sbin/* && \
    ! readelf -l /image/sbin/* | grep 'program interpreter'

# No base: the binaries are static and the image is only a source of files.
FROM scratch

COPY --from=build /image/sbin/ /sbin/
