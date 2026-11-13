# Side-loading the image

Registries are not always reachable from the target country, and a failed pull is
hard to diagnose on a router. Side-loading needs nothing but SMB or a Winbox
upload.

## 1. Build and export

```sh
make save PLATFORM=linux/arm64
```

This writes `dist/v2raymik-1.14.4.tar` (the name follows `SING_BOX_VERSION`). It must match the router's
architecture: `arm64` for hAP ax³, `arm` for older hEX, `amd64` for x86/CHR.

BuildKit writes the archive with `blobs/sha256/…` paths. Some RouterOS versions
import that directly; the ones tested here want the classic `<layer>.tar` layout
with a repository tag. Normalize it once (this is what was verified to import):

```sh
docker run --rm -v "$PWD/dist:/w" quay.io/skopeo/stable copy \
  docker-archive:/w/v2raymik-1.14.4.tar \
  docker-archive:/w/v2raymik.tar:v2raymik:latest
```

The result has `RepoTags: ["docker.io/library/v2raymik:latest"]` and
layers named `<hash>.tar` — the shape RouterOS accepted on 7.25.1.

## 2. Upload

Through SMB to the router's disk (`MikDisk` is detected at import — check
`/file print where type=directory` for its name), or drag the
file into Winbox's Files panel. Put it at the path your install uses, e.g.
`flash/v2raymik.tar`.

A formatted, partitioned USB stick mounts as `usb2-part1`, not `usb2` —
the bare `usb2` name is the unpartitioned device and is not a usable
directory. Use whatever name `/file print where type=directory` shows,
and prefer auto-detect over pinning `MikDisk`: on some hardware the same
stick enumerates as usb1 after a reboot.

## 3. Point the container at the file

`v2raymik.rsc` uses `MikImageFile` when it is set, otherwise it pulls
`MikImage` from a registry. The import starts the container itself once
the image is in — no manual `/container/start` needed:

```
:global MikImageFile "usb2-part1/v2raymik.tar"
/import file-name=v2raymik.rsc
```

## Pulling through an Iranian mirror

`ghcr.io` and `docker.io` are usually unreachable from Iran, so the image cannot
be pulled directly. Publish it to Docker Hub (the CI does this when
`DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets exist) and point the import at a
Docker Hub mirror instead:

```
:global MikRegistryUrl "https://docker.arvancloud.ir"
:global MikCheckCertificate "no"
/import file-name=v2raymik.rsc
```

Verified combinations on RouterOS 7.25.1:

| Mirror | Works | Note |
| --- | --- | --- |
| `docker.arvancloud.ir` | yes | needs `check-certificate=no` (CA not in RouterOS) |
| `focker.ir` | registry reachable | official first, then mirror; not pull-tested here |
| `docker.iranserver.com` | yes | needs `check-certificate=no`; pulled 1.1.0 and 1.1.1 on arm64 (8 layers, ~30–45 s) |
| `ghcr.repo.mirrory.ir` | no | returns 504 on our 15 MB layer |

The container must be created with `remote-image=`, not `file=`; RouterOS will not
switch an existing file-based container to a registry. Recreate it, keeping the
same `root-dir` (its `/data` is wiped by the removal, so the panel's saved
subscription is lost — everything else survives).

## 4. Update later

Export a new archive, upload it over the same name, then:

```
/container/repull [find where name="v2raymik"]
/container/start [find where name="v2raymik"]
```

`repull` re-extracts the file. The root-dir (and therefore your `outbound.json`)
survives — but anything you `apk add`ed inside the old container does not.

Check that the new image is actually in use: the first log line from the
entrypoint names the egress interface.

```
/log print where topics~"container" and message~"v2raymik:"
```
