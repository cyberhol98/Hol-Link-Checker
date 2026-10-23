#!/usr/bin/env bash
# HOL LINK CHECKER
# Crawls a website, checks every link/image/script/stylesheet it finds,
# and opens a visual HTML report in your browser.
set -euo pipefail

clear 2>/dev/null || true

echo "===================================="
echo "        HOL LINK CHECKER"
echo "===================================="
echo

# Check required tools
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required but was not found."
    exit 1
fi

# Ask for website URL
read -r -p "Enter website URL: " URL
if [[ -z "$URL" ]]; then
    echo "Error: no URL entered."
    exit 1
fi
# Add https:// if the user left it off
if [[ ! "$URL" =~ ^https?:// ]]; then
    URL="https://$URL"
fi

read -r -p "Max pages to scan [100]: " MAX_PAGES
MAX_PAGES="${MAX_PAGES:-100}"
if ! [[ "$MAX_PAGES" =~ ^[0-9]+$ ]] || [[ "$MAX_PAGES" -lt 1 ]]; then
    echo "Error: max pages must be a positive number."
    exit 1
fi

echo
echo "Website: $URL"
echo "Maximum pages: $MAX_PAGES"
echo

read -r -p "Start scan? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Scan cancelled."
    exit 0
fi

# Where reports go
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$REPORT_DIR"
HOST="$(echo "$URL" | sed -E 's#^https?://##; s#/.*##; s#[^A-Za-z0-9.-]#_#g')"
REPORT="$REPORT_DIR/linkreport_${HOST}_$(date +%Y%m%d_%H%M%S).html"

echo
echo "Scanning $URL (up to $MAX_PAGES pages)..."
echo

python3 - "$URL" "$MAX_PAGES" "$REPORT" <<'PYTHON'
import sys, json, time, ssl, http.client
from datetime import datetime
from html.parser import HTMLParser
from urllib.parse import urljoin, urldefrag, urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from concurrent.futures import ThreadPoolExecutor, as_completed

START, MAX_PAGES, OUT = urldefrag(sys.argv[1])[0], int(sys.argv[2]), sys.argv[3]
if urlparse(START).scheme not in ("http", "https") or not urlparse(START).netloc:
    sys.exit("Error: Please enter a valid website URL.")
UA = "Mozilla/5.0 (Macintosh) HolLinkChecker/2.0"
TIMEOUT = 12
WORKERS = 16
CTX = ssl.create_default_context()
t0 = time.time()

def fetch(url, method="GET"):
    return urlopen(Request(url, headers={"User-Agent": UA}, method=method),
                   timeout=TIMEOUT, context=CTX)

class LinkParser(HTMLParser):
    """Collects (url, text, kind) for links, images, scripts and stylesheets."""
    def __init__(self):
        super().__init__()
        self.links, self._href, self._text = [], None, []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "a" and a.get("href"):
            self._href, self._text = a["href"], []
        elif tag == "img" and a.get("src"):
            self.links.append((a["src"], a.get("alt") or "(image)", "image"))
        elif tag == "script" and a.get("src"):
            self.links.append((a["src"], "(script)", "script"))
        elif tag == "link" and a.get("href") and "stylesheet" in (a.get("rel") or ""):
            self.links.append((a["href"], "(stylesheet)", "stylesheet"))
    def handle_data(self, data):
        if self._href is not None:
            self._text.append(data)
    def handle_endtag(self, tag):
        if tag == "a" and self._href is not None:
            text = " ".join("".join(self._text).split())[:80] or "(no text)"
            self.links.append((self._href, text, "link"))
            self._href = None

def normalise(base, href):
    href = href.strip()
    if not href or href.startswith(("#", "mailto:", "tel:", "javascript:", "data:")):
        return None
    url = urldefrag(urljoin(base, href))[0]
    return url if urlparse(url).scheme in ("http", "https") else None

# ---------- 1. Crawl pages on the same site ----------
domains = {urlparse(START).netloc.lower()}
queue, seen, pages = [START], {START}, []
links = {}  # url -> {"kind", "sources", "found_on"}

while queue and len(pages) < MAX_PAGES:
    page = queue.pop(0)
    try:
        r = fetch(page)
        if "text/html" not in r.headers.get("Content-Type", ""):
            continue
        final = r.geturl()
        body = r.read(3_000_000).decode(r.headers.get_content_charset() or "utf-8", "replace")
    except Exception as e:
        if not pages and page == START:
            print(f"  Couldn't open {START}: {e}")
            sys.exit(1)
        continue
    if not pages:  # follow e.g. example.com -> www.example.com
        domains.add(urlparse(final).netloc.lower())
    pages.append(page)
    sys.stdout.write(f"\r  Pages scanned: {len(pages)}   Links found: {len(links)}   ")
    sys.stdout.flush()

    parser = LinkParser()
    try:
        parser.feed(body)
    except Exception:
        pass
    for href, text, kind in parser.links:
        url = normalise(final, href)
        if not url:
            continue
        entry = links.setdefault(url, {"kind": kind, "sources": [], "found_on": 0})
        entry["found_on"] += 1
        if len(entry["sources"]) < 25:
            entry["sources"].append({"page": page, "text": text})
        if kind == "link" and urlparse(url).netloc.lower() in domains and url not in seen:
            seen.add(url)
            queue.append(url)
    time.sleep(0.15)  # small delay so we don't hammer the site
print()

# ---------- 2. Check every unique link ----------
def check(url):
    start = time.time()
    status, reason, final = 0, "", url
    try:
        try:
            r = fetch(url, "HEAD")
        except Exception:
            r = fetch(url, "GET")  # some servers reject HEAD
        status, final = r.status, r.geturl()
        reason = http.client.responses.get(status, "")
    except HTTPError as e:
        status, reason = e.code, http.client.responses.get(e.code, str(e.reason))
    except URLError as e:
        reason = str(e.reason)
    except Exception as e:
        reason = str(e) or e.__class__.__name__

    if status == 0 or (status >= 400 and status not in (401, 403, 429)):
        category = "broken"
    elif status in (401, 403, 429):
        category = "check"  # often bot-blocking; may work fine in a browser
    elif final.rstrip("/") != url.rstrip("/"):
        category = "redirect"
    else:
        category = "ok"
    return {"url": url, "status": status, "reason": reason, "final": final,
            "category": category, "ms": int((time.time() - start) * 1000)}

results, total, done = [], len(links), 0
with ThreadPoolExecutor(WORKERS) as ex:
    futures = {ex.submit(check, u): u for u in links}
    for f in as_completed(futures):
        res = f.result()
        info = links[futures[f]]
        res.update(kind=info["kind"], sources=info["sources"], found_on=info["found_on"])
        results.append(res)
        done += 1
        filled = int(30 * done / total) if total else 30
        sys.stdout.write(f"\r  Checking links [{'#' * filled}{'.' * (30 - filled)}] {done}/{total}")
        sys.stdout.flush()
print("\n")

# ---------- 3. Terminal summary ----------
counts = {c: sum(r["category"] == c for r in results) for c in ("broken", "check", "redirect", "ok")}
print(f"  Broken:       {counts['broken']}")
print(f"  Needs a look: {counts['check']}")
print(f"  Redirects:    {counts['redirect']}")
print(f"  Working:      {counts['ok']}")

# Plain-text list of broken links (same format as before), saved where you ran the script
broken = sorted((r for r in results if r["category"] == "broken"), key=lambda r: r["url"])
with open("broken-links.txt", "w", encoding="utf-8") as f:
    f.write("SOURCE PAGE\tBROKEN LINK\tSTATUS\n")
    for r in broken:
        for s in r["sources"]:
            f.write(f"{s['page']}\t{r['url']}\t{r['status'] or 'ERROR'}\n")

if broken:
    print("\n  Broken links found:")
    for r in broken:
        print(f"\n  [{r['status'] or 'ERROR'}] {r['url']}")
        print(f"    Found on: {r['sources'][0]['page']}" +
              (f" (+{r['found_on'] - 1} more)" if r["found_on"] > 1 else ""))
else:
    print("\n  No broken links detected!")
print()
print("  Text list saved to:  broken-links.txt")

# ---------- 4. HTML report ----------
data = {
    "site": START,
    "generated": datetime.now().strftime("%d %b %Y, %H:%M"),
    "duration": round(time.time() - t0, 1),
    "pages": len(pages),
    "results": results,
}

TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Link Report</title>
<style>
:root{--bg:#f5f6f8;--card:#fff;--text:#1d2330;--muted:#6b7280;--line:#e4e6eb;
--bad:#c62828;--bad-bg:#fde8e8;--warn:#a15c07;--warn-bg:#fdf1d8;--redir:#1f5fd6;--redir-bg:#e1ebfd;
--ok:#18794e;--ok-bg:#dff3e7;--accent:#1d2330}
@media(prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#181b22;--text:#e6e8ec;--muted:#9aa1ad;--line:#2a2f3a;
--bad:#f47272;--bad-bg:#3a1717;--warn:#f5c04a;--warn-bg:#3a2c0c;--redir:#6aa5ff;--redir-bg:#15243f;
--ok:#4cd88a;--ok-bg:#0f2e1c;--accent:#e6e8ec}}
*{box-sizing:border-box}
body{margin:0;font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--text)}
.wrap{max-width:1100px;margin:0 auto;padding:32px 16px 64px}
h1{margin:0;font-size:26px;letter-spacing:-.01em}
.sub{margin:4px 0 0;color:var(--muted);font-size:14px;word-break:break-all}
.verdict{margin:20px 0 0;padding:14px 16px;border-radius:12px;font-weight:600}
.verdict.bad{background:var(--bad-bg);color:var(--bad)}
.verdict.good{background:var(--ok-bg);color:var(--ok)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin:20px 0}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;cursor:pointer;
text-align:left;font:inherit;color:inherit;transition:transform .1s}
.card:hover{transform:translateY(-1px)}
.card.active{outline:2px solid var(--accent);outline-offset:-1px}
.card .n{font-size:30px;font-weight:700;line-height:1.1}
.card .l{color:var(--muted);font-size:13px}
.card.broken .n{color:var(--bad)}.card.check .n{color:var(--warn)}
.card.redirect .n{color:var(--redir)}.card.ok .n{color:var(--ok)}
.toolbar{display:flex;gap:10px;margin-bottom:12px}
input,button.btn{font:inherit;color:var(--text);background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px}
input{flex:1;min-width:0}
button.btn{cursor:pointer;white-space:nowrap}
.row{background:var(--card);border:1px solid var(--line);border-radius:10px;margin-bottom:8px;overflow:hidden}
summary{display:flex;align-items:center;gap:12px;padding:12px 14px;cursor:pointer;list-style:none}
summary::-webkit-details-marker{display:none}
.pill{font-size:12px;font-weight:600;padding:3px 9px;border-radius:999px;white-space:nowrap}
.pill.broken{background:var(--bad-bg);color:var(--bad)}.pill.check{background:var(--warn-bg);color:var(--warn)}
.pill.redirect{background:var(--redir-bg);color:var(--redir)}.pill.ok{background:var(--ok-bg);color:var(--ok)}
.url{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-family:ui-monospace,Menlo,monospace;font-size:13px}
.meta{color:var(--muted);font-size:13px;white-space:nowrap}
.detail{padding:4px 14px 14px;font-size:14px;border-top:1px solid var(--line)}
.detail dl{display:grid;grid-template-columns:120px 1fr;gap:6px 12px;margin:10px 0}
.detail dt{color:var(--muted)}.detail dd{margin:0;word-break:break-all}
.detail a{color:var(--redir)}
.detail ul{margin:4px 0 0;padding-left:18px}
.empty{text-align:center;color:var(--muted);padding:48px 0;font-size:16px}
@media(max-width:640px){.meta{display:none}.detail dl{grid-template-columns:1fr}}
</style></head>
<body><div class="wrap">
<h1>HOL Link Report</h1>
<p class="sub" id="sub"></p>
<div class="verdict" id="verdict"></div>
<div class="cards" id="cards"></div>
<div class="toolbar">
  <input id="q" type="search" placeholder="Search URLs, link text or pages…">
  <button class="btn" id="csv">Export CSV</button>
</div>
<div id="list"></div>
</div>
<script id="data" type="application/json">__DATA__</script>
<script>
const D = JSON.parse(document.getElementById("data").textContent);
const R = D.results;
const CATS = [["all","All links"],["broken","Broken"],["check","Needs a look"],["redirect","Redirects"],["ok","Working"]];
const LABEL = {broken:"Broken",check:"Needs a look",redirect:"Redirect",ok:"OK"};
const HELP = {
  broken:"This link doesn't work. Fix or remove it.",
  check:"The server refused the checker (often bot protection). Open it yourself to confirm.",
  redirect:"Works, but sends visitors elsewhere. Consider linking straight to the final address.",
  ok:"Working normally."
};
const ORDER = {broken:0,check:1,redirect:2,ok:3};
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const count = c => c === "all" ? R.length : R.filter(r => r.category === c).length;
let filter = count("broken") ? "broken" : "all";

$("sub").textContent = `${D.site} · ${D.pages} page${D.pages===1?"":"s"} scanned · ${R.length} unique links · ${D.generated} · took ${D.duration}s`;
const nb = count("broken");
$("verdict").className = "verdict " + (nb ? "bad" : "good");
$("verdict").textContent = nb ? `${nb} broken link${nb===1?"":"s"} found` : "No broken links found 🎉";

function renderCards(){
  $("cards").innerHTML = CATS.map(([k,l]) =>
    `<button class="card ${k} ${k===filter?"active":""}" data-k="${k}"><div class="n">${count(k)}</div><div class="l">${l}</div></button>`).join("");
  $("cards").querySelectorAll(".card").forEach(b => b.onclick = () => { filter = b.dataset.k; render(); });
}

function renderList(){
  const q = $("q").value.trim().toLowerCase();
  const rows = R.filter(r => (filter === "all" || r.category === filter) &&
      (!q || (r.url + " " + r.sources.map(s => s.page + " " + s.text).join(" ")).toLowerCase().includes(q)))
    .sort((a,b) => ORDER[a.category] - ORDER[b.category] || b.found_on - a.found_on || a.url.localeCompare(b.url));
  if (!rows.length) { $("list").innerHTML = `<div class="empty">Nothing to show here</div>`; return; }
  $("list").innerHTML = rows.map(r => `
    <details class="row"><summary>
      <span class="pill ${r.category}">${r.status || "ERR"} · ${LABEL[r.category]}</span>
      <span class="url" title="${esc(r.url)}">${esc(r.url)}</span>
      <span class="meta">${r.kind} · on ${r.found_on} page${r.found_on===1?"":"s"}</span>
    </summary>
    <div class="detail">
      <dl>
        <dt>What it means</dt><dd>${HELP[r.category]}</dd>
        <dt>Response</dt><dd>${r.status || "No response"} ${esc(r.reason)} · ${r.ms} ms</dd>
        <dt>Link</dt><dd><a href="${esc(r.url)}" target="_blank" rel="noopener">${esc(r.url)}</a></dd>
        ${r.category === "redirect" ? `<dt>Ends up at</dt><dd><a href="${esc(r.final)}" target="_blank" rel="noopener">${esc(r.final)}</a></dd>` : ""}
        <dt>Found on</dt><dd><ul>${r.sources.map(s =>
          `<li><a href="${esc(s.page)}" target="_blank" rel="noopener">${esc(s.page)}</a> — “${esc(s.text)}”</li>`).join("")}
          ${r.found_on > r.sources.length ? `<li>…and ${r.found_on - r.sources.length} more</li>` : ""}</ul></dd>
      </dl>
    </div></details>`).join("");
}

function render(){ renderCards(); renderList(); }
$("q").addEventListener("input", renderList);

$("csv").onclick = () => {
  const cell = v => `"${String(v).replace(/"/g,'""')}"`;
  const lines = [["Category","Status","Reason","URL","Final URL","Type","Found on (count)","Example page","Link text"]];
  R.forEach(r => lines.push([LABEL[r.category], r.status, r.reason, r.url, r.final, r.kind, r.found_on,
    r.sources[0]?.page || "", r.sources[0]?.text || ""]));
  const blob = new Blob([lines.map(l => l.map(cell).join(",")).join("\n")], {type:"text/csv"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = "link-report.csv"; a.click();
};

render();
</script></body></html>"""

with open(OUT, "w", encoding="utf-8") as f:
    f.write(TEMPLATE.replace("__DATA__", json.dumps(data).replace("</", "<\\/")))
PYTHON

echo "  Visual report:       $REPORT"

# Open the report in the default browser
if command -v open >/dev/null 2>&1; then
    open "$REPORT" || true
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$REPORT" >/dev/null 2>&1 &
fi
