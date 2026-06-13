#!/usr/bin/env python3
import json
import os
import re
import sqlite3
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parent
STATIC_DIR = ROOT / "static"
DATA_DIR = Path(os.environ.get("PAPER_APP_DATA_DIR", ROOT))
DB_PATH = DATA_DIR / "paper_app.sqlite3"
PDF_DIR = DATA_DIR / "storage" / "pdfs"


class MetadataParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title_text = ""
        self.in_title = False
        self.meta = {}

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "title":
            self.in_title = True
            return
        if tag.lower() != "meta":
            return
        data = {k.lower(): v for k, v in attrs if k and v}
        key = (
            data.get("name")
            or data.get("property")
            or data.get("itemprop")
            or data.get("http-equiv")
        )
        content = data.get("content")
        if key and content:
            self.meta.setdefault(key.lower(), []).append(content.strip())

    def handle_endtag(self, tag):
        if tag.lower() == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title_text += data


class ArxivFigureParser(HTMLParser):
    def __init__(self, base_url):
        super().__init__()
        self.base_url = base_url
        self.in_figure = False
        self.in_caption = False
        self.current = None
        self.figures = []

    def handle_starttag(self, tag, attrs):
        data = {k.lower(): v for k, v in attrs if k and v}
        if tag.lower() == "figure":
            classes = data.get("class", "")
            self.in_figure = "ltx_table" not in classes
            if self.in_figure:
                self.current = {
                    "id": data.get("id", ""),
                    "src": "",
                    "alt": "",
                    "caption": "",
                }
            return
        if not self.in_figure or not self.current:
            return
        if tag.lower() == "img" and not self.current["src"]:
            self.current["src"] = absolute_url(self.base_url, data.get("src", ""))
            self.current["alt"] = data.get("alt", "")
        elif tag.lower() == "figcaption":
            self.in_caption = True

    def handle_endtag(self, tag):
        if tag.lower() == "figcaption":
            self.in_caption = False
        elif tag.lower() == "figure" and self.in_figure:
            if self.current and self.current["src"]:
                self.current["caption"] = re.sub(r"\s+", " ", self.current["caption"]).strip()
                self.figures.append(self.current)
            self.in_figure = False
            self.in_caption = False
            self.current = None

    def handle_data(self, data):
        if self.in_figure and self.in_caption and self.current:
            self.current["caption"] += data


