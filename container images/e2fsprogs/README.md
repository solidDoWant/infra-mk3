# e2fsprogs

Statically linked ext4 tools from [e2fsprogs](https://github.com/tytso/e2fsprogs), on an empty
base: `mke2fs`/`mkfs.ext4`, `resize2fs`, `e2fsck`/`fsck.ext4`, `tune2fs` and `dumpe2fs`, in
`/sbin`. Static, so they run from any image regardless of its libc. The image is meant to be
mounted as an image volume rather than run.

Used by the docker Tekton Task's dind sidecar (`cluster/gitops/ci/tekton/docker/task/`) to format
and grow its build cache volume: `docker:dind` ships neither tool.

## Building

```sh
make image             # build and push to ghcr.io/soliddowant/e2fsprogs
make image PUSH=false  # build and load locally
make print-image-name
```

The tag is `<e2fsprogs version>-r<IMAGE_REVISION>`. To update e2fsprogs, change
`E2FSPROGS_VERSION` and `E2FSPROGS_COMMIT` together (the build refuses a tag that doesn't point at
the commit), push, and update the digest-pinned reference in the Task.
