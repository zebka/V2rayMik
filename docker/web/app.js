/* V2rayMik panel. No auth: this page lives on the LAN behind the router's
 * dst-nat and nothing else. */
let GEN = "";
let ENTRIES = [];
let TESTED = {};
let CANCELLED = false;
let BUSY = false;

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
  const tb = $("rows");
  if (!ENTRIES.length) {
    tb.innerHTML = '<tr><td colspan="7" class="muted">No configs yet.</td></tr>';
    return;
  }
  tb.innerHTML = "";
  ENTRIES.forEach((e) => {
    const tr = document.createElement("tr");
    const res = TESTED[e.i] || {};
    let delay = "—";
    if (res.code === 204) delay = '<span class="ok">✓</span> ' + (res.ms || 0) + " ms";
    else if (res.code) delay = '<span class="bad">✗</span> ' + (res.ms ? res.ms + " ms" : "timeout");
    else if (res.error) delay = '<span class="bad">✗</span> ' + esc(res.error);
    if (res.engine) delay += ' <span class="pill" title="core that ran this test">' + esc(res.engine) + "</span>";
    const country = res.country ? flag(res.country) + " " + esc(res.country) : "—";
    const speed = res.mbps ? res.mbps : "—";
    tr.innerHTML =
      "<td class='num'>" + (e.i + 1) + "</td>" +
      "<td>" + esc(e.label) + (e.port_ok ? "" : " <span class='pill bad'>port blocked</span>") + "</td>" +
      "<td class='muted'>" + esc(e.host) + ":" + esc(e.port) + "</td>" +
      "<td class='num'>" + delay + "</td>" +
      "<td>" + country + "</td>" +
      "<td class='num'>" + speed + "</td>" +
      "<td class='row'></td>";
    const cell = tr.lastElementChild;
    const testBtn = document.createElement("button");
    testBtn.textContent = "Test";
    testBtn.disabled = !e.port_ok || BUSY;
    testBtn.onclick = () => testOne(e.i);
    const connBtn = document.createElement("button");
    connBtn.textContent = "Connect";
    connBtn.className = "primary";
    connBtn.disabled = !e.port_ok || BUSY;
    connBtn.onclick = () => connect(e.i);
    cell.append(testBtn, connBtn);
    tb.append(tr);
  });
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
  $("versionState").textContent = r.version || "dev";
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
    if (!e.port_ok) continue;
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

load().catch(() => { $("testMsg").textContent = "panel failed to load"; });
