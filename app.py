#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Serveur d'application local pour la Bibliothèque PDF Intelligente.
Supporte l'accès PC et Mobile (Android via Wi-Fi), l'upload direct de PDF et PWA.
"""

import os
import sys
import json
import sqlite3
import hashlib
import webbrowser
import threading
import urllib.request
import urllib.error
from pathlib import Path
from flask import Flask, request, jsonify, render_template_string, send_file
from pypdf import PdfReader

app = Flask(__name__)
app.config['JSON_AS_ASCII'] = False
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100 Mo max

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, 'library.db')
CONFIG_FILE = os.path.join(BASE_DIR, 'config.json')
UPLOAD_DIR = os.path.join(BASE_DIR, 'uploads')
os.makedirs(UPLOAD_DIR, exist_ok=True)

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "llama-3.3-70b-versatile"
FAST_MODEL = "llama-3.1-8b-instant"

# ==================== CONFIGURATION ====================

def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "groq_api_key": os.environ.get("GROQ_API_KEY", ""),
        "model": DEFAULT_MODEL,
        "scan_page_count": 3,
        "privacy_accepted": False
    }

def save_config(cfg):
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

# ==================== BASE DE DONNEES ====================

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS domains (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            is_custom INTEGER NOT NULL DEFAULT 0
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS subdomains (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            FOREIGN KEY (domain_id) REFERENCES domains (id) ON DELETE CASCADE,
            UNIQUE(domain_id, name)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            file_name TEXT NOT NULL,
            file_hash TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            page_count INTEGER NOT NULL DEFAULT 0,
            modified_date INTEGER NOT NULL,
            domain_id INTEGER,
            subdomain_id INTEGER,
            summary TEXT,
            keywords TEXT,
            language TEXT,
            level TEXT,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            is_excluded INTEGER NOT NULL DEFAULT 0,
            ai_status TEXT NOT NULL DEFAULT 'pending',
            created_at INTEGER NOT NULL,
            last_opened_at INTEGER,
            FOREIGN KEY (domain_id) REFERENCES domains (id),
            FOREIGN KEY (subdomain_id) REFERENCES subdomains (id)
        )
    """)
    cur.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            document_id UNINDEXED,
            file_name,
            summary,
            keywords,
            domain_name,
            subdomain_name
        )
    """)

    default_taxonomies = {
        "Informatique": ["Programmation", "Systèmes & Réseaux", "Bases de données", "Génie logiciel"],
        "Intelligence Artificielle": ["Machine Learning", "Deep Learning", "NLP", "Vision par ordinateur"],
        "Data Science": ["Analyse de données", "Big Data", "Visualisation"],
        "Mathématiques": ["Analyse", "Algèbre", "Probabilités"],
        "Statistiques": ["Statistique descriptive", "Statistique inférentielle", "Économétrie"],
        "Économie": ["Microéconomie", "Macroéconomie", "Économie monétaire"],
        "Finance": ["Marchés financiers", "Gestion des risques", "Finance quantitative"],
        "Droit": ["Droit civil", "Droit des affaires", "Droit pénal", "Droit public"],
        "Médecine": ["Anatomie", "Pharmacologie", "Santé publique"],
        "Agriculture": ["Agronomie", "Agroéconomie", "Assurance agricole", "Élevage"],
        "Gestion": ["Management", "Marketing", "Ressources Humaines"],
        "Sciences Sociales": ["Sociologie", "Psychologie", "Sciences politiques"]
    }

    for dom, subs in default_taxonomies.items():
        cur.execute("INSERT OR IGNORE INTO domains (name, is_custom) VALUES (?, 0)", (dom,))
        cur.execute("SELECT id FROM domains WHERE name = ?", (dom,))
        row = cur.fetchone()
        if row:
            dom_id = row[0]
            for sub in subs:
                cur.execute("INSERT OR IGNORE INTO subdomains (domain_id, name) VALUES (?, ?)", (dom_id, sub))

    conn.commit()
    conn.close()

def get_or_create_domain(cur, name):
    name = name.strip()
    cur.execute("SELECT id FROM domains WHERE LOWER(name) = ?", (name.lower(),))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO domains (name, is_custom) VALUES (?, 1)", (name,))
    return cur.lastrowid

def get_or_create_subdomain(cur, domain_id, name):
    name = name.strip()
    cur.execute("SELECT id FROM subdomains WHERE domain_id = ? AND LOWER(name) = ?", (domain_id, name.lower(),))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO subdomains (domain_id, name) VALUES (?, ?)", (domain_id, name))
    return cur.lastrowid

# ==================== EXTRACTION & GROQ ====================

def calculate_sha256(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def extract_pdf_info(filepath: str, max_pages: int = 3):
    try:
        reader = PdfReader(filepath)
        total_pages = len(reader.pages)
        pages_to_extract = min(total_pages, max_pages)

        extracted = []
        for i in range(pages_to_extract):
            txt = reader.pages[i].extract_text() or ""
            if txt.strip():
                extracted.append(f"--- Page {i+1} ---\n{txt.strip()}")

        text = "\n\n".join(extracted)
        if len(text) > 7000:
            text = text[:7000] + "\n[...texte tronqué pour l'analyse...]"
        return text, total_pages
    except Exception as e:
        print(f"Erreur extraction {filepath}: {e}")
        return "", 0

def call_groq(api_key: str, filename: str, text: str, model: str = DEFAULT_MODEL):
    system_prompt = """Tu es un documentaliste universitaire et scientifique expert.
