# Project Zomboid dedicated server

Container image for the Project Zomboid dedicated server (Steam app `380870`), built the same way
as the [tug2](https://github.com/soliddowant/tug2) insurgency images: the game is installed at
build time rather than on every container start.

The install is ~7 GB of copyrighted game content, so the image **must only be pushed to the private
registry**. `CONTAINER_REGISTRY` defaults to a local-only name to make that hard to do by accident.

## Building

```sh
make image                        # build locally
make push CONTAINER_REGISTRY=...  # build and push to a private registry
make print-image-name
```

| Variable             | Default  | Notes                                                                          |
| -------------------- | -------- | ------------------------------------------------------------------------------ |
| `PZ_BRANCH`          | `public` | Steam branch. `legacy41` is the build 41 line, `42.19` and friends pin a build. |
| `PZ_BRANCH_PASSWORD` | empty    | Only needed for password-protected betas.                                      |
| `IMAGE_REVISION`     | `1`      | Bump for packaging changes that aren't a game build change.                     |
| `VERSION`            | `$(PZ_BRANCH)-r$(IMAGE_REVISION)` | Image tag.                                            |

Branches are whatever `steamcmd +login anonymous +app_info_print 380870 +quit` lists under
`branches`, so check there before pinning one.

The build downloads the whole app through steamcmd, which takes a while. The depot cache and
in-progress chunks are kept in BuildKit cache mounts, so an interrupted build resumes instead of
starting over.

## Running

```sh
make run-local LOCAL_ADMIN_PASSWORD=somepassword
make stop-local
```

| Variable            | Default            | Notes                                                                  |
| ------------------- | ------------------ | ---------------------------------------------------------------------- |
| `ADMIN_PASSWORD`    | empty              | Required on a server's first start; ignored afterwards.                |
| `ADMIN_USERNAME`    | `admin`            |                                                                        |
| `SERVER_NAME`       | `pzserver`         | Names the INI, the save and the player database under `DATA_DIR`.       |
| `DATA_DIR`          | `/var/lib/zomboid` | Everything persistent. Mount a volume here, owned by `1000:1000`.       |
| `PORT`              | `16261`            | UDP. The client also uses `PORT + 1`.                                   |
| `BIND_IP`           | empty              | One address to bind. Leave empty for all of them - see below.           |
| `MAX_HEAP`          | empty              | e.g. `8g`. Overrides the `-Xmx8g` the game ships with.                  |
| `EXTRA_JAVA_OPTS`   | empty              | Extra JVM args, e.g. `-XX:+UseSerialGC`.                                |
| `EXTRA_SERVER_ARGS` | empty              | Passed through to the server, e.g. `-nosteam`.                          |
| `STEAM_VAC`         | `true`             |                                                                        |
| `SHUTDOWN_TIMEOUT`  | `120`              | Seconds the server gets to save on shutdown before it is killed.        |

Server settings themselves are not environment variables: the server writes
`Server/<SERVER_NAME>.ini` and `Server/<SERVER_NAME>_SandboxVars.lua` into `DATA_DIR` on its first
start, and those are what to edit afterwards.

### Workshop mods

Mods are not baked into the image and need no steamcmd. They are three keys in
`DATA_DIR/Server/<SERVER_NAME>.ini`, and the server downloads them from Steam itself every time it
starts:

```ini
WorkshopItems=514427485;513111049   # what to download - the numeric Workshop IDs
Mods=MyMod;AnotherMod               # what to load - the `id=` from each mod's info.txt
Map=MyMap;Muldraugh, KY             # only for map mods, the folder under the mod's media/maps/
```

`WorkshopItems` on its own only downloads; a mod does nothing until its loading ID is in `Mods`.
That ID is in `DATA_DIR/workshop/content/108600/<workshop id>/mods/<mod>/info.txt` after the first
download, so a new mod is usually: add the ID, start, read `info.txt`, add the name to `Mods`,
restart.

Items install under `DATA_DIR/workshop/`, on the data volume - the entrypoint points the server's
`steamapps/workshop` there - so they are downloaded once and survive restarts rather than being
re-fetched into the container on every start. Steam still re-checks them at each start and updates
any that changed, so a restart can pull a new version of a mod.

A mod list of any size makes the first start much longer, and mods only work with Steam enabled:
`-nosteam` skips the download entirely.

### Updating the game

The server never updates itself. There is no steamcmd in the runtime image at all - the install is
baked in at build time - so the version is whatever the image was built with, and changing it means
rebuilding and redeploying. `make print-build-id` prints the Steam build ID inside the image.

Note that `PZ_BRANCH=public` is a moving target: a rebuild installs whatever `public` is that day,
while the default tag (`public-r1`) stays the same. For a tag that means something, pin a point
release (`make image PZ_BRANCH=42.19`) or set `VERSION` to the game version.

### When the server exits a second after starting

Two settings make the server quit about a second after it logs `SteamUtils initialised
successfully`, with nothing in the log or in `Logs/` to say why:

* **No Steam client library in the home directory.** Steamworks loads it from the home directory in
  `/etc/passwd` for the UID the server runs as - not from the server directory and not from `$HOME`.
  The image links it into place for UID 1000; running as some other UID will need the same.
* **`-ip 0.0.0.0`.** The obvious way to say "all interfaces" is fatal, which is why `BIND_IP` is
  empty by default. The server binds everything without it.

The server also needs to reach Steam. `EXTRA_SERVER_ARGS=-nosteam` starts it with Steam off, which
is the quick way to tell a Steam problem apart from a real startup failure - the log then says
`*** Steam is not enabled` and the server comes up.

### Shutdown

Project Zomboid only writes the world to disk when it is told to. The entrypoint keeps a pipe on
the server's stdin and sends `save` then `quit` when the container is stopped, so **whatever stops
the container has to wait longer than `SHUTDOWN_TIMEOUT`**: `docker stop -t`, or
`terminationGracePeriodSeconds` in Kubernetes. A shorter grace period means a SIGKILL mid-save and a
world rolled back to the last autosave. A graceful stop exits 0; a server that had to be killed
exits 1.

Built and run against build `42.20.4` (`public`) on 2026-09-19: server starts with Steam enabled,
`MAX_HEAP` reaches the JVM, a stop saves and exits cleanly in ~10s, and a restart against the same
data directory loads the world without `ADMIN_PASSWORD`.
