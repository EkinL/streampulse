#!/usr/bin/env python3
"""Genere des formats accessibles de la documentation StreamPulse.

Produit dans docs/accessible/ :

- streampulse-documentation.epub : l'ensemble de la documentation technique
  (README, docs/*.md, docs/ADR/*.md) en un seul livre numerique reflowable.
  Police, interligne et couleurs restent au choix du lecteur (aucune n'est
  imposee dans le CSS) : compatible plage braille, synthese vocale integree
  aux liseuses, et zoom sans perte de mise en page contrairement a un PDF.
- guide-utilisateur.m4a et accessibilite.m4a : narration audio (voix
  francaise du systeme) du guide utilisateur et du document d'accessibilite,
  pour la formation et pour les personnes en situation de handicap visuel.
  Necessite `say` et `afconvert` (macOS) ; genere l'EPUB quand meme si absents.

Repond au critere Ce3.6.4 du bloc 3 (RNCP 38822) : la documentation
technique doit inclure des solutions pour les utilisateurs en situation de
handicap, au-dela de l'application elle-meme. Voir docs/accessibilite.md.

Usage : python3 docs/scripts/build_accessible_docs.py
Sans dependance externe (bibliotheque standard uniquement) hormis les
binaires `say`/`afconvert` pour la partie audio.
"""
from __future__ import annotations

import html
import re
import shutil
import subprocess
import sys
import uuid
import zipfile
from pathlib import Path

DOCS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = DOCS_DIR.parent
OUTPUT_DIR = DOCS_DIR / "accessible"

# Ordre et titres repris du tableau de documentation du README.
DOC_LIST: list[tuple[Path, str]] = [
    (REPO_ROOT / "README.md", "StreamPulse"),
    (DOCS_DIR / "api.md", "API"),
    (DOCS_DIR / "user-stories.md", "User stories"),
    (DOCS_DIR / "diagrammes.md", "Diagrammes UML et BPMN"),
    (DOCS_DIR / "base-de-donnees.md", "Schema de la base de donnees"),
    (DOCS_DIR / "securite.md", "Schema general de securite"),
    (DOCS_DIR / "guide-utilisateur.md", "Guide utilisateur et plan de formation"),
    (DOCS_DIR / "accessibilite.md", "Accessibilite"),
    (DOCS_DIR / "performance.md", "Fluidite de l'interface"),
    (DOCS_DIR / "plan-de-tests.md", "Plan de tests"),
    (DOCS_DIR / "cahier-de-recette.md", "Cahier de recette"),
    (DOCS_DIR / "slo.md", "Objectifs de niveau de service"),
    (DOCS_DIR / "rgpd.md", "Donnees personnelles et RGPD"),
    (DOCS_DIR / "deployment.md", "Deploiement"),
    (DOCS_DIR / "operations.md", "Operations"),
    (DOCS_DIR / "scalability.md", "Scalabilite"),
    (REPO_ROOT / "CHANGELOG.md", "Changelog"),
    (DOCS_DIR / "ADR" / "001-clean-architecture.md", "ADR 001 - Clean Architecture"),
    (DOCS_DIR / "ADR" / "002-state-management-riverpod.md", "ADR 002 - Riverpod"),
    (DOCS_DIR / "ADR" / "003-streaming-sse.md", "ADR 003 - Streaming SSE"),
    (DOCS_DIR / "ADR" / "004-background-audio.md", "ADR 004 - Lecture en arriere-plan"),
    (DOCS_DIR / "ADR" / "004-observabilite-otel.md", "ADR 004 - Observabilite"),
    (DOCS_DIR / "ADR" / "005-choix-postgresql.md", "ADR 005 - PostgreSQL"),
    (DOCS_DIR / "ADR" / "005-http-timeouts.md", "ADR 005 - Timeouts HTTP"),
    (DOCS_DIR / "ADR" / "006-strategie-auth-jwt.md", "ADR 006 - Authentification JWT"),
    (DOCS_DIR / "ADR" / "007-effacement-compte-rgpd.md", "ADR 007 - Effacement de compte"),
    (DOCS_DIR / "ADR" / "008-dashboard-alertes-grafana.md", "ADR 008 - Dashboard Grafana"),
]