Analyse le nom du document et le texte des premières pages pour le cataloguer avec précision.
Tu DOIS répondre STRICTEMENT avec cet objet JSON valide :
{
  "domaine": "Domaine principal (ex: Mathématiques, Statistiques, Informatique, Économie, Finance, Droit, Médecine, Sciences Sociales...)",
  "sous_domaine": "Sous-domaine précis",
  "resume": "Résumé clair et synthétique en 2 ou 3 phrases du contenu",
  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"],
  "langue": "français | anglais | autre",
  "niveau": "débutant | intermédiaire | avancé | recherche"
}
Ne fournis AUCUN texte en dehors du JSON."""

    user_prompt = f"Nom du fichier : \"{filename}\"\n\nExtrait des premières pages :\n\"\"\"\n{text}\n\"\"\""

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"}
    }

    req = urllib.request.Request(
        GROQ_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key.strip()}",
            "Content-Type": "application/json; charset=utf-8"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            return json.loads(content)
    except Exception as e:
        print(f"Erreur Groq: {e}")
        return None

def process_file_into_db(fpath):
    conn = get_db()
    cur = conn.cursor()

    stat = os.stat(fpath)
    fhash = calculate_sha256(fpath)
    fname = os.path.basename(fpath)

    cur.execute("SELECT id, ai_status FROM documents WHERE file_hash = ?", (fhash,))
    existing = cur.fetchone()
    if existing and existing["ai_status"] == 'analyzed':
        conn.close()
        return "already_indexed"

    cfg = load_config()
    api_key = cfg.get("groq_api_key", "")
    model = cfg.get("model", DEFAULT_MODEL)
    max_pages = cfg.get("scan_page_count", 3)

    text, pages = extract_pdf_info(fpath, max_pages=max_pages)

    ai_data = None
    if api_key:
        ai_data = call_groq(api_key, fname, text, model=model)

    if not ai_data:
        ai_data = {
            "domaine": "Documents & Cours" if ("cours" in fname.lower() or "questionnaire" in fname.lower()) else "Général",
            "sous_domaine": "Pédagogie & TP" if "tp" in fname.lower() else "Général",
            "resume": f"Document PDF de {pages} pages ({fname}). Analyse IA complète disponible dès que votre clé Groq est configurée.",
            "mots_cles": ["pdf", "document", fname.replace(".pdf", "").replace("_", " ")],
            "langue": "français",
            "niveau": "intermédiaire"
        }

    domain_id = get_or_create_domain(cur, ai_data.get("domaine", "Autre"))
    subdomain_id = get_or_create_subdomain(cur, domain_id, ai_data.get("sous_domaine", "Général"))

    cur.execute("""
        INSERT OR REPLACE INTO documents 
        (file_path, file_name, file_hash, file_size, page_count, modified_date, domain_id, subdomain_id, summary, keywords, language, level, ai_status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'analyzed', ?)
    """, (
        fpath, fname, fhash, stat.st_size, pages, int(stat.st_mtime * 1000),
        domain_id, subdomain_id, ai_data.get("resume"),
        json.dumps(ai_data.get("mots_cles", []), ensure_ascii=False),
        ai_data.get("langue", "français"), ai_data.get("niveau", "intermédiaire"),
        int(os.path.getctime(fpath) * 1000)
    ))
    doc_id = cur.lastrowid

    cur.execute("DELETE FROM documents_fts WHERE document_id = ?", (doc_id,))
    cur.execute("""
        INSERT INTO documents_fts (document_id, file_name, summary, keywords, domain_name, subdomain_name)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        doc_id, fname, ai_data.get("resume", ""),
        " ".join(ai_data.get("mots_cles", [])),
        ai_data.get("domaine", ""), ai_data.get("sous_domaine", "")
    ))

    conn.commit()
    conn.close()
    return "analyzed"

