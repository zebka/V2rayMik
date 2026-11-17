# RouterOS Field Fixes Implementation Plan

> **Status:** implemented on `feat/routeros-field-fixes`, release 1.3.26. The checkboxes below are the plan as written, not a progress tracker.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold the six field fixes found on 2026-11-16 into the project: a 1400-byte tunnel MTU, a healthcheck that makes a real request, a pinned GHCR image with a working mirror fallback, a connection-mark rule, a fasttrack that cannot route around the tunnel, and verification commands printed after install.

**Architecture:** Everything lands in the single RouterOS import file `router/v2raymik.rsc`, which stays a generic, full-tunnel installer. The tunnel's architecture does not change: every non-local IPv4 destination still travels through the tunnel. Each fix is a knob with a default, so an operator can override it before the import.

**Tech Stack:** RouterOS 7.23+ scripting (`.rsc`), POSIX `sh` unit tests, GitHub Actions, Markdown docs.

**Spec:** the field notes from the 2026-11-16 device test. They are not in the repository, because they contain node credentials.

## Global Constraints

- **Full tunnel stays.** Do not add a bridge, subnet or interface restriction to the tunnel. No `in-interface=` on any new rule, no `in-interface-list=` anywhere, no DHCP changes, no per-destination exception. The notes' split-tunnel topology (`bridge-remote` only) is explicitly out of scope.
- **No secrets in the repository.** No passwords, UUIDs, Hysteria or obfs keys, or server IPs. The notes omit them on purpose; keep it that way.
- **The `.rsc` file names no interface and no disk.** `MikDisk` is auto-detected; the veth is `$MikVeth`; there is no interface list and no port list.
- **`mik-private` (RFC1918 + link-local) stays the LAN boundary** and stays the admin panel's source guard. The lint asserts `src-address-list=mik-private` and `dst-address-list=!mik-private` are present.
- **Every `/add` needs a guard** — `:if`, `find where` or `:do` within the eight lines above it, or `tests/lint-rsc.sh` fails.
- **Every `$Mik*` read needs a `:global Mik*` declaration** at the top of the file, or the lint fails.
- **RouterOS version floor is 7.23** (healthcheck support). The router in the notes runs 7.25.1.
- **Versions:** `VERSION` goes from `1.3.25` to `1.3.26`. `CHANGELOG.md` uses the heading format `## 1.3.26 - 2026-11-17` with `### Added` / `### Changed` / `### Fixed` sections.
- **The image pin equals `VERSION`.** The `.rsc` names `ghcr.io/zebka/v2raymik:1.3.26`; `tests/unit/rsc-image.t.sh` fails if it drifts.

## Review Focus

- **The mirror fallback must change the image name, not only the registry.** `docker.arvancloud.ir` mirrors Docker Hub; it has no `ghcr.io/zebka/v2raymik`. A fallback that keeps the GHCR name silently never works.
- **`/container repull` must not be trusted blindly.** It is RouterOS 7.x only; wrap it in `:do { } on-error={ }` so an older router logs a warning instead of aborting the import.
- **The fasttrack rule belongs to RouterOS, not to this project.** The script changes it, so the previous values must be saved once and restored on uninstall — or uninstall leaves the router's own rule altered.
- **A network-based healthcheck can fail while the container is fine.** Three consecutive failed probes stop the container (`stop-on-unhealthy=yes`), so the retry count has to tolerate a WAN hiccup.
- **The mark-connection rule must come before the mark-routing rule and must pass through.** Without `passthrough=yes` the chain stops there and nothing is routed into the tunnel table.
- **An operator who pinned `MikRegistryUrl` gets no fallback.** That is the documented behaviour: pinning means "this registry, no fallback".

---

### Task 1: Version and changelog skeleton

**Files:**
- Modify: `VERSION` (one line, `1.3.25` → `1.3.26`)
- Modify: `CHANGELOG.md` (new section at the top, under the `# Changelog` heading)

**Interfaces:**
- Consumes: nothing.
- Produces: `VERSION` = `1.3.26`, and a `## 1.3.26 - 2026-11-17` section that later tasks append bullets to. Task 2 reads `VERSION` to build the image pin.

- [ ] **Step 1: Write the failing test**

The project's own check is the test. Run it and watch it fail:

```bash
cd "$(git rev-parse --show-toplevel)"
sh -c 'v=$(cat VERSION); grep -q "^## $v " CHANGELOG.md'
```

Expected: FAIL — `VERSION` is `1.3.25` and the CHANGELOG's newest section is `## 1.3.25 - 2026-11-15`, so once `VERSION` is bumped the grep must find a matching section. Before the bump this command currently passes, so bump `VERSION` first in step 2 and re-run to see it fail.

- [ ] **Step 2: Bump `VERSION`**

`VERSION` contains exactly `1.3.26` and nothing else.

- [ ] **Step 3: Run the check to verify it fails**

Run the command from step 1.