# Docs narrees en audio : les deux documents de prise en main / accessibilite,
# pas l'ensemble du corpus (references API, migrations SQL, code Mermoid ne
# se pretent pas a une lecture audio utile - voir docs/accessible/README.md).
AUDIO_DOCS: list[tuple[Path, str]] = [
    (DOCS_DIR / "guide-utilisateur.md", "guide-utilisateur"),
    (DOCS_DIR / "accessibilite.md", "accessibilite"),
]

FRENCH_VOICE_PREFERENCE = ["Thomas", "Jacques", "Amelie", "Amélie"]


# --------------------------------------------------------------------------
# Analyse markdown -> blocs (parseur delibrement simple : suffisant pour des
# documents ecrits a la main, dans un style Markdown homogene).
# --------------------------------------------------------------------------

def parse_blocks(md_text: str) -> list[tuple]:
    lines = md_text.split("\n")
    blocks: list[tuple] = []
    i, n = 0, len(lines)

    def is_table_row(s: str) -> bool:
        return s.startswith("|")

    while i < n:
        raw = lines[i]
        s = raw.strip()

        if s == "":
            i += 1
            continue

        if s.startswith("```"):
            lang = s[3:].strip()
            i += 1
            code_lines = []
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # ferme la balise
            blocks.append(("code", lang, "\n".join(code_lines)))
            continue

        if s.startswith("#"):
            level = len(s) - len(s.lstrip("#"))
            text = s[level:].strip()
            blocks.append(("heading", min(level, 6), text))
            i += 1
            continue

        if s in ("---", "***", "___"):
            blocks.append(("hr",))
            i += 1
            continue

        if s.startswith(">"):
            quote_lines = []
            while i < n and lines[i].strip().startswith(">"):
                quote_lines.append(lines[i].strip().lstrip(">").strip())
                i += 1
            blocks.append(("quote", " ".join(quote_lines)))
            continue

        if is_table_row(s):
            table_lines = []
            while i < n and is_table_row(lines[i].strip()):
                table_lines.append(lines[i].strip())
                i += 1
            blocks.append(("table", table_lines))
            continue

        if re.match(r"^[-*] ", s):
            items = []
            while i < n and re.match(r"^[-*] ", lines[i].strip()):
                items.append(re.sub(r"^[-*] ", "", lines[i].strip()))
                i += 1
            blocks.append(("ul", items))
            continue

        if re.match(r"^\d+\. ", s):
            items = []
            while i < n and re.match(r"^\d+\. ", lines[i].strip()):
                items.append(re.sub(r"^\d+\. ", "", lines[i].strip()))
                i += 1
            blocks.append(("ol", items))
            continue

        para_lines = [s]
        i += 1
        stop_prefixes = ("#", "```", ">", "|", "- ", "* ")
        while i < n:
            nxt = lines[i].strip()
            if nxt == "" or nxt.startswith(stop_prefixes) or nxt in ("---", "***", "___") or re.match(r"^\d+\. ", nxt):
                break
            para_lines.append(nxt)
            i += 1
        blocks.append(("para", " ".join(para_lines)))

    return blocks


def parse_table(table_lines: list[str]) -> tuple[list[str], list[list[str]]]:
    def split_row(line: str) -> list[str]:
        line = line.strip()
        if line.startswith("|"):
            line = line[1:]
        if line.endswith("|"):
            line = line[:-1]
        return [c.strip() for c in line.split("|")]

    header = split_row(table_lines[0])
    rows = [split_row(l) for l in table_lines[2:]]  # ligne 1 = separateur ---|---
    return header, rows


def github_slug(text: str, seen: dict[str, int]) -> str:
    s = text.lower()
    s = re.sub(r"[^\w\s\-]", "", s, flags=re.UNICODE)
    s = s.strip()
    s = re.sub(r"\s+", "-", s)
    if s in seen:
        seen[s] += 1
        return f"{s}-{seen[s]}"
    seen[s] = 0
    return s


