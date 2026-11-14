/* V2rayMik panel. No auth: this page lives on the LAN behind the router's
 * dst-nat and nothing else. */
let GEN = "";
let ENTRIES = [];
let TESTED = {};
let CANCELLED = false;
let BUSY = false;
let CONTAINER_NAME = "v2raymik";

const $ = (id) => document.getElementById(id);

async function api(path, body) {
  const opt = body === undefined ? {} : {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body).toString()
  };
  opt.credentials = "same-origin";
  const res = await fetch("cgi-bin/" + path, opt);
  return res.json();
}

$("subForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const url = $("subUrl").value.trim();
  const links = $("subLinks").value.trim();
  if (!url && !links) { $("subMsg").textContent = "give a URL or paste a link"; return; }
  $("subMsg").textContent = "loading…";
  try {
    const r = await api("sub", url ? { url } : { links });
    if (!r.ok) { $("subMsg").textContent = r.error || "failed"; return; }
    $("subMsg").textContent = r.count + " configs";
    $("subLinks").value = "";
    TESTED = {};
    await load();
  } catch (_) { $("subMsg").textContent = "failed"; }
});

function flag(code) {
  if (!code || code.length !== 2) return "";
  const base = 0x1F1E6;
  return String.fromCodePoint(base + code.charCodeAt(0) - 65, base + code.charCodeAt(1) - 65);
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function renderRows() {
  const box = $("rows");
  if (!ENTRIES.length) {
    box.innerHTML = '<p class="muted">No configs yet.</p>';
    return;
  }
  box.innerHTML = "";
  ENTRIES.forEach((e) => {
    const res = TESTED[e.i] || {};
    let delay = "not tested";
    if (res.code === 204) delay = '<span class="ok">✓ ' + (res.ms || 0) + " ms</span>";
    else if (res.code) delay = '<span class="bad">✗ ' + (res.ms ? res.ms + " ms" : "timeout") + "</span>";
    else if (res.error) delay = '<span class="bad">✗ ' + esc(res.error) + "</span>";
    const engine = res.engine || e.engine;
    const country = res.country ? flag(res.country) + " " + esc(res.country) : "";
    const speed = res.mbps ? res.mbps + " Mbps" : "";

    const row = document.createElement("div");
    row.className = "cfg";
    row.innerHTML =
      '<div class="info"><div class="name">' + (e.i + 1) + ". " + esc(e.label) + "</div>" +
      '<div class="host">' + esc(e.host) + ":" + esc(e.port) +
        (engine ? ' · <span class="pill">' + esc(engine) + "</span>" : "") + "</div></div>" +
      '<div class="result">' + delay +
        (country ? " · " + country : "") + (speed ? " · " + esc(speed) : "") + "</div>";
    const actions = document.createElement("div");
    actions.className = "btns";
    const testBtn = document.createElement("button");
    testBtn.textContent = "Test";
    testBtn.disabled = BUSY;
    testBtn.onclick = () => testOne(e.i);
    const connBtn = document.createElement("button");
    connBtn.textContent = "Connect";
    connBtn.className = "primary";
    connBtn.disabled = BUSY;
    connBtn.onclick = () => connect(e.i);
    actions.append(testBtn, connBtn);
    row.append(actions);
    box.append(row);
  });
}

function ago(ts) {
  if (!ts) return "—";
  const s = Math.max(0, Math.floor(Date.now() / 1000) - ts);
  if (s < 60) return s + " s ago";
  if (s < 3600) return Math.floor(s / 60) + " min ago";
  if (s < 86400) return Math.floor(s / 3600) + " h ago";
  return Math.floor(s / 86400) + " d ago";
}

function renderHealth(r) {
  $("upSince").textContent = r.up_since ? ago(r.up_since) : (r.tun ? "—" : "down");
  $("problemState").textContent = r.problem || "none";
  $("problemState").className = r.problem ? "bad" : "ok";
  $("dnsState").textContent = r.dns_via_tunnel ? "through tunnel" : "not through tunnel";
  $("dnsState").className = r.dns_via_tunnel ? "ok" : "bad";
}

function setBusy(b) {
  BUSY = b;
  $("busy").hidden = !b;
  $("testAll").disabled = b;
  $("cancel").disabled = !b;
  renderRows();
}

async function load() {
  const r = await api("state");
  GEN = r.gen;
  ENTRIES = (r.list && r.list.entries) || [];
  $("activeLabel").textContent = r.label || "environment";
  $("tunState").textContent = r.tun ? "up" : "down";
  $("countState").textContent = r.count;
  CONTAINER_NAME = r.container || "v2raymik";
  $("versionState").textContent = r.version || "dev";
  renderHealth(r);
  $("singboxState").textContent = r.singbox || "—";
  $("xrayState").textContent = r.xray || "—";
  $("engineState").textContent = r.run_engine || r.engine || "—";
  renderRows();
}

async function testOne(i) {
  if (BUSY) return;
  setBusy(true);
  $("testMsg").textContent = "testing #" + (i + 1) + "…";
  try {
    const r = await api("test", { i, gen: GEN });
    TESTED[i] = r;
    $("testMsg").textContent = r.code === 204 ? "ok" : (r.error || "unreachable");
  } catch (err) {
    $("testMsg").textContent = "error";
  } finally {
    setBusy(false);
  }
}

$("testAll").onclick = async () => {
  if (BUSY) return;
  CANCELLED = false;
  setBusy(true);
  for (const e of ENTRIES.slice()) {
    if (CANCELLED) break;
    $("testMsg").textContent = "testing #" + (e.i + 1) + " of " + ENTRIES.length + "…";
    try {
      const r = await api("test", { i: e.i, gen: GEN });
      TESTED[e.i] = r;
      renderRows();
    } catch (_) { break; }
  }
  $("testMsg").textContent = CANCELLED ? "cancelled" : "done";
  setBusy(false);
};

$("cancel").onclick = () => { CANCELLED = true; $("cancel").disabled = true; };

async function connect(i) {
  const e = ENTRIES.find((x) => x.i === i);
  if (!e) return;
  if (!TESTED[i] && !confirm("This config has not been tested. Connect anyway?")) return;
  if (!confirm("Move the router's traffic to \"" + e.label + "\"?\nAbout 2–3 seconds of dropped connections.")) return;
  setBusy(true);
  $("testMsg").textContent = "switching…";
  try {
    const r = await api("connect", { i, gen: GEN });
    $("testMsg").textContent = r.ok ? "connected to " + r.label : (r.error || "failed");
  } catch (_) {
    $("testMsg").textContent = "failed";
  } finally {
    setBusy(false);
    await load();
  }
}

function showRepull(latest) {
  const cmd = "/container/repull [find where name=\"" + CONTAINER_NAME + "\"]";
  $("repullBox").textContent = "# v" + latest + ": run this on the router\n" + cmd;
  $("repullBox").hidden = false;
  $("repullWrap").hidden = false;
}

$("copyRepull").onclick = async () => {
  try {
    await navigator.clipboard.writeText($("repullBox").textContent);
    $("copyRepull").textContent = "Copied";
  } catch (_) {
    $("copyRepull").textContent = "Select and copy";
  }
};

$("checkUpdate").onclick = async () => {
  const msg = $("updateMsg");
  msg.className = "muted update-note";
  msg.textContent = "checking...";
  $("repullBox").hidden = true;
  $("repullWrap").hidden = true;
  $("copyRepull").textContent = "Copy";
  try {
    const r = await api("update");
    if (!r.latest) {
      msg.textContent = "Could not check: " + (r.error || "no answer from GitHub") + ".";
    } else if (r.update) {
      msg.className = "update-note new";
      msg.textContent = "New release " + r.latest + " is out (you run " + r.current + "). Run this on the router:";
      showRepull(r.latest);
    } else {
      msg.textContent = "You run the newest release (" + r.current + ").";
    }
  } catch (_) {
    msg.textContent = "Could not check for an update.";
  }
};

load().catch(() => { $("testMsg").textContent = "panel failed to load"; });