Expected: FAIL — `grep` finds no `## 1.3.26 ` section in `CHANGELOG.md`.

- [ ] **Step 4: Add the changelog section**

Insert directly under the `# Changelog` heading, above `## 1.3.25 - 2026-11-15`:

```markdown
## 1.3.26 - 2026-11-17

### Changed

- The image is pinned to the version of the repository, and the pull goes to
  GitHub Container Registry first.
```

Later tasks add their own bullets under this section; keep the `### Changed` /
`### Fixed` subsections in the file's existing style.

- [ ] **Step 5: Run the check to verify it passes**

Run the command from step 1, and the project's own target:

```bash
sh -c 'v=$(cat VERSION); case "$v" in [0-9]*.[0-9]*.[0-9]*) ;; *) exit 1 ;; esac; grep -q "^## $v " CHANGELOG.md && echo "version $v ok"'
```

Expected: `version 1.3.26 ok`

- [ ] **Step 6: Commit**

```bash
git add VERSION CHANGELOG.md
git commit -m "release: 1.3.26"
```

---

### Task 2: Tunnel MTU and a healthcheck that makes a request

**Files:**
- Create: `tests/unit/rsc-container.t.sh`
- Modify: `router/v2raymik.rsc` (globals block, defaults block, container-environment block, healthcheck block)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the knob `MikTunMtu` (default `"1400"`), the env `TUN_MTU` on the container, and a healthcheck command that fetches `http://www.gstatic.com/generate_204`. Task 4's test file asserts against the same `.rsc` and uses the same `root` idiom.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/rsc-container.t.sh`:

```sh
#!/bin/sh
# The RouterOS import file: the tun MTU and the container healthcheck.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The MTU the tunnel uses. 1400, not 1500: a Hysteria2 packet carries its own
# header, so a 1500-byte inner packet does not fit a 1500-byte WAN MTU and is
# dropped or fragmented. The router's MSS clamp covers TCP that enters from
# the LAN; it does not cover UDP inside the tunnel.
assert_eq "$(has ':global MikTunMtu "1400"')" "yes" "default tun MTU is 1400"
assert_eq "$(has 'key=TUN_MTU')" "yes" "TUN_MTU is set on the container"
assert_eq "$(has 'value=$MikTunMtu')" "yes" "TUN_MTU takes the knob's value"

# The healthcheck must make a real request. Checking only that tun0 exists
# says the process is alive, not that the tunnel carries anything.
assert_eq "$(has 'generate_204')" "yes" "healthcheck makes a real request"
assert_eq "$(has 'healthcheck-cmd=')" "yes" "healthcheck is set"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd "$(git rev-parse --show-toplevel)"
sh tests/unit/rsc-container.t.sh
```

Expected: FAIL — `default tun MTU is 1400: expected [yes], got [no]`

- [ ] **Step 3: Declare the knob and its default in `router/v2raymik.rsc`**

Add `:global MikTunMtu` to the globals block (after `:global MikRegistryFallback`, line 48), and in the defaults block (after the `MikRegistryFallback` default, line 102) add:

```routeros
# The MTU of the tunnel interface. 1400, not 1500: the transport adds its own
# header, so a 1500-byte inner packet no longer fits the WAN MTU and is
# dropped or fragmented. The router's MSS clamp only covers TCP that enters
# from the LAN; it does not cover UDP inside the tunnel, so the clamp cannot
# fix this. Set MikTunMtu to 1500 only if the path really has the room.
:if ([:typeof $MikTunMtu] = "nothing") do={ :global MikTunMtu "1400" }
```

- [ ] **Step 4: Set the env on the container**

In the container-environment block, after the `NODE_OUTBOUND_FILE` block (line 307), add:

```routeros
# The MTU the tunnel interface gets. The entrypoint reads TUN_MTU and writes
# it into the sing-box tun inbound; unset it means 1500, which is too large
# for a tunnel that adds a header.
:if ([:len [/container envs find where list=$MikContainerName and key="TUN_MTU"]] = 0) do={
  /container envs add list=$MikContainerName key=TUN_MTU value=$MikTunMtu
} else={
  :do { /container envs set [find where list=$MikContainerName and key="TUN_MTU"] value=$MikTunMtu } on-error={}
}
```

The `else` branch rewrites the value, so an install that already has `TUN_MTU=1500` is corrected on the next import.

- [ ] **Step 5: Make the healthcheck make a request**

Replace the healthcheck block (lines 405-408) with:

```routeros
# 7.23+: if the TUN disappears, the container is restarted instead of sitting
# "running" with no tunnel. The check looks for tun0 AND makes one small
# request, because a live process with a dead tunnel still passes the first
# test. wget is in the image (busybox-extras). One request is not a
# throughput test: a healthy container can still be too slow for big
# downloads.
:do {
  /container set [find where name=$MikContainerName] healthcheck-cmd="/bin/sh -c 'ip link show tun0 >/dev/null 2>&1 && wget -q -T 5 -O /dev/null http://www.gstatic.com/generate_204'" \
    healthcheck-interval=00:01:00 healthcheck-start-period=00:00:30 healthcheck-retries=6 stop-on-unhealthy=yes
} on-error={ :log warning "v2raymik: could not set a healthcheck (RouterOS too old?) — the container still runs" }
```