# --------------------------------------------------------------------------
# Rendu XHTML (pour l'EPUB)
# --------------------------------------------------------------------------

def build_link_html(link_text: str, url: str, basename_map: dict[str, str]) -> str:
    esc_text = html.escape(link_text)
    if url.startswith(("http://", "https://", "mailto:")):
        return f'<a href="{html.escape(url, quote=True)}">{esc_text}</a>'
    path_part, _, anchor = url.partition("#")
    if path_part == "":
        return f'<a href="#{anchor}">{esc_text}</a>'
    basename = path_part.rsplit("/", 1)[-1]
    target = basename_map.get(basename)
    if target:
        href = target + (f"#{anchor}" if anchor else "")
        return f'<a href="{href}">{esc_text}</a>'
    return esc_text  # reference locale non resolue : degrade en texte, pas de lien mort


def inline_to_html(text: str, basename_map: dict[str, str]) -> str:
    placeholders: list[str] = []

    def link_sub(m: re.Match) -> str:
        placeholders.append(build_link_html(m.group(1), m.group(2), basename_map))
        return f"\x00{len(placeholders) - 1}\x00"

    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link_sub, text)
    text = html.escape(text)

    def code_sub(m: re.Match) -> str:
        placeholders.append(f"<code>{m.group(1)}</code>")
        return f"\x00{len(placeholders) - 1}\x00"

    # Code spans are protected before bold/italic: a literal "*" inside a
    # code span (e.g. a glob like `test/features/*/data`) must never be
    # read as emphasis syntax reaching across into the next code span.
    text = re.sub(r"`([^`]+)`", code_sub, text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    for idx, rendered in enumerate(placeholders):
        text = text.replace(f"\x00{idx}\x00", rendered)
    return text


def blocks_to_xhtml(blocks: list[tuple], basename_map: dict[str, str]) -> str:
    out: list[str] = []
    seen_slugs: dict[str, int] = {}
    for b in blocks:
        kind = b[0]
        if kind == "heading":
            level, text = b[1], b[2]
            slug = github_slug(text, seen_slugs)
            out.append(f'<h{level} id="{slug}">{inline_to_html(text, basename_map)}</h{level}>')
        elif kind == "para":
            out.append(f"<p>{inline_to_html(b[1], basename_map)}</p>")
        elif kind == "ul":
            items = "".join(f"<li>{inline_to_html(it, basename_map)}</li>" for it in b[1])
            out.append(f"<ul>{items}</ul>")
        elif kind == "ol":
            items = "".join(f"<li>{inline_to_html(it, basename_map)}</li>" for it in b[1])
            out.append(f"<ol>{items}</ol>")
        elif kind == "table":
            header, rows = parse_table(b[1])
            thead = "".join(f'<th scope="col">{inline_to_html(h, basename_map)}</th>' for h in header)
            body_rows = []
            for r in rows:
                cells = "".join(f"<td>{inline_to_html(c, basename_map)}</td>" for c in r)
                body_rows.append(f"<tr>{cells}</tr>")
            out.append(f"<table><thead><tr>{thead}</tr></thead><tbody>{''.join(body_rows)}</tbody></table>")
        elif kind == "quote":
            out.append(f"<blockquote><p>{inline_to_html(b[1], basename_map)}</p></blockquote>")
        elif kind == "hr":
            out.append("<hr/>")
        elif kind == "code":
            lang = b[1] or ""
            label = "Diagramme Mermaid (code source, restitution textuelle)" if lang == "mermaid" else (f"Extrait de code ({lang})" if lang else "Extrait")
            out.append(f'<p class="code-label">{html.escape(label)}</p><pre><code>{html.escape(b[2])}</code></pre>')
    return "\n".join(out)


CSS = """
/* Aucune couleur n'est imposee : le lecteur garde son propre theme
   (clair, sombre, contraste eleve) et ses propres reglages de police. */
body { font-family: serif; line-height: 1.5; margin: 1em; }
h1, h2, h3, h4 { font-family: sans-serif; line-height: 1.25; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { border: 1px solid currentColor; padding: 0.4em 0.6em; text-align: left; }
code, pre { font-family: monospace; }
pre { overflow-x: auto; padding: 0.6em; border: 1px solid currentColor; }
.code-label { font-style: italic; }
blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid currentColor; }
nav[epub|type~="toc"] ol { list-style: none; padding-left: 1em; }
"""

CHAPTER_TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="fr" lang="fr">
<head>
<meta charset="utf-8"/>
<title>{title}</title>
<link rel="stylesheet" type="text/css" href="styles.css"/>
</head>
<body>
<h1>{title}</h1>
{body}
</body>
</html>
"""

CONTAINER_XML = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def build_epub(chapters: list[dict], output_path: Path, book_title: str) -> None:
    book_uid = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "streampulse-docs-epub-v1"))

    manifest_items = ['<item id="css" href="styles.css" media-type="text/css"/>']
    spine_items = []
    nav_lis = []
    ncx_points = []
    for idx, ch in enumerate(chapters, start=1):
        manifest_items.append(f'<item id="{ch["id"]}" href="{ch["filename"]}" media-type="application/xhtml+xml"/>')
        spine_items.append(f'<itemref idref="{ch["id"]}"/>')
        nav_lis.append(f'<li><a href="{ch["filename"]}">{html.escape(ch["title"])}</a></li>')
        ncx_points.append(
            f'<navPoint id="navpoint-{idx}" playOrder="{idx}">'
            f'<navLabel><text>{html.escape(ch["title"])}</text></navLabel>'
            f'<content src="{ch["filename"]}"/></navPoint>'
        )

    nav_xhtml = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="fr" lang="fr">
<head><meta charset="utf-8"/><title>Table des matieres</title><link rel="stylesheet" type="text/css" href="styles.css"/></head>
<body>
<nav epub:type="toc" id="toc"><h1>Table des matieres</h1><ol>{''.join(nav_lis)}</ol></nav>
</body>
</html>"""

    ncx = f"""<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="{book_uid}"/>
  </head>
  <docTitle><text>{html.escape(book_title)}</text></docTitle>
  <navMap>{''.join(ncx_points)}</navMap>
</ncx>"""

    opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="fr">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="bookid">{book_uid}</dc:identifier>
    <dc:title>{html.escape(book_title)}</dc:title>
    <dc:language>fr</dc:language>
    <dc:creator>Equipe StreamPulse</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
    <meta property="schema:accessMode">textual</meta>
    <meta property="schema:accessibilityFeature">structuralNavigation</meta>
    <meta property="schema:accessibilityFeature">tableOfContents</meta>
    <meta property="schema:accessibilityFeature">readingOrder</meta>
    <meta property="schema:accessibilityHazard">none</meta>
    <meta property="schema:accessibilitySummary">Document texte structure par titres, navigation par table des matieres, aucune information portee uniquement par la couleur ou le son, aucune couleur imposee (le theme du lecteur s'applique).</meta>
  </metadata>
  <manifest>
    {''.join(manifest_items)}
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    {''.join(spine_items)}
  </spine>
</package>"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_path, "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER_XML)
        z.writestr("OEBPS/styles.css", CSS)
        z.writestr("OEBPS/nav.xhtml", nav_xhtml)
        z.writestr("OEBPS/toc.ncx", ncx)
        z.writestr("OEBPS/content.opf", opf)
        for ch in chapters:
            z.writestr(f"OEBPS/{ch['filename']}", CHAPTER_TEMPLATE.format(title=html.escape(ch["title"]), body=ch["body_html"]))


# --------------------------------------------------------------------------
# Rendu texte pour narration audio
# --------------------------------------------------------------------------

def inline_to_speech(text: str) -> str:
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = text.replace("`", "")
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]+)\*", r"\1", text)
    return text