# ==================== ROUTES API ====================

@app.route('/manifest.json')
def manifest():
    return jsonify({
        "name": "Bibliothèque PDF Intelligente",
        "short_name": "PDF IA",
        "start_url": "/",
        "display": "standalone",
        "background_color": "#1e3a8a",
        "theme_color": "#1e3a8a",
        "icons": [
            {
                "src": "https://cdn-icons-png.flaticon.com/512/337/337946.png",
                "sizes": "512x512",
                "type": "image/png"
            }
        ]
    })

@app.route('/api/upload', methods=['POST'])
def api_upload():
    if 'file' not in request.files:
        return jsonify({"error": "Aucun fichier reçu"}), 400
    file = request.files['file']
    if not file.filename or not file.filename.lower().endswith('.pdf'):
        return jsonify({"error": "Format PDF requis"}), 400

    target_path = os.path.join(UPLOAD_DIR, file.filename)
    file.save(target_path)
    status = process_file_into_db(target_path)

    return jsonify({"status": status, "filename": file.filename})

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    if request.method == 'POST':
        data = request.json or {}
        cfg = load_config()
        if 'groq_api_key' in data:
            cfg['groq_api_key'] = data['groq_api_key'].strip()
        if 'model' in data:
            cfg['model'] = data['model']
        if 'scan_page_count' in data:
            cfg['scan_page_count'] = int(data['scan_page_count'])
        if 'privacy_accepted' in data:
            cfg['privacy_accepted'] = bool(data['privacy_accepted'])
        save_config(cfg)
        return jsonify({"status": "ok", "config": cfg})
    else:
        cfg = load_config()
        masked_key = ""
        if cfg.get("groq_api_key"):
            k = cfg["groq_api_key"]
            masked_key = k[:8] + "..." + k[-4:] if len(k) > 12 else "****"
        return jsonify({
            "has_key": bool(cfg.get("groq_api_key")),
            "masked_key": masked_key,
            "model": cfg.get("model", DEFAULT_MODEL),
            "scan_page_count": cfg.get("scan_page_count", 3),
            "privacy_accepted": cfg.get("privacy_accepted", False)
        })