`healthcheck-retries=6` is the new part: with `stop-on-unhealthy=yes`, three failed probes stop the container, and a network probe fails when the WAN hiccups. Six consecutive failures (six minutes) before the container is stopped.

- [ ] **Step 6: Run the test to verify it passes**

```bash
sh tests/unit/rsc-container.t.sh
```

Expected: PASS (exit 0, no output)

- [ ] **Step 7: Run the whole suite and the lint**

```bash
APP_DIR=docker TESTS_DIR=tests sh tests/run.sh
sh tests/lint-rsc.sh router
```

Expected: `9 tests, 9 passed, 0 failed` and no lint output.

- [ ] **Step 8: Commit**

```bash
git add tests/unit/rsc-container.t.sh router/v2raymik.rsc
git commit -m "fix: 1400-byte tunnel MTU and a healthcheck that makes a request"
```

---

### Task 3: Pinned GHCR image with a working mirror fallback

**Files:**
- Create: `tests/unit/rsc-image.t.sh`
- Modify: `router/v2raymik.rsc` (globals block, defaults block, the pull section)
- Modify: `.github/workflows/build.yml` (the `ver` step and the `meta` step)
- Modify: `site/index.html` (the registry selector and the generated setup block)

**Interfaces:**
- Consumes: `VERSION` = `1.3.26` from Task 1.
- Produces: the knobs `MikImage` (default `ghcr.io/zebka/v2raymik:1.3.26`), `MikImageFallback` (default `azebka/v2raymik:1.3.26`), `MikRegistryUrl` (default `https://ghcr.io`), `MikRegistryFallback` (default `https://docker.arvancloud.ir`). The site generator writes `MikRegistryUrl` and `MikImage` together.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/rsc-image.t.sh`:

```sh
#!/bin/sh
# The RouterOS import file: which image is pulled, and from where.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"
version=$(cat "$root/VERSION")

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The default image is pinned to the version of this repository, so a router
# never runs a container the repository does not describe.
assert_eq "$(has ":global MikImage \"ghcr.io/zebka/v2raymik:$version\"")" "yes" \
  "the image is pinned to VERSION"
assert_eq "$(has ":global MikImageFallback \"azebka/v2raymik:$version\"")" "yes" \
  "the fallback names the Docker Hub repository"

# GitHub Container Registry first: it is what CI publishes to, and it has no
# rate limit that an Iranian user runs into.
assert_eq "$(has ':global MikRegistryUrl "https://ghcr.io"')" "yes" \
  "the primary registry is ghcr.io"

# The fallback has to name a different repository, not only a different
# registry: a Docker Hub mirror serves the Docker Hub namespace and has never
# heard of ghcr.io/zebka/v2raymik.
assert_match "$(cat "$rsc")" 'remote-image=\$MikImageFallback' \
  "the fallback pull uses the fallback image"

# A pull that dies half-way leaves the container stopped. Ask for it again.
assert_match "$(cat "$rsc")" '/container/repull' "a failed pull is retried"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
sh tests/unit/rsc-image.t.sh
```

Expected: FAIL — `the image is pinned to VERSION: expected [yes], got [no]`

- [ ] **Step 3: Declare the new knob and change the defaults**

In `router/v2raymik.rsc`, add `:global MikImageFallback` to the globals block (after `:global MikImage`, line 40).

Replace the `MikImage` default (line 92) and add the fallback default next to it:

```routeros
# The image is pinned to the version of this file: a router must never run a
# container the repository does not describe. The tag is bumped with every
# release, and CI checks that it matches VERSION.
:if ([:typeof $MikImage] = "nothing") do={ :global MikImage "ghcr.io/zebka/v2raymik:1.3.26" }
# The fallback names the Docker Hub repository on purpose. A Docker Hub mirror
# serves the Docker Hub namespace and has never heard of ghcr.io/zebka/...,
# so swapping only the registry would silently pull nothing.
:if ([:typeof $MikImageFallback] = "nothing") do={ :global MikImageFallback "azebka/v2raymik:1.3.26" }
```

Replace the `MikRegistryUrl` default (line 101):

```routeros
:if ([:typeof $MikRegistryUrl] = "nothing") do={ :global MikRegistryUrl "https://ghcr.io" }
```

Replace the comment above it (lines 95-99) with:

```routeros
# Registry used for the pull. If you set MikRegistryUrl yourself, that registry
# is used and there is no fallback — and MikImage has to name an image that
# registry actually has (a Docker Hub mirror serves azebka/v2raymik, not
# ghcr.io/zebka/v2raymik). Otherwise GitHub Container Registry is tried first
# and, if the image does not start, MikRegistryFallback is tried with
# MikImageFallback. "" turns the fallback off.
```

- [ ] **Step 4: Make the fallback pull use the fallback image, and really turn the certificate check off**

In the pull section (lines 364-394), replace the fallback's `/container add` (line 377) with:

```routeros
      /container add name=$MikContainerName remote-image=$MikImageFallback interface=$MikVeth \
        root-dir=$rootDir dns=1.1.1.1 \
        envlist=$MikContainerName start-on-boot=yes restart-policy=always \
        check-certificate=no mountlists=MOUNT_MIK_DATA \
        memory-high=100663296 logging=yes