def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS papers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                authors TEXT NOT NULL DEFAULT '',
                year TEXT NOT NULL DEFAULT '',
                venue TEXT NOT NULL DEFAULT '',
                doi TEXT NOT NULL DEFAULT '',
                url TEXT NOT NULL DEFAULT '',
                pdf_url TEXT NOT NULL DEFAULT '',
                pdf_path TEXT NOT NULL DEFAULT '',
                summary TEXT NOT NULL DEFAULT '',
                teaser_url TEXT NOT NULL DEFAULT '',
                pipeline_url TEXT NOT NULL DEFAULT '',
                abstract TEXT NOT NULL DEFAULT '',
                notes TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE
            );

            CREATE TABLE IF NOT EXISTS paper_tags (
                paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
                tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                PRIMARY KEY (paper_id, tag_id)
            );

            CREATE TABLE IF NOT EXISTS pdf_annotations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                paper_id INTEGER NOT NULL REFERENCES papers(id) ON DELETE CASCADE,
                page INTEGER NOT NULL,
                kind TEXT NOT NULL DEFAULT 'highlight',
                x REAL NOT NULL DEFAULT 0,
                y REAL NOT NULL DEFAULT 0,
                width REAL NOT NULL DEFAULT 0,
                height REAL NOT NULL DEFAULT 0,
                color TEXT NOT NULL DEFAULT '#ffd966',
                text TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """
        )
        columns = {
            row["name"]
            for row in conn.execute("PRAGMA table_info(papers)").fetchall()
        }
        if "summary" not in columns:
            conn.execute("ALTER TABLE papers ADD COLUMN summary TEXT NOT NULL DEFAULT ''")
        if "teaser_url" not in columns:
            conn.execute("ALTER TABLE papers ADD COLUMN teaser_url TEXT NOT NULL DEFAULT ''")
        if "pipeline_url" not in columns:
            conn.execute("ALTER TABLE papers ADD COLUMN pipeline_url TEXT NOT NULL DEFAULT ''")
        if "pdf_path" not in columns:
            conn.execute("ALTER TABLE papers ADD COLUMN pdf_path TEXT NOT NULL DEFAULT ''")
        conn.execute(
            "UPDATE papers SET abstract = '' WHERE lower(abstract) LIKE 'abstract page for arxiv paper%'"
        )
        conn.execute(
            """
            UPDATE papers SET teaser_url = ''
            WHERE lower(teaser_url) LIKE '%/static/browse/%'
               OR lower(teaser_url) LIKE '%arxiv-logo%'
               OR lower(teaser_url) LIKE '%favicon%'
               OR lower(teaser_url) LIKE '%apple-touch-icon%'
            """
        )
        conn.execute(
            """
            UPDATE papers SET pipeline_url = ''
            WHERE lower(pipeline_url) LIKE '%/static/browse/%'
               OR lower(pipeline_url) LIKE '%arxiv-logo%'
               OR lower(pipeline_url) LIKE '%favicon%'
               OR lower(pipeline_url) LIKE '%apple-touch-icon%'
            """
        )


def now():
    return int(time.time())


def normalize_tags(value):
    if value is None:
        return []
    if isinstance(value, str):
        parts = re.split(r"[,;]", value)
    else:
        parts = value
    tags = []
    seen = set()
    for item in parts:
        tag = re.sub(r"\s+", " ", str(item).strip().lower())
        if tag and tag not in seen:
            seen.add(tag)
            tags.append(tag)
    return tags


def first_meta(meta, *keys):
    for key in keys:
        values = meta.get(key.lower())
        if values:
            return values[0]
    return ""


def all_meta(meta, *keys):
    values = []
    for key in keys:
        values.extend(meta.get(key.lower(), []))
    return values


def clean_title(title):
    title = re.sub(r"\s+", " ", title or "").strip()
    for separator in [" | ", " - "]:
        if separator in title and len(title.split(separator)[0]) > 20:
            title = title.split(separator)[0].strip()
    return title


def clean_abstract(text):
    text = re.sub(r"\s+", " ", text or "").strip()
    if re.match(r"^Abstract page for arXiv paper\b", text, re.IGNORECASE):
        return ""
    return text


def absolute_url(base_url, maybe_url):
    if not maybe_url:
        return ""
    return urllib.parse.urljoin(base_url or "", maybe_url)


def is_placeholder_image(url):
    url = (url or "").lower()
    if not url:
        return True
    placeholders = [
        "/static/browse/",
        "arxiv-logo",
        "favicon",
        "apple-touch-icon",
        "site.webmanifest",
    ]
    return "arxiv.org" in url and any(token in url for token in placeholders)


def paper_has_visual(paper):
    return bool(paper.get("teaser_url") or paper.get("pipeline_url"))


def paper_has_meaningful_visual(paper):
    return bool(
        (paper.get("teaser_url") and not is_placeholder_image(paper.get("teaser_url")))
        or (paper.get("pipeline_url") and not is_placeholder_image(paper.get("pipeline_url")))
    )


def clean_image_url(base_url, maybe_url):
    url = absolute_url(base_url, maybe_url)
    return "" if is_placeholder_image(url) else url


def extract_arxiv_id(value):
    value = value or ""
    match = re.search(r"arxiv\.org/(?:abs|pdf|html)/([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?", value, re.IGNORECASE)
    if match:
        return match.group(1)
    match = re.search(r"(?:arxiv:|arxiv\.)([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?", value, re.IGNORECASE)
    if not match:
        match = re.search(r"\b([0-9]{4}\.[0-9]{4,5})(?:v[0-9]+)?\b", value)
    return match.group(1) if match else ""


def extract_arxiv(url):
    arxiv_id = extract_arxiv_id(url)
    if not arxiv_id:
        return {}
    return {
        "doi": f"arXiv:{arxiv_id}",
        "pdf_url": f"https://arxiv.org/pdf/{arxiv_id}",
        "source": "arXiv",
    }


def pdf_url_for_paper(paper):
    if paper.get("pdf_url"):
        return paper["pdf_url"]
    for key in ["url", "doi"]:
        arxiv_id = extract_arxiv_id(paper.get(key, ""))
        if arxiv_id:
            return f"https://arxiv.org/pdf/{arxiv_id}"
    return paper.get("url", "")


def arxiv_id_for_paper(paper):
    for key in ["url", "pdf_url", "doi"]:
        arxiv_id = extract_arxiv_id(paper.get(key, ""))
        if arxiv_id:
            return arxiv_id
    return ""


def fetch_arxiv_figures(arxiv_id):
    if not arxiv_id:
        return []
    html_url = f"https://arxiv.org/html/{arxiv_id}"
    request = urllib.request.Request(
        html_url,
        headers={
            "User-Agent": "NimbleScholar/0.2 (+local paper manager)",
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            body = response.read(3_000_000)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return []
    parser = ArxivFigureParser(html_url)
    try:
        parser.feed(body.decode("utf-8", errors="ignore"))
    except Exception:
        return []
    return parser.figures


def choose_arxiv_visual(figures):
    if not figures:
        return {}

    def text_for(figure):
        return " ".join([figure.get("id", ""), figure.get("alt", ""), figure.get("caption", "")]).lower()

    teaser = next((figure for figure in figures if "teaser" in text_for(figure)), None)
    if teaser:
        return {"teaser_url": teaser["src"]}

    pipeline_words = [
        "pipeline",
        "overview",
        "framework",
        "architecture",
        "method",
        "approach",
        "workflow",
        "system",
    ]
    pipeline = next(
        (figure for figure in figures if any(word in text_for(figure) for word in pipeline_words)),
        None,
    )
    if pipeline:
        return {"pipeline_url": pipeline["src"]}

    first = next((figure for figure in figures if re.search(r"\bfigure\s*1\b", text_for(figure))), figures[0])
    return {"teaser_url": first["src"]}


def fetch_page_metadata(url):
    if not url:
        return {}
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "NimbleScholar/0.2 (+local paper manager)",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            content_type = response.headers.get("content-type", "")
            body = response.read(1_000_000)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return {}

    if "pdf" in content_type.lower() or url.lower().endswith(".pdf"):
        name = Path(urllib.parse.urlparse(url).path).stem.replace("_", " ").replace("-", " ")
        return {"title": clean_title(name), "pdf_url": url, "url": url, "source": "PDF"}

    parser = MetadataParser()
    try:
        parser.feed(body.decode("utf-8", errors="ignore"))
    except Exception:
        return {}

    meta = parser.meta
    authors = all_meta(meta, "citation_author", "dc.creator", "author")
    year = first_meta(meta, "citation_publication_date", "citation_date", "dc.date", "article:published_time")
    if year:
        year_match = re.search(r"\d{4}", year)
        year = year_match.group(0) if year_match else year

    result = {
        "title": clean_title(first_meta(meta, "citation_title", "dc.title", "og:title") or parser.title_text),
        "authors": ", ".join(dict.fromkeys(authors)),
        "year": year,
        "venue": first_meta(meta, "citation_journal_title", "citation_conference_title", "dc.source"),
        "doi": first_meta(meta, "citation_doi", "dc.identifier", "doi"),
        "url": first_meta(meta, "citation_public_url", "og:url") or url,
        "pdf_url": first_meta(meta, "citation_pdf_url"),
        "teaser_url": clean_image_url(url, first_meta(meta, "og:image", "twitter:image")),
        "abstract": clean_abstract(first_meta(meta, "description", "dc.description", "og:description")),
        "source": urllib.parse.urlparse(url).netloc,
    }
    result.update({k: v for k, v in extract_arxiv(url).items() if v and not result.get(k)})
    return {k: v for k, v in result.items() if v}


def row_to_paper(conn, row):
    tags = [
        item["name"]
        for item in conn.execute(
            """
            SELECT tags.name FROM tags
            JOIN paper_tags ON paper_tags.tag_id = tags.id
            WHERE paper_tags.paper_id = ?
            ORDER BY tags.name
            """,
            (row["id"],),
        ).fetchall()
    ]
    paper = dict(row)
    paper["tags"] = tags
    return paper


def list_papers(query="", tag=""):
    with db() as conn:
        sql = "SELECT DISTINCT papers.* FROM papers"
        params = []
        where = []
        if tag:
            sql += " JOIN paper_tags pt ON pt.paper_id = papers.id JOIN tags t ON t.id = pt.tag_id"
            where.append("t.name = ?")
            params.append(tag.lower())
        if query:
            needle = f"%{query.lower()}%"
            where.append(
                """(
                    lower(title) LIKE ? OR lower(authors) LIKE ? OR lower(summary) LIKE ?
                    OR lower(abstract) LIKE ? OR lower(venue) LIKE ? OR lower(doi) LIKE ?
                    OR lower(url) LIKE ?
                    OR EXISTS (
                        SELECT 1 FROM paper_tags pt2
                        JOIN tags t2 ON t2.id = pt2.tag_id
                        WHERE pt2.paper_id = papers.id AND lower(t2.name) LIKE ?
                    )
                )"""
            )
            params.extend([needle, needle, needle, needle, needle, needle, needle, needle])
        if where:
            sql += " WHERE " + " AND ".join(where)
        sql += " ORDER BY updated_at DESC, id DESC"
        rows = conn.execute(sql, params).fetchall()
        return [row_to_paper(conn, row) for row in rows]


def opportunistic_figure_backfill(papers, limit=1):
    checked = 0
    for paper in papers:
        if checked >= limit:
            break
        if not arxiv_id_for_paper(paper) or paper_has_meaningful_visual(paper):
            continue
        checked += 1
        enrich_paper_figures(paper["id"])


def save_tags(conn, paper_id, tags):
    conn.execute("DELETE FROM paper_tags WHERE paper_id = ?", (paper_id,))
    for tag in normalize_tags(tags):
        conn.execute("INSERT OR IGNORE INTO tags(name) VALUES (?)", (tag,))
        tag_id = conn.execute("SELECT id FROM tags WHERE name = ?", (tag,)).fetchone()["id"]
        conn.execute(
            "INSERT OR IGNORE INTO paper_tags(paper_id, tag_id) VALUES (?, ?)",
            (paper_id, tag_id),
        )


def create_paper(data):
    timestamp = now()
    fields = {
        "title": clean_title(data.get("title")) or "Untitled paper",
        "authors": data.get("authors", ""),
        "year": data.get("year", ""),
        "venue": data.get("venue", ""),
        "doi": data.get("doi", ""),
        "url": data.get("url", ""),
        "pdf_url": data.get("pdf_url", ""),
        "summary": data.get("summary", ""),
        "teaser_url": clean_image_url(data.get("url", ""), data.get("teaser_url", "")),
        "pipeline_url": clean_image_url(data.get("url", ""), data.get("pipeline_url", "")),
        "abstract": clean_abstract(data.get("abstract", "")),
        "notes": data.get("notes", ""),
        "source": data.get("source", ""),
    }
    with db() as conn:
        existing = None
        if fields["doi"]:
            existing = conn.execute("SELECT * FROM papers WHERE lower(doi) = lower(?)", (fields["doi"],)).fetchone()
        if not existing and fields["url"]:
            existing = conn.execute("SELECT * FROM papers WHERE url = ?", (fields["url"],)).fetchone()
        if existing:
            merged = {**dict(existing), **{k: v for k, v in fields.items() if v}}
            merged["updated_at"] = timestamp
            conn.execute(
                """
                UPDATE papers SET title=:title, authors=:authors, year=:year, venue=:venue,
                    doi=:doi, url=:url, pdf_url=:pdf_url, summary=:summary,
                    teaser_url=:teaser_url, pipeline_url=:pipeline_url, abstract=:abstract,
                    notes=:notes, source=:source, updated_at=:updated_at
                WHERE id=:id
                """,
                merged,
            )
            paper_id = existing["id"]
        else:
            cur = conn.execute(
                """
                INSERT INTO papers(title, authors, year, venue, doi, url, pdf_url, summary, teaser_url, pipeline_url, abstract, notes, source, created_at, updated_at)
                VALUES (:title, :authors, :year, :venue, :doi, :url, :pdf_url, :summary, :teaser_url, :pipeline_url, :abstract, :notes, :source, :created_at, :updated_at)
                """,
                {**fields, "created_at": timestamp, "updated_at": timestamp},
            )
            paper_id = cur.lastrowid
        save_tags(conn, paper_id, data.get("tags", []))
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        return row_to_paper(conn, row)


def update_paper(paper_id, data):
    timestamp = now()
    with db() as conn:
        existing = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        if not existing:
            return None
        fields = dict(existing)
        for key in ["title", "authors", "year", "venue", "doi", "url", "pdf_url", "summary", "teaser_url", "pipeline_url", "abstract", "notes", "source"]:
            if key in data:
                fields[key] = clean_title(data[key]) if key == "title" else data[key]
        fields["updated_at"] = timestamp
        conn.execute(
            """
            UPDATE papers SET title=:title, authors=:authors, year=:year, venue=:venue,
                doi=:doi, url=:url, pdf_url=:pdf_url, summary=:summary,
                teaser_url=:teaser_url, pipeline_url=:pipeline_url, abstract=:abstract,
                notes=:notes, source=:source, updated_at=:updated_at
            WHERE id=:id
            """,
            fields,
        )
        if "tags" in data:
            save_tags(conn, paper_id, data["tags"])
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        return row_to_paper(conn, row)


def enrich_paper_figures(paper_id, overwrite=False):
    with db() as conn:
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        if not row:
            return None
        paper = row_to_paper(conn, row)
        if not overwrite and paper_has_meaningful_visual(paper):
            return paper
        arxiv_id = arxiv_id_for_paper(paper)
        chosen = choose_arxiv_visual(fetch_arxiv_figures(arxiv_id))
        if not chosen:
            return paper
        updates = {
            "id": paper_id,
            "teaser_url": "" if is_placeholder_image(paper.get("teaser_url")) else paper.get("teaser_url", ""),
            "pipeline_url": "" if is_placeholder_image(paper.get("pipeline_url")) else paper.get("pipeline_url", ""),
            "updated_at": now(),
        }
        if overwrite or not updates["teaser_url"]:
            updates["teaser_url"] = chosen.get("teaser_url", updates["teaser_url"])
        if overwrite or not updates["pipeline_url"]:
            updates["pipeline_url"] = chosen.get("pipeline_url", updates["pipeline_url"])
        conn.execute(
            """
            UPDATE papers SET teaser_url = :teaser_url, pipeline_url = :pipeline_url,
                updated_at = :updated_at
            WHERE id = :id
            """,
            updates,
        )
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        return row_to_paper(conn, row)


def ensure_paper_figure(paper):
    if paper and not paper_has_meaningful_visual(paper):
        return enrich_paper_figures(paper["id"]) or paper
    return paper


def enrich_all_arxiv_figures(overwrite=False):
    updated = 0
    skipped = 0
    with db() as conn:
        rows = conn.execute("SELECT * FROM papers ORDER BY id").fetchall()
        paper_ids = [row["id"] for row in rows if arxiv_id_for_paper(dict(row))]
    for paper_id in paper_ids:
        before = None
        after = None
        with db() as conn:
            row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
            if row:
                before = dict(row)
        if before:
            after = enrich_paper_figures(paper_id, overwrite=overwrite)
        if after and (
            after.get("teaser_url") != before.get("teaser_url")
            or after.get("pipeline_url") != before.get("pipeline_url")
        ):
            updated += 1
        else:
            skipped += 1
    return {"checked": len(paper_ids), "updated": updated, "skipped": skipped}


def open_external_url(url):
    parsed = urllib.parse.urlparse(url or "")
    if parsed.scheme not in ("http", "https"):
        return False
    if sys.platform == "darwin":
        subprocess.Popen(["/usr/bin/open", url])
    else:
        import webbrowser

        webbrowser.open(url)
    return True


def safe_pdf_name(paper):
    arxiv_id = arxiv_id_for_paper(paper)
    source = arxiv_id or paper.get("title") or f"paper-{paper.get('id')}"
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", source).strip("-._").lower()
    return f"{paper.get('id')}-{slug[:80] or 'paper'}.pdf"


def local_pdf_path_for_paper(paper):
    path = paper.get("pdf_path", "")
    if path and Path(path).exists():
        return Path(path)
    return None


def update_pdf_path(paper_id, path):
    with db() as conn:
        conn.execute(
            "UPDATE papers SET pdf_path = ?, updated_at = ? WHERE id = ?",
            (str(path), now(), paper_id),
        )


def download_pdf_for_paper(paper_id, overwrite=False):
    with db() as conn:
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        if not row:
            return {"ok": False, "error": "Paper not found"}
        paper = row_to_paper(conn, row)

    existing = local_pdf_path_for_paper(paper)
    if existing and not overwrite:
        return {"ok": True, "downloaded": False, "path": str(existing), "paper": paper}

    pdf_url = pdf_url_for_paper(paper)
    parsed = urllib.parse.urlparse(pdf_url or "")
    if parsed.scheme not in ("http", "https"):
        return {"ok": False, "error": "No PDF URL available"}

    PDF_DIR.mkdir(parents=True, exist_ok=True)
    destination = PDF_DIR / safe_pdf_name(paper)
    temp_path = destination.with_suffix(".download")
    request = urllib.request.Request(
        pdf_url,
        headers={
            "User-Agent": "NimbleScholar/0.2 (+local paper manager)",
            "Accept": "application/pdf,*/*;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response, temp_path.open("wb") as output:
            first = response.read(5)
            if first != b"%PDF-":
                temp_path.unlink(missing_ok=True)
                return {"ok": False, "error": "URL did not return a PDF"}
            output.write(first)
            shutil.copyfileobj(response, output, length=1024 * 256)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
        temp_path.unlink(missing_ok=True)
        return {"ok": False, "error": str(exc)}

    temp_path.replace(destination)
    update_pdf_path(paper_id, destination)
    with db() as conn:
        row = conn.execute("SELECT * FROM papers WHERE id = ?", (paper_id,)).fetchone()
        paper = row_to_paper(conn, row)
    return {"ok": True, "downloaded": True, "path": str(destination), "paper": paper}


def download_all_pdfs(overwrite=False):
    papers = list_papers()
    result = {"checked": len(papers), "downloaded": 0, "skipped": 0, "failed": 0, "errors": []}
    for paper in papers:
        item = download_pdf_for_paper(paper["id"], overwrite=overwrite)
        if item.get("ok") and item.get("downloaded"):
            result["downloaded"] += 1
        elif item.get("ok"):
            result["skipped"] += 1
        else:
            result["failed"] += 1
            result["errors"].append({"id": paper["id"], "title": paper.get("title", ""), "error": item.get("error", "")})
    return result


def pdf_file_for_paper(paper_id):
    result = download_pdf_for_paper(paper_id)
    if not result.get("ok"):
        return None, result.get("error", "PDF unavailable")
    path = Path(result["path"])
    if not path.exists():
        return None, "PDF file missing"
    return path, ""


def open_local_pdf(paper_id, reader_app=""):
    result = download_pdf_for_paper(paper_id)
    if not result.get("ok"):
        return result
    path = result["path"]
    try:
        if sys.platform == "darwin":
            command = ["/usr/bin/open"]
            if reader_app.strip():
                command.extend(["-a", reader_app.strip()])
            command.append(path)
            subprocess.Popen(command)
        else:
            import webbrowser

            webbrowser.open(Path(path).as_uri())
    except OSError as exc:
        return {"ok": False, "error": str(exc)}
    return {**result, "opened": True}


def clamp_float(value, minimum=0.0, maximum=1.0):
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = minimum
    return min(max(number, minimum), maximum)


def row_to_annotation(row):
    annotation = dict(row)
    for key in ["x", "y", "width", "height"]:
        annotation[key] = float(annotation[key])
    return annotation


def list_pdf_annotations(paper_id):
    with db() as conn:
        rows = conn.execute(
            """
            SELECT * FROM pdf_annotations
            WHERE paper_id = ?
            ORDER BY page, created_at, id
            """,
            (paper_id,),
        ).fetchall()
        return [row_to_annotation(row) for row in rows]


def create_pdf_annotation(paper_id, data):
    timestamp = now()
    kind = data.get("kind", "highlight")
    if kind not in {"highlight", "note"}:
        kind = "highlight"
    fields = {
        "paper_id": paper_id,
        "page": max(1, int(data.get("page") or 1)),
        "kind": kind,
        "x": clamp_float(data.get("x")),
        "y": clamp_float(data.get("y")),
        "width": clamp_float(data.get("width")),
        "height": clamp_float(data.get("height")),
        "color": data.get("color") or ("#ffd966" if kind == "highlight" else "#7cc4ff"),
        "text": str(data.get("text", "")).strip(),
        "created_at": timestamp,
        "updated_at": timestamp,
    }
    with db() as conn:
        paper = conn.execute("SELECT id FROM papers WHERE id = ?", (paper_id,)).fetchone()
        if not paper:
            return None
        cur = conn.execute(
            """
            INSERT INTO pdf_annotations(paper_id, page, kind, x, y, width, height, color, text, created_at, updated_at)
            VALUES (:paper_id, :page, :kind, :x, :y, :width, :height, :color, :text, :created_at, :updated_at)
            """,
            fields,
        )
        row = conn.execute("SELECT * FROM pdf_annotations WHERE id = ?", (cur.lastrowid,)).fetchone()
        return row_to_annotation(row)


def delete_pdf_annotation(annotation_id):
    with db() as conn:
        cur = conn.execute("DELETE FROM pdf_annotations WHERE id = ?", (annotation_id,))
        return cur.rowcount > 0


def delete_paper(paper_id):
    with db() as conn:
        row = conn.execute("SELECT pdf_path FROM papers WHERE id = ?", (paper_id,)).fetchone()
        cur = conn.execute("DELETE FROM papers WHERE id = ?", (paper_id,))
    if cur.rowcount and row and row["pdf_path"]:
        try:
            path = Path(row["pdf_path"]).resolve()
            cache_root = PDF_DIR.resolve()
            if cache_root in path.parents:
                path.unlink(missing_ok=True)
        except OSError:
            pass
    return cur.rowcount > 0


def list_tags():
    with db() as conn:
        rows = conn.execute(
            """
            SELECT tags.name, COUNT(paper_tags.paper_id) AS count
            FROM tags
            LEFT JOIN paper_tags ON paper_tags.tag_id = tags.id
            GROUP BY tags.id
            HAVING count > 0
            ORDER BY tags.name
            """
        ).fetchall()
        return [dict(row) for row in rows]


def bibtex_key(paper):
    author = paper.get("authors", "").split(",")[0].split(" and ")[0].strip().split(" ")[-1] or "paper"
    year = paper.get("year", "") or "nd"
    word = re.sub(r"[^A-Za-z0-9]", "", paper.get("title", "").split(" ")[0] or "paper")
    return re.sub(r"[^A-Za-z0-9]", "", f"{author}{year}{word}")


def export_bibtex():
    entries = []
    for paper in list_papers():
        kind = "article" if paper.get("venue") else "misc"
        fields = {
            "title": paper.get("title"),
            "author": paper.get("authors"),
            "year": paper.get("year"),
            "journal": paper.get("venue"),
            "doi": paper.get("doi") if not paper.get("doi", "").startswith("arXiv:") else "",
            "url": paper.get("url"),
            "abstract": paper.get("abstract"),
        }
        body = ",\n".join(
            f"  {key} = {{{value}}}" for key, value in fields.items() if value
        )
        entries.append(f"@{kind}{{{bibtex_key(paper)},\n{body}\n}}")
    return "\n\n".join(entries) + ("\n" if entries else "")


class Handler(SimpleHTTPRequestHandler):
    def translate_path(self, path):
        parsed = urllib.parse.urlparse(path)
        clean = parsed.path
        if clean == "/":
            clean = "/index.html"
        return str(STATIC_DIR / clean.lstrip("/"))

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def json_response(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def text_response(self, body, content_type="text/plain; charset=utf-8", status=200):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def file_response(self, path, content_type="application/octet-stream"):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(path.stat().st_size))
        self.send_header("Content-Disposition", f'inline; filename="{path.name}"')
        self.end_headers()
        with path.open("rb") as handle:
            shutil.copyfileobj(handle, self.wfile)

    def read_json(self):
        length = int(self.headers.get("content-length", "0"))
        if not length:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.path == "/api/papers":
            papers = list_papers(query.get("q", [""])[0], query.get("tag", [""])[0])
            opportunistic_figure_backfill(papers)
            papers = list_papers(query.get("q", [""])[0], query.get("tag", [""])[0])
            self.json_response({"papers": papers})
            return
        if parsed.path == "/api/tags":
            self.json_response({"tags": list_tags()})
            return
        match = re.match(r"^/api/papers/(\d+)/pdf$", parsed.path)
        if match:
            path, error = pdf_file_for_paper(int(match.group(1)))
            if not path:
                self.json_response({"ok": False, "error": error}, 404)
                return
            self.file_response(path, "application/pdf")
            return
        match = re.match(r"^/api/papers/(\d+)/annotations$", parsed.path)
        if match:
            self.json_response({"annotations": list_pdf_annotations(int(match.group(1)))})
            return
        if parsed.path == "/api/export/bibtex":
            self.text_response(export_bibtex(), "application/x-bibtex; charset=utf-8")
            return
        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/papers":
            paper = create_paper(self.read_json())
            paper = ensure_paper_figure(paper)
            self.json_response({"paper": paper}, 201)
            return
        if parsed.path == "/api/capture":
            data = self.read_json()
            fetched = fetch_page_metadata(data.get("url", ""))
            merged = {**fetched, **{k: v for k, v in data.items() if v}}
            paper = create_paper(merged)
            paper = ensure_paper_figure(paper)
            self.json_response({"paper": paper}, 201)
            return
        if parsed.path == "/api/open-url":
            data = self.read_json()
            self.json_response({"ok": open_external_url(data.get("url", ""))})
            return
        match = re.match(r"^/api/papers/(\d+)/open-local-pdf$", parsed.path)
        if match:
            data = self.read_json()
            self.json_response(open_local_pdf(int(match.group(1)), data.get("reader_app", "")))
            return
        match = re.match(r"^/api/papers/(\d+)/download-pdf$", parsed.path)
        if match:
            data = self.read_json()
            self.json_response(download_pdf_for_paper(int(match.group(1)), bool(data.get("overwrite"))))
            return
        if parsed.path == "/api/pdfs/download-all":
            data = self.read_json()
            self.json_response(download_all_pdfs(bool(data.get("overwrite"))))
            return
        if parsed.path == "/api/enrich/arxiv-figures":
            data = self.read_json()
            self.json_response(enrich_all_arxiv_figures(bool(data.get("overwrite"))))
            return
        match = re.match(r"^/api/papers/(\d+)/annotations$", parsed.path)
        if match:
            annotation = create_pdf_annotation(int(match.group(1)), self.read_json())
            if not annotation:
                self.json_response({"error": "Paper not found"}, 404)
                return
            self.json_response({"annotation": annotation}, 201)
            return
        self.json_response({"error": "Not found"}, 404)

    def do_PUT(self):
        match = re.match(r"^/api/papers/(\d+)$", urllib.parse.urlparse(self.path).path)
        if not match:
            self.json_response({"error": "Not found"}, 404)
            return
        paper = update_paper(int(match.group(1)), self.read_json())
        if not paper:
            self.json_response({"error": "Paper not found"}, 404)
            return
        self.json_response({"paper": paper})

    def do_DELETE(self):
        match = re.match(r"^/api/annotations/(\d+)$", urllib.parse.urlparse(self.path).path)
        if match:
            self.json_response({"ok": delete_pdf_annotation(int(match.group(1)))})
            return
        match = re.match(r"^/api/papers/(\d+)$", urllib.parse.urlparse(self.path).path)
        if not match:
            self.json_response({"error": "Not found"}, 404)
            return
        self.json_response({"ok": delete_paper(int(match.group(1)))})


def main():
    init_db()
    port = int(os.environ.get("PORT", "8765"))
    try:
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    except OSError as exc:
        if exc.errno in (48, 98):
            print(
                f"Port {port} is already in use. The app may already be running at "
                f"http://127.0.0.1:{port}\n"
                f"To use another port, run: PORT=8766 python3 server.py",
                file=sys.stderr,
            )
            raise SystemExit(1)
        raise
    print(f"Nimble Scholar running at http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped")


if __name__ == "__main__":
    main()
