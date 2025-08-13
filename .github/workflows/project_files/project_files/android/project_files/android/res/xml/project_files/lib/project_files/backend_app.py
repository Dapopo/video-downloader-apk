# backend_app.py (Flask) — supports /info and /download
# Supports TikTok, Instagram, and Twitter/X.
# Install: pip install flask yt-dlp
# Run:     python backend_app.py
# Optional: set env var YTDLP_COOKIES=/path/to/cookies.txt

from flask import Flask, request, send_file, jsonify, render_template_string
from yt_dlp import YoutubeDL
import os, re, tempfile, uuid, pathlib

ALLOWED_DOMAINS = (
    r"(^|\\.)tiktok\\.com$",
    r"(^|\\.)instagram\\.com$",
    r"(^|\\.)twitter\\.com$",
    r"(^|\\.)x\\.com$",
)
import re as _re
_DOMAIN_RE = _re.compile(r"^(?:https?://)?([^/]+)")

COOKIEFILE = os.environ.get("YTDLP_COOKIES")  # optional

app = Flask(__name__)

def _allowed(url: str) -> bool:
    m = _DOMAIN_RE.match(url.strip())
    return bool(m and any(_re.search(p, m.group(1).lower()) for p in ALLOWED_DOMAINS))

@app.get("/info")
def info():
    url = request.args.get("url", "").strip()
    if not url or not _allowed(url):
        return jsonify({"error": "Only TikTok/Instagram/Twitter"}), 400
    ydl_opts = {"quiet": True, "no_warnings": True, "skip_download": True}
    if COOKIEFILE and os.path.exists(COOKIEFILE):
        ydl_opts["cookiefile"] = COOKIEFILE
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=False)
    return jsonify({
        "title": info.get("title"),
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
        "uploader": info.get("uploader"),
    })

HTML = """
<!doctype html>
<html><body>
<form method="post" action="/download">
<input name="url" placeholder="https://..." style="width:360px">
<button>Download</button>
</form>
</body></html>
"""

@app.get("/")
def index():
    return render_template_string(HTML)

@app.post("/download")
def download():
    url = request.form.get("url","").strip()
    if not url: return "URL required", 400
    if not _allowed(url): return "Only TikTok/Instagram/Twitter", 400
    tmpdir = tempfile.mkdtemp(prefix="dl_")
    outfile = os.path.join(tmpdir, f"{uuid.uuid4()}.mp4")
    ydl_opts = {
        "outtmpl": outfile,
        "merge_output_format": "mp4",
        "format": "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b",
        "noplaylist": True,
        "http_headers": {"User-Agent": "Mozilla/5.0"},
        "quiet": True,
        "no_warnings": True,
    }
    if COOKIEFILE and os.path.exists(COOKIEFILE):
        ydl_opts["cookiefile"] = COOKIEFILE
    with YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        final_path = outfile if os.path.exists(outfile) else max(pathlib.Path(tmpdir).glob("*"), key=lambda p: p.stat().st_size)
    title = (info.get("title") or "video").replace("\\n"," ")
    safe = re.sub(r"[^\\w\\-\\. ]","", title) or "video"
    return send_file(str(final_path), as_attachment=True, download_name=f"{safe}.mp4")