def blocks_to_speech(blocks: list[tuple]) -> str:
    out: list[str] = []
    for b in blocks:
        kind = b[0]
        if kind == "heading":
            out.append(inline_to_speech(b[2]) + ".")
        elif kind == "para":
            out.append(inline_to_speech(b[1]))
        elif kind in ("ul", "ol"):
            out.extend(inline_to_speech(it) + "." for it in b[1])
        elif kind == "table":
            header, rows = parse_table(b[1])
            for r in rows:
                pieces = [f"{inline_to_speech(h)} : {inline_to_speech(c)}" for h, c in zip(header, r) if c.strip()]
                if pieces:
                    out.append(". ".join(pieces) + ".")
        elif kind == "quote":
            out.append("Remarque. " + inline_to_speech(b[1]))
        elif kind == "code":
            out.append("Extrait de code non lu ici ; voir la version texte de la documentation.")
        # 'hr' : ignore, simple pause entre paragraphes deja assuree par le \n\n
    return "\n\n".join(out)


def find_french_voice() -> str | None:
    try:
        listing = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, check=True).stdout
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    for preferred in FRENCH_VOICE_PREFERENCE:
        for line in listing.splitlines():
            if line.startswith(preferred) and "fr_FR" in line:
                return preferred
    for line in listing.splitlines():
        if "fr_FR" in line:
            return line.split()[0]
    return None