```

`check-certificate=no` is what the log message at line 365 already claims. The Iranian mirrors serve the image with a certificate the router does not trust (measured on 7.25.1).

- [ ] **Step 5: Retry the pull on the same registry**

Replace the "wait for the image pull to finish" block (lines 346-361) with a loop that asks for the pull again when it did not produce a running container:

```routeros
# Start a just-added container as soon as the pull has produced a startable
# one, retrying while the pull is still running. A pull that dies half-way
# (Connection reset by peer, HTTP 502) leaves the container stopped and
# nothing starts it, so the pull is asked for again once before the registry
# is given up on.
:if ($fresh) do={
  :log info "v2raymik: waiting for the image pull to finish, then starting the container"
  :local started false
  :local attempt 0
  :while ($attempt < 2) do={
    :set attempt ($attempt + 1)
    :if ($started = false) do={
      :for i from=1 to=40 do={
        :if ($started = false) do={
          :do {
            /container start [find where name=$MikContainerName]
            :delay 2s
            :if ([:len [/container find where name=$MikContainerName and stopped]] = 0) do={
              :set started true
            }
          } on-error={ :delay 3s }
        }
        :if ($started = false) do={ :delay 2s }
      }
      :if ($started = false) do={
        :log warning ("v2raymik: the image did not start (attempt " . ($attempt - 1) . "); pulling it again")
        :do { /container/repull [find where name=$MikContainerName] } on-error={ :log warning "v2raymik: this RouterOS cannot re-pull an image; trying the fallback registry" }
      }
    }
  }
  :if ($started = true) do={
    :log info "v2raymik: container started"
  } else={
    ...
```

The `...` stands for the existing fallback code (the `if ($registryPinned = false ...)` block, lines 364-400 of the file). Keep that code exactly as it is, except for the `/container add` that step 4 replaces. Do not move the fallback out of the `} else{` branch — it must only run when both attempts on the primary registry failed.

The loop condition is a single comparison on purpose: RouterOS parses a `:while` condition more reliably when it is not a compound expression, and the inner `:if ($started = false)` guard is what stops the second attempt once the container is up.

- [ ] **Step 6: Run the test to verify it passes**

```bash
sh tests/unit/rsc-image.t.sh
```

Expected: PASS (exit 0)

- [ ] **Step 7: Publish the version tag from `main` too, so the pin always resolves**

In `.github/workflows/build.yml`, replace the `ver` step (lines 103-108) with:

```yaml
      - id: ver
        name: Read VERSION
        run: |
          v="$(cat VERSION)"
          plain="$v"
          if [ "${{ github.ref_type }}" != "tag" ]; then v="$v-edge"; fi
          echo "value=$v" >> "$GITHUB_OUTPUT"
          echo "plain=$plain" >> "$GITHUB_OUTPUT"
```

and replace `type=semver,pattern={{version}}` in the `meta` step (line 118) with:

```yaml
            type=raw,value=${{ steps.ver.outputs.plain }}
```

`main` builds publish the bare version as well as `edge`, so the tag the `.rsc` pins exists from the moment the `.rsc` is merged. A tag build publishes the same tag from the same commit. `latest` and `edge` are unchanged.

- [ ] **Step 8: Teach the site generator to change the image name with the registry**

In `site/index.html`, the `official` option currently leaves everything at the default. With ghcr.io as the default, the two mirror options must also name the Docker Hub repository, or the generated block pulls nothing.

In the `gen()` function (lines 159-168), replace the registry block with:

```javascript
    if (vars.registry.value === 'arvancloud') {
      out.push(`:global MikRegistryUrl "https://docker.arvancloud.ir"`);
      out.push(`:global MikImage "azebka/v2raymik:${VERSION}"`);
      if (vars.cert.value === 'no') out.push(`:global MikCheckCertificate "no"`);
    } else if (vars.registry.value === 'iranserver') {
      out.push(`:global MikRegistryUrl "https://docker.iranserver.com"`);
      out.push(`:global MikImage "azebka/v2raymik:${VERSION}"`);
      if (vars.cert.value === 'no') out.push(`:global MikCheckCertificate "no"`);
    }
```

and add a constant next to the `vars` object (line 137):

```javascript
  // The release the import URL points at. The image tag has to be the same
  // version, because the .rsc at that tag pins that version. Bumping the
  // release is a one-line change here and in the URL below.
  const VERSION = '1.3.25';
  const IMPORT_URL = `https://raw.githubusercontent.com/zebka/V2rayMik/v${VERSION}/router/v2raymik.rsc`;
```

Use `IMPORT_URL` in both places that spell the URL out — the "Next:" hint (line 133) and the generated comment (line 172) — so the two cannot drift apart.

Change the `official` option's label (line 108) to `Official (GitHub Container Registry)` and its hint (line 112) to mention that the image is pinned to the release.

- [ ] **Step 9: Run the whole suite and the lint**

```bash
APP_DIR=docker TESTS_DIR=tests sh tests/run.sh
sh tests/lint-rsc.sh router
```

Expected: `10 tests, 10 passed, 0 failed`, no lint output.

- [ ] **Step 10: Commit**

```bash
git add tests/unit/rsc-image.t.sh router/v2raymik.rsc .github/workflows/build.yml site/index.html
git commit -m "feat: pin the image to the release and pull from ghcr.io first"
```

---

### Task 4: A connection mark, and a fasttrack that cannot route around the tunnel

**Files:**
- Create: `tests/unit/rsc-mangle.t.sh`
- Modify: `router/v2raymik.rsc` (globals block, the mangle section, the uninstall section)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the mangle rule `mik: mark tunnel connections` with connection mark `mik-conn`, the globals `MikFasttrackSavedMark` and `MikFasttrackSavedList`, and a `defconf: fasttrack` rule restricted to `connection-mark=no-mark`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/rsc-mangle.t.sh`:

```sh
#!/bin/sh
# The RouterOS import file: the connection mark and the fasttrack rule.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }
line_of() { grep -nF -- "$1" "$rsc" | head -1 | cut -d: -f1; }

# A routing mark is set per packet; a connection mark is set once and sticks.
# The connection mark is what stops fasttrack from taking a connection out of
# the tunnel table.
assert_eq "$(has 'action=mark-connection')" "yes" "the connection is marked"
assert_eq "$(has 'new-connection-mark=mik-conn')" "yes" "the mark is named mik-conn"
assert_eq "$(has 'comment="mik: mark tunnel connections"')" "yes" "the rule is named"

# Without passthrough the chain stops at the mark and the routing rule below
# it never runs.
assert_eq "$(has 'passthrough=yes')" "yes" "the rule passes the packet on"

# The rule must sit above the routing rule, or nothing is routed into the
# tunnel table.
mk=$(line_of 'comment="mik: mark tunnel connections"')
wt=$(line_of 'comment="World -> tunnel"')
[ -n "$mk" ] && [ -n "$wt" ] && [ "$mk" -lt "$wt" ] || \
  fail "the mark-connection rule must come before the mark-routing rule"

# Fasttrack must skip the marked connections, or it routes around the tunnel.
assert_eq "$(has 'connection-mark=no-mark')" "yes" "fasttrack only takes unmarked connections"

# The rule belongs to RouterOS, so the values it had are saved and put back
# on uninstall.
assert_eq "$(has ':global MikFasttrackSavedMark')" "yes" "the old fasttrack mark is saved"
assert_eq "$(has ':global MikFasttrackSavedList')" "yes" "the old fasttrack list is saved"

# Uninstall has to take the rule away again.
assert_eq "$(has 'mik: mark tunnel connections')" "yes" "uninstall knows the rule"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
sh tests/unit/rsc-mangle.t.sh
```

Expected: FAIL — `the connection is marked: expected [yes], got [no]`

- [ ] **Step 3: Declare the two globals**

Add to the globals block in `router/v2raymik.rsc` (after `:global MikDnsSavedServers`, line 49):

```routeros
:global MikFasttrackSaved
:global MikFasttrackSavedMark
:global MikFasttrackSavedList
```

`MikFasttrackSaved` is the flag that says "the two values below were already captured". It is separate from them because a value that was empty comes back from RouterOS as an empty string, and an empty global is indistinguishable from a global that was never set. The flag is never empty, so it is always distinguishable.

- [ ] **Step 4: Add the mark-connection rule**

In the mangle section, before the `World -> tunnel` rule (line 460), add:

```routeros
# The routing mark below is set per packet. The connection mark is set once,
# when the connection is created, and sticks to it. That matters because
# fasttrack takes established connections out of the firewall before the
# mangle rules are even looked at, so a connection that was fasttracked never
# gets the routing mark and leaves through the WAN instead of the tunnel.
# The rule below fasttrack is what stops that; this rule is what gives
# fasttrack something to skip.
:if ([:len [/ip firewall mangle find where comment="mik: mark tunnel connections"]] = 0) do={
  :if ([:len $firstMark] > 0) do={
    /ip firewall mangle add chain=prerouting dst-address-type=!local \
      action=mark-connection new-connection-mark=mik-conn passthrough=yes \
      comment="mik: mark tunnel connections" place-before=$firstMark
  } else={
    /ip firewall mangle add chain=prerouting dst-address-type=!local \
      action=mark-connection new-connection-mark=mik-conn passthrough=yes \
      comment="mik: mark tunnel connections"
  }
}
```

`$firstMark` is the id of the first `mark-routing` rule, computed at line 416. `place-before` puts the new rule above it.

- [ ] **Step 5: Restrict fasttrack and save what it had**

After the mark-connection block, add:

```routeros
# RouterOS ships a fasttrack rule that skips the firewall for established
# connections. Those connections are exactly the ones that would leave
# through the WAN instead of the tunnel, so fasttrack is limited to the
# connections that carry no mark. The rule is RouterOS's own, so what it had
# is saved once and put back when the project is uninstalled.
:local fasttrack [:pick [/ip firewall filter find where comment="defconf: fasttrack"] 0]
:if ([:len $fasttrack] > 0) do={
  :if ([:typeof $MikFasttrackSaved] = "nothing") do={
    :global MikFasttrackSaved true
    :do { :global MikFasttrackSavedMark [/ip firewall filter get $fasttrack connection-mark] } on-error={ :global MikFasttrackSavedMark "" }
    :do { :global MikFasttrackSavedList [/ip firewall filter get $fasttrack src-address-list] } on-error={ :global MikFasttrackSavedList "" }
  }
  /ip firewall filter set $fasttrack connection-mark=no-mark
  :if ([:len $MikFasttrackSavedList] = 0) do={
    :do { /ip firewall filter set $fasttrack src-address-list="" } on-error={}
  }
}
```

The `on-error` around each `get` covers a RouterOS that does not know the property at all; the value is then an empty string, and putting an empty string back on uninstall clears the property — which is what RouterOS's own default looks like.

The last two lines clear a stray empty `src-address-list` — a leftover from a mistyped `src-address-list=!something` that RouterOS keeps as an empty value.

- [ ] **Step 6: Uninstall the new rule and restore fasttrack**

In the uninstall section, add `mik: mark tunnel connections` to the mangle comment list (line 137):

```routeros
  :foreach c in={"mik: never mark the container";"mik: router to LAN";"mik: keep router-direct off the tunnel";"mik: MSS clamp";"mik: MSS clamp back";"mik: MSS clamp (router output)";"World -> mik (LAN)";"World -> mik (router)";"World -> tunnel";"World -> tunnel (router)";"mik: mark tunnel connections"} do={
```

and after that block, restore fasttrack:

```routeros
  # put RouterOS's own fasttrack rule back the way it was
  :local fasttrack [:pick [/ip firewall filter find where comment="defconf: fasttrack"] 0]
  :if ([:len $fasttrack] > 0) do={
    :if ([:typeof $MikFasttrackSaved] != "nothing") do={
      :do { /ip firewall filter set $fasttrack connection-mark=$MikFasttrackSavedMark } on-error={}
      :do { /ip firewall filter set $fasttrack src-address-list=$MikFasttrackSavedList } on-error={}
    }
  }
```

Setting a property to an empty string removes it, so a value that was empty when it was captured clears the property again on uninstall — the state RouterOS's own rule has out of the box.

- [ ] **Step 7: Run the test to verify it passes**

```bash
sh tests/unit/rsc-mangle.t.sh
```

Expected: PASS (exit 0)

- [ ] **Step 8: Run the whole suite and the lint**

```bash
APP_DIR=docker TESTS_DIR=tests sh tests/run.sh
sh tests/lint-rsc.sh router
```

Expected: `11 tests, 11 passed, 0 failed`, no lint output.

- [ ] **Step 9: Commit**

```bash
git add tests/unit/rsc-mangle.t.sh router/v2raymik.rsc
git commit -m "fix: keep fasttrack from routing around the tunnel"
```

---

### Task 5: Verification commands, documentation and changelog

**Files:**
- Create: `tests/unit/rsc-verify.t.sh`
- Modify: `router/v2raymik.rsc` (end of the install branch)
- Modify: `CHANGELOG.md` (bullets in the `1.3.26` section)
- Modify: `docs/install.md` (the "Get the image" section)
- Modify: `docs/architecture.md` (the healthcheck sentence)
- Modify: `docs/troubleshooting.md` (a healthy-but-slow entry)
- Modify: `docs/security.md` (the fasttrack change)

**Interfaces:**
- Consumes: everything the earlier tasks produced.
- Produces: three log lines the operator can copy out of the router log, and documentation that matches the script.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/rsc-verify.t.sh`:

```sh
#!/bin/sh
# The RouterOS import file: the checks it prints after the install.
set -eu
. "$(dirname "$0")/../lib/assert.sh"

root=$(cd "$(dirname "$0")/../.." && pwd)
rsc="$root/router/v2raymik.rsc"

has() { grep -qF -- "$1" "$rsc" && echo yes || echo no; }

# The import ends by telling the operator what to look at. The MTU is the one
# that silently breaks large downloads.
assert_eq "$(has 'grep mtu /etc/sing-box/config.json')" "yes" "the MTU check is printed"
assert_eq "$(has 'connection-mark=mik-conn')" "yes" "the connection-mark check is printed"
assert_eq "$(has 'defconf: fasttrack')" "yes" "the fasttrack check is printed"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
sh tests/unit/rsc-verify.t.sh
```

Expected: FAIL — `the MTU check is printed: expected [yes], got [no]`

- [ ] **Step 3: Print the checks at the end of the install**

In `router/v2raymik.rsc`, replace the last log line (line 609) with:

```routeros
:log info "v2raymik: installed; the panel comes up at http://<router>:$MikAdminLanPort/ once the container is running"
:log info "v2raymik: verify 1 - the tunnel MTU: /container shell $MikContainerName -- grep mtu /etc/sing-box/config.json"
:log info "v2raymik: verify 2 - the marked connections: /ip firewall connection print count-only where connection-mark=mik-conn"
:log info "v2raymik: verify 3 - fasttrack: /ip firewall filter print where comment=\"defconf: fasttrack\""
:log info "v2raymik: verify 4 - old connections keep their old routing: /ip firewall connection remove [find where comment~\"mik\"]"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
sh tests/unit/rsc-verify.t.sh
```

Expected: PASS (exit 0)

- [ ] **Step 5: Write the documentation**

`docs/install.md`, in the "Get the image" section: state that the import pulls `ghcr.io/zebka/v2raymik:<version>` where `<version>` is the version in the `VERSION` file, that the fallback is `azebka/v2raymik:<version>` on `https://docker.arvancloud.ir`, and that a mirror needs both `:global MikRegistryUrl` **and** `:global MikImage` together, because a Docker Hub mirror has never heard of `ghcr.io/zebka/v2raymik`.

`docs/architecture.md`, at the `healthcheck-cmd` sentence (line 147): say that the check looks for `tun0` **and** fetches `http://www.gstatic.com/generate_204`, that it is a liveness check and not a throughput test, and that `TUN_MTU` (1400 by default) is what the tunnel interface uses.

`docs/troubleshooting.md`: add an entry for "the container is healthy but large downloads and speed tests hang" — the MTU is the first thing to look at, `TUN_MTU` must be 1400, and the check is `grep mtu /etc/sing-box/config.json` inside the container.

`docs/security.md`: note that the import restricts RouterOS's own `defconf: fasttrack` rule to connections that carry no mark, because a fasttracked connection would otherwise leave through the WAN, and that uninstall puts the rule back the way it was.

- [ ] **Step 6: Write the changelog bullets**

Under the `## 1.3.26 - 2026-11-17` heading from Task 1, replace the placeholder bullet with:

```markdown
### Changed

- The image is pinned to the version of the repository and the pull goes to
  GitHub Container Registry first. The fallback to an Iranian Docker Hub
  mirror now names the Docker Hub repository as well, because a Docker Hub
  mirror serves the Docker Hub namespace and has never heard of
  `ghcr.io/zebka/v2raymik`.
- A failed pull is asked for again once before the fallback registry is used.
- The import prints the checks to run afterwards.

### Fixed

- **The tunnel's MTU is 1400, not 1500.** The transport adds its own header,
  so a 1500-byte inner packet no longer fits a 1500-byte WAN MTU and is
  dropped or fragmented. The router's MSS clamp only covers TCP that enters
  from the LAN; it does not cover UDP inside the tunnel, so it could not
  cover this. Small pages loaded while large downloads and speed tests hung.
  `TUN_MTU` is now set on the container and `MikTunMtu` overrides it.
- **The healthcheck makes a request.** It looked only for `tun0`, which says
  the process is alive, not that the tunnel carries anything. It now also
  fetches `http://www.gstatic.com/generate_204`. One request is not a
  throughput test — a healthy container can still be too slow for big
  downloads.
- **Fasttrack can no longer route around the tunnel.** RouterOS's
  `defconf: fasttrack` rule skipped the firewall for established connections,
  and those connections never got the routing mark, so they left through the
  WAN. The import now marks connections (`mik-conn`) and limits fasttrack to
  connections that carry no mark. Uninstall puts RouterOS's rule back the way
  it was.
```

- [ ] **Step 7: Run the whole suite, the lint and the version check**

```bash
APP_DIR=docker TESTS_DIR=tests sh tests/run.sh
sh tests/lint-rsc.sh router
sh -c 'v=$(cat VERSION); grep -q "^## $v " CHANGELOG.md && echo "version $v ok"'
```

Expected: `12 tests, 12 passed, 0 failed`, no lint output, `version 1.3.26 ok`.

- [ ] **Step 8: Commit**

```bash
git add tests/unit/rsc-verify.t.sh router/v2raymik.rsc CHANGELOG.md docs/
git commit -m "docs: the checks to run after an install, and what changed"
```

---

### Task 6: Make the version check catch a drifted image pin

**Files:**
- Modify: `Makefile` (the `check-version` target)
- Modify: `tests/lint-rsc.sh` (a new check)

**Interfaces:**
- Consumes: `VERSION` = `1.3.26` and the pin `ghcr.io/zebka/v2raymik:1.3.26` from Task 3.
- Produces: a build-time failure when the `.rsc` names a version the repository does not have. CI already runs `make lint` and the unit tests, so both pick this up.

- [ ] **Step 1: Write the failing test**

Add to `tests/lint-rsc.sh`, after the "Invariants the design stands on" block (after line 68):

```sh
# The image the import pulls is pinned to the version of the repository. A
# pin that names another version would run a container the repository does
# not describe.
pin=$(sed -n 's/.*:global MikImage "ghcr\.io\/zebka\/v2raymik:\([0-9.]*\)".*/\1/p' "$f")
want=$(cat "$root/VERSION")
[ -n "$pin" ] || { err "$f: the image is not pinned to a version"; }
[ "$pin" = "$want" ] || err "$f: the image is pinned to $pin, VERSION says $want"
```

- [ ] **Step 2: Run the lint to verify it passes**

```bash
sh tests/lint-rsc.sh router
```

Expected: no output, exit 0.

- [ ] **Step 3: Break the pin on purpose and watch the lint catch it**

```bash
sed -i 's|ghcr.io/zebka/v2raymik:1.3.26|ghcr.io/zebka/v2raymik:1.3.25|' router/v2raymik.rsc
sh tests/lint-rsc.sh router
sed -i 's|ghcr.io/zebka/v2raymik:1.3.25|ghcr.io/zebka/v2raymik:1.3.26|' router/v2raymik.rsc
```

Expected: the lint prints `router/v2raymik.rsc: the image is pinned to 1.3.25, VERSION says 1.3.26` and exits 1. The second `sed` puts the file back.

- [ ] **Step 4: Extend `make check-version`**

In the `Makefile`, replace the `check-version` target with:

```make
check-version:
	@v=$$(cat VERSION); \
	case "$$v" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "VERSION is not x.y.z: $$v" >&2; exit 1 ;; esac; \
	grep -q "^## $$v " CHANGELOG.md || { echo "CHANGELOG.md has no '## $$v' section" >&2; exit 1; }; \
	grep -q "ghcr.io/zebka/v2raymik:$$v" router/v2raymik.rsc || { echo "router/v2raymik.rsc does not pin the image to $$v" >&2; exit 1; }; \
	echo "version $$v ok"
```

- [ ] **Step 5: Run the lint and the suite once more**

```bash
sh tests/lint-rsc.sh router
APP_DIR=docker TESTS_DIR=tests sh tests/run.sh
```

Expected: no lint output, `12 tests, 12 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add Makefile tests/lint-rsc.sh
git commit -m "test: the image pin has to match VERSION"
```

---

## Self-Review

**Spec coverage.** Every item of the notes' section 6 checklist that belongs to the install script is covered: the `TUN_MTU` env (Task 2), ghcr.io with a pinned tag and retries (Task 3), the healthcheck with `generate_204` (Task 2), the veth and routing table (already in the project, untouched), the mangle rule order (Task 4), the fasttrack fix (Task 4), no DNS or tunnel rules for `bridge` (the project has none, and Task 4 adds none), the DHCP change (out of scope — split tunnel was declined), the single admin address (out of scope — the admin guard stays `mik-private`), and the verification checks (Task 5). The notes' sections 5 and 8 — secret rotation, `tls.insecure`, SSH hardening, a second protocol, a latency ping test — are deployment and panel work, not install-script work, and are not in this plan.

**Step scan.** Every step names one file, one edit, and one command. The two places where a body is left to the implementer are marked with `...` (the existing fallback block in Task 3) and with an exact quoted block.

**Type consistency.** `MikTunMtu`, `MikImageFallback`, `MikFasttrackSavedMark`, `MikFasttrackSavedList` are declared as `:global` in the globals block and read with the same names in the code and in the tests. The connection mark is `mik-conn` in the rule, in the verification log and in the test.

**Review Focus.** Each of the six listed failure modes has a test: the mirror fallback name (`rsc-image.t.sh`), the repull wrap (the `:do {} on-error={}` in Task 3 and the `rsc-image.t.sh` grep for `/container/repull`), the fasttrack restore (`rsc-mangle.t.sh` asserts both saved globals), the healthcheck false negative (`healthcheck-retries=6`, Task 2 step 5), the passthrough (`rsc-mangle.t.sh`), and the pinned registry (`rsc-image.t.sh` plus Task 6's lint check).
