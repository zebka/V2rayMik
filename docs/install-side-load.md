# Side-loading the image

Registries are not always reachable from the target country, and a failed pull is
hard to diagnose on a router. Side-loading needs nothing but SMB or a Winbox
upload.

## 1. Build and export

```sh
make save PLATFORM=linux/arm64
```

This writes `dist/mikrotik-xray-gateway-26.10.31.tar`. It must match the router's
architecture: `arm64` for hAP ax³, `arm` for older hEX, `amd64` for x86/CHR.

BuildKit writes the archive with `blobs/sha256/…` paths. Some RouterOS versions
import that directly; the ones tested here want the classic `<layer>.tar` layout
with a repository tag. Normalize it once (this is what was verified to import):

```sh
docker run --rm -v "$PWD/dist:/w" quay.io/skopeo/stable copy \
  docker-archive:/w/mikrotik-xray-gateway-26.10.31.tar \
  docker-archive:/w/royal-xray-gateway.tar:royal-xray-gateway:latest
```

The result has `RepoTags: ["docker.io/library/royal-xray-gateway:latest"]` and
layers named `<hash>.tar` — the shape RouterOS accepted on 7.25.1.

## 2. Upload

Through SMB to the disk you configured as `XrayDisk` (e.g. `/usb2`), or drag the
file into Winbox's Files panel. Put it at the path your install uses:
`usb2/royal-xray-gateway.tar`.

## 3. Point the container at the file

`01-container.rsc` uses `XrayImageFile` when it is set, otherwise it pulls
`XrayImage` from a registry:

```
/import file-name=00-vars.rsc
:global XrayImageFile "usb2/royal-xray-gateway.tar"
/import file-name=01-container.rsc
/container/start [find where name="xray-gw"]
```

## Pulling through an Iranian mirror

`ghcr.io` and `docker.io` are usually unreachable from Iran, so the image cannot
be pulled directly. Publish it to Docker Hub (the CI does this when
`DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets exist) and point RouterOS at a
Docker Hub mirror instead:

```
/container/config/set registry-url=https://docker.arvancloud.ir
/container/set [find where name="xray-gw"] check-certificate=no
/container/repull [find where name="xray-gw"]
```

Verified combinations on RouterOS 7.25.1:

| Mirror | Works | Note |
| --- | --- | --- |
| `docker.arvancloud.ir` | yes | needs `check-certificate=no` (CA not in RouterOS) |
| `focker.ir` | registry reachable | not pull-tested here |
| `docker.iranserver.com` | registry reachable | not pull-tested here |
| `ghcr.repo.mirrory.ir` | no | returns 504 on our 15 MB layer |

The container must be created with `remote-image=`, not `file=`; RouterOS will not
switch an existing file-based container to a registry. Recreate it, keeping the
same `root-dir` (its `/data` is wiped by the removal, so the panel's saved
subscription is lost — everything else survives).

## 4. Update later

Export a new archive, upload it over the same name, then:

```
/container/repull [find where name="xray-gw"]
/container/start [find where name="xray-gw"]
```

`repull` re-extracts the file. The root-dir (and therefore your `outbound.json`)
survives — but anything you `apk add`ed inside the old container does not.

Check that the new image is actually in use: the first log line from the
entrypoint names the egress interface.

```
/log print where topics~"container" and message~"xray-gw:"
```