def build_audio(text: str, output_path: Path, voice: str) -> bool:
    if not (shutil.which("say") and shutil.which("afconvert")):
        print(f"  say/afconvert indisponibles : {output_path.name} non genere (EPUB toujours produit).")
        return False

    output_path.parent.mkdir(parents=True, exist_ok=True)
    text_file = output_path.with_suffix(".txt")
    aiff_file = output_path.with_suffix(".aiff")
    text_file.write_text(text, encoding="utf-8")
    try:
        subprocess.run(["say", "-v", voice, "-f", str(text_file), "-o", str(aiff_file)], check=True)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(aiff_file), str(output_path)], check=True)
        return True
    finally:
        text_file.unlink(missing_ok=True)
        aiff_file.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------

def slugify_filename(path: Path) -> str:
    if path.parent.name == "ADR":
        return "adr-" + path.stem.lower()
    if path.name == "README.md":
        return "readme"
    return path.stem.lower()


def main() -> int:
    missing = [p for p, _ in DOC_LIST if not p.exists()]
    if missing:
        print("Documents introuvables :", *missing, sep="\n  - ", file=sys.stderr)
        return 1

    basename_map = {p.name: f"{slugify_filename(p)}.xhtml" for p, _ in DOC_LIST}

    print("Construction de l'EPUB (documentation technique complete)...")
    chapters = []
    for path, title in DOC_LIST:
        blocks = parse_blocks(path.read_text(encoding="utf-8"))
        body_html = blocks_to_xhtml(blocks, basename_map)
        chapters.append({"id": slugify_filename(path), "filename": f"{slugify_filename(path)}.xhtml", "title": title, "body_html": body_html})

    epub_path = OUTPUT_DIR / "streampulse-documentation.epub"
    build_epub(chapters, epub_path, "StreamPulse - Documentation technique")
    print(f"  -> {epub_path.relative_to(REPO_ROOT)} ({epub_path.stat().st_size // 1024} Ko, {len(chapters)} chapitres)")

    voice = find_french_voice()
    if voice:
        print(f"Narration audio avec la voix '{voice}'...")
    else:
        print("Aucune voix francaise disponible : narration audio ignoree.")

    for path, out_name in AUDIO_DOCS:
        blocks = parse_blocks(path.read_text(encoding="utf-8"))
        speech_text = blocks_to_speech(blocks)
        out_path = OUTPUT_DIR / f"{out_name}.m4a"
        if voice and build_audio(speech_text, out_path, voice):
            print(f"  -> {out_path.relative_to(REPO_ROOT)} ({out_path.stat().st_size // 1024} Ko)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
