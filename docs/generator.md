# RouterOS variable generator

The `site/index.html` page generates a `:global` setup block before the import.
Everything runs in the browser. No server receives user data.

## Files

- `site/index.html` — the generator. Host it as a static page (GitHub Pages,
  a CDN, or any web server). It does not need a backend.
- `router/v2raymik.rsc` — the install script. The generator never changes this
  file; it only writes `:global` variable assignments that the import reads.

## What the generator sets

- **Disk** — one of the names RouterOS exposes (`usb1`, `sata1`, `nvme1`, etc.)
  or a partition name like `usb1-part1`. If left empty, auto-detect runs on the
  router.
- **Container name** — defaults to `v2raymik`; must be unique.
- **Panel port (LAN)** — the TCP port the panel listens on inside the LAN.
  Default `8081`.
- **Pull registry** — `official`, `docker.arvancloud.ir`, or
  `docker.iranserver.com`. For mirrors the certificate check is also offered;
  for the official registry it defaults to on.
- **Certificate check** — for mirrors this must usually be off. For the
  official registry it stays on.

Nothing about traffic routing, DNS, geo-splitting, or the import itself is
generated. The import URL is always fetched from GitHub by the user at install
time.

## Usage

1. Open the page on a device on your LAN (or a PC with the repo).
2. Choose disk, panel port, container name, and registry.
3. Copy the generated block.
4. Run the import:
   ```
   :global MikDisk "sata1"
   :global MikContainerName "proxy"
   :global MikAdminLanPort "8081"
   :global MikRegistryUrl "https://docker.arvancloud.ir"
   /import file-name=v2raymik.rsc
   ```

The same page updates automatically after each release, because the import URL
is written from `docs/install.md` in the generator.
