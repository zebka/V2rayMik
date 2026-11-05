# Side-loading the image

Registries are not always reachable from the target country, and a router pull
failure is hard to diagnose. Side-loading needs nothing but SMB or Winbox upload.

## 1. Build and export

On a machine with Docker:

```sh
make image PLATFORM=linux/arm64
make save PLATFORM=linux/arm64
```

`make save` writes `dist/mikrotik-xray-gateway-26.10.31.tar`. The image must match
the router's architecture (`arm64` for hAP ax³, `arm` for older hEX, `amd64` for
x86/CHR).

RouterOS imports docker-save archives. If the import fails with a format error,
convert it (this is a known RouterOS quirk with some OCI outputs):

```sh
skopeo copy docker-archive:dist/mikrotik-xray-gateway-26.10.31.tar \
              docker-archive:dist/clean.tar
```

## 2. Upload

Through SMB to the disk you configured as `XrayDisk` (e.g. `/usb2`), or drag the
file into Winbox's Files panel.

## 3. Create the container from the file

Instead of `remote-image=`, use `file=`:

```
/container/add name=xray-gw file=usb2/mikrotik-xray-gateway-26.10.31.tar \
  interface=veth-xray root-dir=usb2/xray-gw dns=1.1.1.1 envlist=xray-gw \
  start-on-boot=yes restart-policy=always memory-high=100663296 logging=yes
```

`01-container.rsc` uses `remote-image=$XrayImage`. If you side-load, either run the
`/container/add` line above by hand instead of importing `01-container.rsc`, or
set `XrayImage` to a name that the router already has stored locally.

## 4. Update later

With a file: export a new tar, upload it, then

```
/container/set [find where name="xray-gw"] file=usb2/new.tar
/container/repull [find where name="xray-gw"]
```

With a registry: `/container/update [find where name="xray-gw"]`.

The root-dir (and therefore your `outbound.json`) survives both.