@app.route('/api/test-groq', methods=['POST'])
def api_test_groq():
    data = request.json or {}
    key = data.get("key") or load_config().get("groq_api_key")
    if not key:
        return jsonify({"valid": False, "message": "Veuillez renseigner une clé API"}), 400

    payload = {
        "model": FAST_MODEL,
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 5
    }
    req = urllib.request.Request(
        GROQ_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {key.strip()}",
            "Content-Type": "application/json"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return jsonify({"valid": resp.status == 200, "message": "Connexion Groq réussie !" if resp.status == 200 else "Erreur"})
    except urllib.error.HTTPError as e:
        return jsonify({"valid": False, "message": f"Erreur API ({e.code})"}), 400
    except Exception as e:
        return jsonify({"valid": False, "message": str(e)}), 400

@app.route('/api/domains')
def api_domains():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT d.id, d.name, d.is_custom, COUNT(doc.id) as doc_count
        FROM domains d
        LEFT JOIN documents doc ON d.id = doc.domain_id AND doc.is_excluded = 0
        GROUP BY d.id
        ORDER BY doc_count DESC, d.name ASC
    """)
    domains = [dict(row) for row in cur.fetchall()]
    conn.close()
    return jsonify(domains)

@app.route('/api/documents')
def api_documents():
    query = request.args.get('q', '').strip()
    domain_id = request.args.get('domain_id')
    level = request.args.get('level')
    favorites = request.args.get('favorites') == '1'

    conn = get_db()
    cur = conn.cursor()

    sql_args = []
    if query:
        fts_q = f'"{query.replace("\"", "")}"*'
        sql = """
            SELECT doc.*, d.name as domain_name, s.name as subdomain_name
            FROM documents_fts fts
            JOIN documents doc ON fts.document_id = doc.id
            LEFT JOIN domains d ON doc.domain_id = d.id
            LEFT JOIN subdomains s ON doc.subdomain_id = s.id
            WHERE documents_fts MATCH ? AND doc.is_excluded = 0
        """
        sql_args.append(fts_q)
    else:
        sql = """
            SELECT doc.*, d.name as domain_name, s.name as subdomain_name
            FROM documents doc
            LEFT JOIN domains d ON doc.domain_id = d.id
            LEFT JOIN subdomains s ON doc.subdomain_id = s.id
            WHERE doc.is_excluded = 0
        """

    if domain_id:
        sql += " AND doc.domain_id = ?"
        sql_args.append(int(domain_id))
    if level:
        sql += " AND doc.level = ?"
        sql_args.append(level)
    if favorites:
        sql += " AND doc.is_favorite = 1"

    sql += " ORDER BY doc.created_at DESC"
    cur.execute(sql, sql_args)
    docs = []
    for row in cur.fetchall():
        d = dict(row)
        if d.get('keywords'):
            try:
                d['keywords'] = json.loads(d['keywords'])
            except Exception:
                d['keywords'] = [k.strip() for k in d['keywords'].split(',') if k.strip()]
        else:
            d['keywords'] = []
        docs.append(d)

    conn.close()
    return jsonify(docs)

@app.route('/api/document/<int:doc_id>/favorite', methods=['POST'])
def api_toggle_favorite(doc_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("UPDATE documents SET is_favorite = NOT is_favorite WHERE id = ?", (doc_id,))
    conn.commit()
    cur.execute("SELECT is_favorite FROM documents WHERE id = ?", (doc_id,))
    new_fav = cur.fetchone()[0]
    conn.close()
    return jsonify({"is_favorite": bool(new_fav)})

@app.route('/api/document/<int:doc_id>/open', methods=['POST'])
def api_open_document(doc_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT file_path FROM documents WHERE id = ?", (doc_id,))
    row = cur.fetchone()
    conn.close()
    if not row or not os.path.exists(row[0]):
        return jsonify({"error": "Fichier introuvable"}), 404

    try:
        if sys.platform == 'win32':
            os.startfile(row[0])
        elif sys.platform == 'darwin':
            os.system(f'open "{row[0]}"')
        else:
            os.system(f'xdg-open "{row[0]}"')
        return jsonify({"status": "opened"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/document/<int:doc_id>/download', methods=['GET'])
def api_download_document(doc_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT file_path, file_name FROM documents WHERE id = ?", (doc_id,))
    row = cur.fetchone()
    conn.close()
    if not row or not os.path.exists(row[0]):
        return "Fichier introuvable", 404
    return send_file(row[0], as_attachment=False, download_name=row[1])

@app.route('/api/scan', methods=['POST'])
def api_scan():
    data = request.json or {}
    folder = data.get("folder")
    if not folder or not os.path.exists(folder):
        folder = str(Path.home() / "Documents")

    pdf_files = []
    try:
        for root, _, files in os.walk(folder):
            for f in files:
                if f.lower().endswith('.pdf'):
                    pdf_files.append(os.path.join(root, f))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    analyzed_count = 0
    already_indexed = 0

    for fpath in pdf_files:
        res = process_file_into_db(fpath)
        if res == "analyzed":
            analyzed_count += 1
        elif res == "already_indexed":
            already_indexed += 1

    return jsonify({
        "total_found": len(pdf_files),
        "new_analyzed": analyzed_count,
        "already_indexed": already_indexed
    })

@app.route('/api/stats')
def api_stats():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*), COALESCE(SUM(file_size), 0) FROM documents WHERE is_excluded = 0")
    total_docs, total_size = cur.fetchone()
    cur.execute("SELECT COUNT(DISTINCT domain_id) FROM documents WHERE is_excluded = 0 AND domain_id IS NOT NULL")
    total_domains = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM documents WHERE is_favorite = 1 AND is_excluded = 0")
    total_favs = cur.fetchone()[0]
    conn.close()
    return jsonify({
        "total_docs": total_docs,
        "total_size": total_size,
        "total_domains": total_domains,
        "total_favorites": total_favs
    })

# ==================== INTERFACE HTML ====================

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="theme-color" content="#1e3a8a">
  <link rel="manifest" href="/manifest.json">
  <title>Bibliothèque PDF Intelligente</title>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #1e3a8a;
      --primary-light: #3b82f6;
      --accent: #0d9488;
      --bg: #f8fafc;
      --card-bg: #ffffff;
      --text: #0f172a;
      --text-muted: #64748b;
      --border: #e2e8f0;
      --shadow: 0 4px 6px -1px rgb(0 0 0 / 0.07), 0 2px 4px -2px rgb(0 0 0 / 0.05);
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Inter', sans-serif; -webkit-tap-highlight-color: transparent; }
    body { background: var(--bg); color: var(--text); display: flex; height: 100vh; overflow: hidden; }

    /* SIDEBAR */
    .sidebar {
      width: 270px; background: white; border-right: 1px solid var(--border);
      display: flex; flex-direction: column; padding: 20px 16px;
    }
    .brand {
      display: flex; align-items: center; gap: 10px; font-weight: 700; font-size: 17px; color: var(--primary);
      margin-bottom: 28px;
    }
    .nav-btn {
      display: flex; align-items: center; gap: 12px; padding: 12px 16px; border-radius: 12px;
      color: var(--text-muted); text-decoration: none; font-weight: 500; margin-bottom: 6px;
      cursor: pointer; border: none; background: transparent; width: 100%; text-align: left;
    }
    .nav-btn:hover, .nav-btn.active { background: #eff6ff; color: var(--primary); font-weight: 600; }
    .nav-btn svg { width: 20px; height: 20px; }

    /* MAIN */
    .main { flex: 1; display: flex; flex-direction: column; overflow-y: auto; }
    .header {
      background: white; border-bottom: 1px solid var(--border); padding: 14px 24px;
      display: flex; align-items: center; justify-content: space-between; position: sticky; top: 0; z-index: 10;
      flex-wrap: wrap; gap: 10px;
    }
    .search-box { position: relative; flex: 1; max-width: 450px; min-width: 260px; }
    .search-box input {
      width: 100%; padding: 10px 16px 10px 42px; border-radius: 10px; border: 1px solid var(--border);
      font-size: 14px; outline: none; transition: 0.2s;
    }
    .search-box input:focus { border-color: var(--primary-light); box-shadow: 0 0 0 3px #dbeafe; }
    .search-icon { position: absolute; left: 14px; top: 11px; color: var(--text-muted); }

    .header-actions { display: flex; gap: 8px; }
    .btn {
      padding: 10px 16px; border-radius: 10px; font-weight: 600; font-size: 13px; cursor: pointer;
      border: none; display: flex; align-items: center; gap: 6px; transition: 0.2s; white-space: nowrap;
    }
    .btn-primary { background: var(--primary); color: white; }
    .btn-primary:hover { background: #172554; }
    .btn-outline { background: white; border: 1px solid var(--border); color: var(--text); }
    .btn-outline:hover { background: #f1f5f9; }

    .content { padding: 24px; max-width: 1200px; margin: 0 auto; width: 100%; }

    /* STATS ROW */
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; margin-bottom: 24px; }
    .stat-card {
      background: white; padding: 14px; border-radius: 12px; border: 1px solid var(--border); box-shadow: var(--shadow);
    }
    .stat-val { font-size: 22px; font-weight: 700; color: var(--primary); margin-top: 2px; }
    .stat-lbl { font-size: 12px; color: var(--text-muted); font-weight: 500; }

    /* DOMAINS CARDS */
    .section-title { font-size: 17px; font-weight: 700; margin-bottom: 12px; display: flex; align-items: center; justify-content: space-between; }
    .domains-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; margin-bottom: 24px; }
    .domain-chip {
      background: white; border: 1px solid var(--border); padding: 12px 14px; border-radius: 12px;
      display: flex; align-items: center; justify-content: space-between; cursor: pointer; transition: 0.2s; font-size: 14px;
    }
    .domain-chip:hover { border-color: var(--primary-light); }
    .domain-chip.active { border-color: var(--primary); background: #eff6ff; font-weight: 600; }
    .badge { background: #e0f2fe; color: #0369a1; padding: 2px 8px; border-radius: 20px; font-size: 11px; font-weight: 700; }

    /* DOCS LIST */
    .docs-list { display: flex; flex-direction: column; gap: 12px; }
    .doc-card {
      background: white; border: 1px solid var(--border); border-radius: 14px; padding: 18px;
      box-shadow: var(--shadow); transition: 0.2s; display: flex; flex-direction: column; gap: 10px;
    }
    .doc-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 10px; }
    .doc-title { font-size: 15px; font-weight: 700; color: var(--text); word-break: break-word; }
    .doc-meta { font-size: 12px; color: var(--text-muted); margin-top: 2px; }
    .doc-summary { font-size: 13.5px; color: #334155; line-height: 1.45; background: #f8fafc; padding: 10px 12px; border-radius: 8px; }
    .tags { display: flex; flex-wrap: wrap; gap: 6px; }
    .tag { font-size: 11px; padding: 3px 8px; border-radius: 6px; background: #f1f5f9; color: #475569; font-weight: 500; }
    .tag-domain { background: #dbeafe; color: #1e40af; font-weight: 600; }
    .tag-level { background: #dcfce7; color: #166534; }

    .doc-actions { display: flex; justify-content: flex-end; gap: 8px; border-top: 1px solid #f1f5f9; padding-top: 10px; flex-wrap: wrap; }

    /* MODAL */
    .modal {
      display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.5);
      align-items: center; justify-content: center; z-index: 100; padding: 16px;
    }
    .modal-content {
      background: white; width: 100%; max-width: 480px; border-radius: 16px; padding: 24px; box-shadow: 0 20px 25px -5px rgb(0 0 0 / 0.1);
    }

    /* RESPONSIVE MOBILE */
    @media (max-width: 768px) {
      body { flex-direction: column; }
      .sidebar { width: 100%; border-right: none; border-bottom: 1px solid var(--border); padding: 12px 16px; flex-direction: row; justify-content: space-between; align-items: center; }
      .brand { margin-bottom: 0; }
      .sidebar .nav-btn { display: none; }
      .sidebar .mobile-menu-btn { display: block; }
      .content { padding: 16px; }
      .search-box { max-width: 100%; width: 100%; }
      .header-actions { width: 100%; justify-content: space-between; }
    }
  </style>
</head>
<body>

  <!-- SIDEBAR -->
  <div class="sidebar">
    <div class="brand">
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1-2.5-2.5Z"/><path d="M6 6h10M6 10h10"/></svg>
      Bibliothèque PDF
    </div>
    <button class="nav-btn active" onclick="loadTab('all')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/></svg>
      Tous les documents
    </button>
    <button class="nav-btn" onclick="loadTab('favorites')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
      Favoris
    </button>
    <button class="nav-btn" onclick="openConfigModal()">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
      Clé Groq
    </button>
    <button class="btn btn-outline" style="margin-top:auto;" onclick="openConfigModal()">⚙️ Paramètres</button>
  </div>

  <!-- MAIN -->
  <div class="main">
    <div class="header">
      <div class="search-box">
        <span class="search-icon">🔍</span>
        <input type="text" id="searchInput" placeholder="Recherche intelligente..." oninput="handleSearch()">
      </div>
      <div class="header-actions">
        <!-- Input caché pour upload mobile -->
        <input type="file" id="pdfUploadInput" accept=".pdf" style="display:none;" onchange="handleFileUpload(this)">
        <button class="btn btn-primary" onclick="document.getElementById('pdfUploadInput').click()">
          📤 Importer un PDF
        </button>
        <button class="btn btn-outline" onclick="triggerQuickScan()">
          ⚡ Scan PC
        </button>
      </div>
    </div>

    <div class="content">
      <!-- STATS -->
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-lbl">Documents</div>
          <div class="stat-val" id="statDocs">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-lbl">Domaines IA</div>
          <div class="stat-val" id="statDomains">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-lbl">Favoris</div>
          <div class="stat-val" id="statFavs">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-lbl">Espace</div>
          <div class="stat-val" id="statSize">0 Mo</div>
        </div>
      </div>

      <!-- DOMAINS -->
      <div class="section-title">
        <span>Domaines de votre Bibliothèque</span>
      </div>
      <div class="domains-grid" id="domainsList"></div>

      <!-- DOCS -->
      <div class="section-title">
        <span id="docsSectionTitle">Tous les Documents</span>
        <span id="docsCount" style="font-size:13px; font-weight:normal; color:var(--text-muted);">0 fichier(s)</span>
      </div>
      <div class="docs-list" id="docsList"></div>
    </div>
  </div>

  <!-- MODAL CONFIG -->
  <div class="modal" id="configModal">
    <div class="modal-content">
      <h3 style="margin-bottom:12px;">Configuration Groq API</h3>
      <p style="font-size:13px; color:var(--text-muted); margin-bottom:16px;">
        Votre clé API est stockée en local et n'est utilisée que pour classifier les documents.
      </p>
      <label style="font-size:13px; font-weight:600;">Clé API Groq (gsk_...)</label>
      <input type="password" id="groqKeyInput" style="width:100%; padding:10px; margin:8px 0 16px; border:1px solid var(--border); border-radius:8px;" placeholder="Collez votre clé ici">
      <div id="testKeyResult" style="font-size:13px; margin-bottom:16px;"></div>
      <div style="display:flex; justify-content:space-between; flex-wrap:wrap; gap:8px;">
        <button class="btn btn-outline" onclick="testKey()">Tester</button>
        <div style="display:flex; gap:8px;">
          <button class="btn btn-outline" onclick="closeConfigModal()">Annuler</button>
          <button class="btn btn-primary" onclick="saveKey()">Enregistrer</button>
        </div>
      </div>
    </div>
  </div>

  <script>
    let currentDomainId = null;
    let favoritesOnly = false;

    async function loadStats() {
      const res = await fetch('/api/stats');
      const data = await res.json();
      document.getElementById('statDocs').textContent = data.total_docs;
      document.getElementById('statDomains').textContent = data.total_domains;
      document.getElementById('statFavs').textContent = data.total_favorites;
      document.getElementById('statSize').textContent = (data.total_size / (1024*1024)).toFixed(1) + ' Mo';
    }

    async function loadDomains() {
      const res = await fetch('/api/domains');
      const domains = await res.json();
      const list = document.getElementById('domainsList');
      list.innerHTML = '';

      const allCard = document.createElement('div');
      allCard.className = `domain-chip ${currentDomainId === null ? 'active' : ''}`;
      allCard.innerHTML = `<span><strong>Tous</strong></span> <span class="badge">Tous</span>`;
      allCard.onclick = () => { currentDomainId = null; loadDomains(); loadDocs(); };
      list.appendChild(allCard);

      domains.filter(d => d.doc_count > 0).forEach(d => {
        const chip = document.createElement('div');
        chip.className = `domain-chip ${currentDomainId === d.id ? 'active' : ''}`;
        chip.innerHTML = `<span>${d.name}</span> <span class="badge">${d.doc_count}</span>`;
        chip.onclick = () => { currentDomainId = d.id; loadDomains(); loadDocs(); };
        list.appendChild(chip);
      });
    }

    async function loadDocs() {
      const q = document.getElementById('searchInput').value;
      let url = `/api/documents?q=${encodeURIComponent(q)}`;
      if (currentDomainId) url += `&domain_id=${currentDomainId}`;
      if (favoritesOnly) url += `&favorites=1`;

      const res = await fetch(url);
      const docs = await res.json();
      const list = document.getElementById('docsList');
      document.getElementById('docsCount').textContent = `${docs.length} fichier(s)`;
      list.innerHTML = '';

      if (docs.length === 0) {
        list.innerHTML = `<div style="text-align:center; padding:32px; color:var(--text-muted);">Aucun document trouvé.</div>`;
        return;
      }

      docs.forEach(d => {
        const card = document.createElement('div');
        card.className = 'doc-card';
        card.innerHTML = `
          <div class="doc-header">
            <div>
              <div class="doc-title">📄 ${d.file_name}</div>
              <div class="doc-meta">${(d.file_size / 1024).toFixed(1)} Ko • ${d.page_count} pages</div>
            </div>
            <button class="btn btn-outline" style="padding:6px 12px; font-size:16px;" onclick="toggleFav(${d.id})">${d.is_favorite ? '⭐' : '☆'}</button>
          </div>
          <div class="doc-summary">${d.summary || 'En attente d\\'analyse...'}</div>
          <div class="tags">
            ${d.domain_name ? `<span class="tag tag-domain">📁 ${d.domain_name}</span>` : ''}
            ${d.subdomain_name ? `<span class="tag">↳ ${d.subdomain_name}</span>` : ''}
            ${d.level ? `<span class="tag tag-level">🎓 ${d.level}</span>` : ''}
            ${(d.keywords || []).map(k => `<span class="tag">#${k}</span>`).join('')}
          </div>
          <div class="doc-actions">
            <a class="btn btn-outline" href="/api/document/${d.id}/download" target="_blank">📥 Télécharger</a>
            <button class="btn btn-primary" onclick="openDoc(${d.id})">📖 Ouvrir</button>
          </div>
        `;
        list.appendChild(card);
      });
    }

    async function toggleFav(id) {
      await fetch(`/api/document/${id}/favorite`, { method: 'POST' });
      loadStats();
      loadDocs();
    }

    async function openDoc(id) {
      await fetch(`/api/document/${id}/open`, { method: 'POST' });
    }

    function handleSearch() {
      loadDocs();
    }

    function loadTab(tab) {
      favoritesOnly = (tab === 'favorites');
      document.querySelectorAll('.nav-btn').forEach((b, i) => {
        b.classList.toggle('active', (i === 0 && tab === 'all') || (i === 1 && tab === 'favorites'));
      });
      loadDocs();
    }

    async function handleFileUpload(input) {
      if (!input.files || input.files.length === 0) return;
      const file = input.files[0];
      const formData = new FormData();
      formData.append('file', file);

      alert("Envoi et analyse IA du document : " + file.name);
      try {
        const res = await fetch('/api/upload', {
          method: 'POST',
          body: formData
        });
        const data = await res.json();
        alert("Document classé avec succès !");
        loadStats();
        loadDomains();
        loadDocs();
      } catch (e) {
        alert("Erreur upload: " + e);
      }
    }

    async function triggerQuickScan() {
      const folder = "C:\\\\Users\\\\_APIAS\\\\Documents";
      alert("Scan lancé sur vos documents...");
      const res = await fetch('/api/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder: folder })
      });
      const data = await res.json();
      alert(`Terminé ! ${data.new_analyzed} analysé(s), ${data.already_indexed} déjà répertorié(s).`);
      loadStats();
      loadDomains();
      loadDocs();
    }

    function openConfigModal() { document.getElementById('configModal').style.display = 'flex'; }
    function closeConfigModal() { document.getElementById('configModal').style.display = 'none'; }

    async function testKey() {
      const key = document.getElementById('groqKeyInput').value;
      const resEl = document.getElementById('testKeyResult');
      resEl.textContent = "Test en cours...";
      const res = await fetch('/api/test-groq', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key: key })
      });
      const data = await res.json();
      resEl.textContent = data.message;
      resEl.style.color = data.valid ? "green" : "red";
    }

    async function saveKey() {
      const key = document.getElementById('groqKeyInput').value;
      await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ groq_api_key: key })
      });
      alert("Clé Groq enregistrée !");
      closeConfigModal();
    }

    initDb = async () => {
      await loadStats();
      await loadDomains();
      await loadDocs();
    };
    initDb();
  </script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

if __name__ == '__main__':
    init_db()
    print("=" * 60)
    print("  Bibliothèque PDF accessible sur :")
    print("  -> Sur votre PC : http://127.0.0.1:5000")
    print("  -> Sur votre téléphone Android (même Wi-Fi) : http://192.168.0.165:5000")
    print("=" * 60)
    app.run(host='0.0.0.0', port=5000, debug=False)
