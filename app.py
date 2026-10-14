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

AI_PROVIDERS = {
    "groq": {
        "name": "Groq",
        "endpoint": "https://api.groq.com/openai/v1/chat/completions",
        "default_model": "meta-llama/llama-4-scout-17b-16e-instruct",
        "fast_model": "llama-3.1-8b-instant"
    },
    "xai": {
        "name": "xAI (Grok)",
        "endpoint": "https://api.x.ai/v1/chat/completions",
        "default_model": "grok-2-latest",
        "fast_model": "grok-beta"
    },
    "gemini": {
        "name": "Google Gemini",
        "endpoint": "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        "default_model": "gemini-2.0-flash",
        "fast_model": "gemini-1.5-flash"
    },
    "openai": {
        "name": "OpenAI",
        "endpoint": "https://api.openai.com/v1/chat/completions",
        "default_model": "gpt-4o-mini",
        "fast_model": "gpt-4o-mini"
    },
    "deepseek": {
        "name": "DeepSeek",
        "endpoint": "https://api.deepseek.com/chat/completions",
        "default_model": "deepseek-chat",
        "fast_model": "deepseek-chat"
    },
    "mistral": {
        "name": "Mistral AI",
        "endpoint": "https://api.mistral.ai/v1/chat/completions",
        "default_model": "mistral-small-latest",
        "fast_model": "mistral-small-latest"
    },
    "openrouter": {
        "name": "OpenRouter",
        "endpoint": "https://openrouter.ai/api/v1/chat/completions",
        "default_model": "google/gemini-2.0-flash-exp:free",
        "fast_model": "google/gemini-2.0-flash-exp:free"
    },
    "custom": {
        "name": "Personnalisé",
        "endpoint": "http://localhost:11434/v1/chat/completions",
        "default_model": "llama3",
        "fast_model": "llama3"
    }
}

DEFAULT_PROVIDER = "groq"
DEFAULT_MODEL = "meta-llama/llama-4-scout-17b-16e-instruct"

# ==================== CONFIGURATION ====================

def load_config():
    cfg = None
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                cfg = json.load(f)
        except Exception:
            pass
    if cfg is None:
        cfg = {
            "provider": DEFAULT_PROVIDER,
            "api_key": os.environ.get("AI_API_KEY", "") or os.environ.get("GROQ_API_KEY", ""),
            "groq_api_key": os.environ.get("GROQ_API_KEY", ""),
            "model": DEFAULT_MODEL,
            "custom_endpoint": "",
            "scan_page_count": 3,
            "privacy_accepted": False
        }
    if cfg.get("model") == "llama-3.3-70b-versatile":
        cfg["model"] = DEFAULT_MODEL
    return cfg

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


def detect_provider(key: str) -> str:
    k = key.strip()
    if k.startswith('gsk_'): return 'groq'
    if k.startswith('xai-'): return 'xai'
    if k.startswith('AIza'): return 'gemini'
    if k.startswith('sk-or-'): return 'openrouter'
    if k.startswith('sk-'): return 'openai'
    return 'groq'

def call_ai(api_key: str, filename: str, text: str, provider: str = "groq", model: str = None, custom_endpoint: str = None):
    p_info = AI_PROVIDERS.get(provider, AI_PROVIDERS["groq"])
    endpoint = custom_endpoint if (provider == "custom" and custom_endpoint) else p_info["endpoint"]
    chosen_model = model or p_info["default_model"]

    system_prompt = """Tu es un documentaliste universitaire et scientifique expert.
Analyse le nom du document et le texte des premières pages pour le cataloguer avec précision.
Tu DOIS répondre STRICTEMENT avec cet objet JSON valide :
{
  "domaine": "Domaine principal (ex: Mathématiques, Statistiques, Informatique, Économie, Finance, Droit, Médecine, Sciences Sociales, Documents & Cours...)",
  "sous_domaine": "Sous-domaine précis",
  "resume": "Résumé clair et synthétique en 2 ou 3 phrases du contenu",
  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"],
  "langue": "français | anglais | autre",
  "niveau": "débutant | intermédiaire | avancé | recherche"
}
Ne fournis AUCUN texte en dehors du JSON."""

    user_prompt = f"Nom du fichier : \"{filename}\"\n\nExtrait des premières pages :\n\"\"\"\n{text}\n\"\"\""

    payload = {
        "model": chosen_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "temperature": 0.1
    }
    if provider in ["groq", "openai"]:
        payload["response_format"] = {"type": "json_object"}

    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "SmartPdfLibrary/1.0"
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key.strip()}"

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            cleaned = content.strip()
            if cleaned.startswith("```json"):
                cleaned = cleaned[7:]
            elif cleaned.startswith("```"):
                cleaned = cleaned[3:]
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]
            return json.loads(cleaned.strip())
    except Exception as e:
        print(f"Erreur IA ({provider}): {e}")
        return None

def call_groq(api_key: str, filename: str, text: str, model: str = DEFAULT_MODEL):
    return call_ai(api_key, filename, text, provider="groq", model=model)


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
    provider = cfg.get("provider", "groq")
    api_key = request.headers.get('X-Ai-Api-Key') or request.headers.get('X-Groq-Api-Key') or cfg.get('api_key') or cfg.get('groq_api_key', '')
    if api_key and not cfg.get("provider"):
        provider = detect_provider(api_key)
    model = cfg.get("model") or AI_PROVIDERS.get(provider, {}).get("default_model", DEFAULT_MODEL)
    custom_endpoint = cfg.get("custom_endpoint", "")
    max_pages = cfg.get("scan_page_count", 3)

    text, pages = extract_pdf_info(fpath, max_pages=max_pages)

    ai_data = None
    if api_key:
        ai_data = call_ai(api_key, fname, text, provider=provider, model=model, custom_endpoint=custom_endpoint)

    if not ai_data:
        ai_data = {
            "domaine": "Documents & Cours" if ("cours" in fname.lower() or "questionnaire" in fname.lower()) else "Général",
            "sous_domaine": "Pédagogie & TP" if "tp" in fname.lower() else "Général",
            "resume": f"Document PDF de {pages} pages ({fname}). Analyse IA complète disponible dès que votre clé IA est configurée.",
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
        if 'provider' in data:
            cfg['provider'] = data['provider'].strip()
        if 'api_key' in data:
            cfg['api_key'] = data['api_key'].strip()
            cfg['groq_api_key'] = data['api_key'].strip()
        elif 'groq_api_key' in data:
            cfg['api_key'] = data['groq_api_key'].strip()
            cfg['groq_api_key'] = data['groq_api_key'].strip()
        if 'model' in data:
            cfg['model'] = data['model']
        if 'custom_endpoint' in data:
            cfg['custom_endpoint'] = data['custom_endpoint'].strip()
        if 'scan_page_count' in data:
            cfg['scan_page_count'] = int(data['scan_page_count'])
        if 'privacy_accepted' in data:
            cfg['privacy_accepted'] = bool(data['privacy_accepted'])
        save_config(cfg)
        return jsonify({"status": "ok", "config": cfg})
    else:
        cfg = load_config()
        key = cfg.get("api_key") or cfg.get("groq_api_key", "")
        masked_key = ""
        if key:
            masked_key = key[:8] + "..." + key[-4:] if len(key) > 12 else "****"
        return jsonify({
            "provider": cfg.get("provider", DEFAULT_PROVIDER),
            "has_key": bool(key),
            "masked_key": masked_key,
            "model": cfg.get("model", DEFAULT_MODEL),
            "custom_endpoint": cfg.get("custom_endpoint", ""),
            "scan_page_count": cfg.get("scan_page_count", 3),
            "privacy_accepted": cfg.get("privacy_accepted", False),
            "available_providers": [
                {"id": k, "name": v["name"], "default_model": v["default_model"]}
                for k, v in AI_PROVIDERS.items()
            ]
        })

@app.route('/api/test-ai', methods=['POST'])
@app.route('/api/test-groq', methods=['POST'])
def api_test_ai():
    data = request.json or {}
    key = data.get("key") or data.get("api_key") or load_config().get("api_key") or load_config().get("groq_api_key", "")
    provider = data.get("provider") or load_config().get("provider", "groq")
    if key and not data.get("provider"):
        provider = detect_provider(key)

    p_info = AI_PROVIDERS.get(provider, AI_PROVIDERS["groq"])
    endpoint = data.get("custom_endpoint") or p_info["endpoint"]
    model = data.get("model") or p_info["fast_model"]

    if not key and provider != "custom":
        return jsonify({"valid": False, "message": "Veuillez renseigner une clé API"}), 400

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "ping"}],
        "max_tokens": 10
    }
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "User-Agent": "SmartPdfLibrary/1.0"
    }
    if key:
        headers["Authorization"] = f"Bearer {key.strip()}"

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return jsonify({
                "valid": resp.status == 200,
                "message": f"Connexion {p_info['name']} réussie !",
                "provider": provider
            })
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return jsonify({"valid": False, "message": "Clé API non reconnue (401)", "code": 401}), 400
        elif e.code == 403:
            return jsonify({"valid": False, "message": "Accès refusé ou région non prise en charge (403)", "code": 403}), 400
        elif e.code == 429:
            return jsonify({"valid": False, "message": "Quota dépassé (429)", "code": 429}), 400
        return jsonify({"valid": False, "message": f"Erreur API ({e.code})", "code": e.code}), 400
    except Exception as e:
        return jsonify({"valid": False, "message": f"Erreur de connexion : {str(e)}"}), 400

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
      <div style="width:36px; height:36px; border-radius:10px; background:linear-gradient(135deg,#1e3a8a,#2563eb,#0d9488); display:flex; align-items:center; justify-content:center; color:white; font-size:18px; box-shadow:0 4px 10px rgba(30,58,138,0.3); margin-right:8px;">
        📖
      </div>
      <div>
        Bibliothèque PDF
        <div style="font-size:10px; color:#0d9488; font-weight:700; letter-spacing:0.5px;">MULTI-IA</div>
      </div>
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
      Clé IA & Fournisseur
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
      <h3 style="margin-bottom:8px;">Configuration IA (Multi-Fournisseurs)</h3>
      <p style="font-size:12.5px; color:var(--text-muted); margin-bottom:14px;">
        Supporte Groq, Google Gemini, OpenAI, DeepSeek, Mistral, OpenRouter ou serveur local. L'application reste utilisable même sans clé.
      </p>

      <label style="font-size:12.5px; font-weight:600;">Fournisseur d'IA :</label>
      <select id="aiProviderSelect" style="width:100%; padding:9px; margin:6px 0 12px; border:1px solid var(--border); border-radius:8px;" onchange="onProviderSelectChanged(this.value)">
        <option value="groq">Groq (Gratuit & Ultra-rapide)</option>
        <option value="xai">xAI (Grok)</option>
        <option value="gemini">Google Gemini (Gratuit & Très précis)</option>
        <option value="openai">OpenAI (ChatGPT)</option>
        <option value="deepseek">DeepSeek</option>
        <option value="mistral">Mistral AI</option>
        <option value="openrouter">OpenRouter (Tous modèles)</option>
        <option value="custom">Autre / Personnalisé (OpenAI compatible)</option>
      </select>

      <label style="font-size:12.5px; font-weight:600;">Clé API :</label>
      <input type="password" id="aiKeyInput" style="width:100%; padding:9px; margin:6px 0 12px; border:1px solid var(--border); border-radius:8px;" placeholder="Collez votre clé API" oninput="autoDetectProvider(this.value)">

      <label style="font-size:12.5px; font-weight:600;">Modèle IA (modifiable librement) :</label>
      <input type="text" id="aiModelInput" style="width:100%; padding:9px; margin:6px 0 14px; border:1px solid var(--border); border-radius:8px;" placeholder="ex: meta-llama/llama-4-scout-17b-16e-instruct">

      <div id="testKeyResult" style="font-size:12.5px; margin-bottom:14px;"></div>
      <div style="display:flex; justify-content:space-between; flex-wrap:wrap; gap:8px;">
        <button class="btn btn-outline" onclick="testKey()">Tester la clé</button>
        <div style="display:flex; gap:8px;">
          <button class="btn btn-outline" onclick="closeConfigModal()">Fermer</button>
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

    const defaultModelsByProvider = {
      groq: "meta-llama/llama-4-scout-17b-16e-instruct",
      xai: "grok-2-latest",
      gemini: "gemini-2.0-flash",
      openai: "gpt-4o-mini",
      deepseek: "deepseek-chat",
      mistral: "mistral-small-latest",
      openrouter: "google/gemini-2.0-flash-exp:free",
      custom: "llama3"
    };

    function onProviderSelectChanged(prov) {
      const modelInput = document.getElementById('aiModelInput');
      if (defaultModelsByProvider[prov]) {
        modelInput.value = defaultModelsByProvider[prov];
      }
    }

    function autoDetectProvider(val) {
      const v = val.trim();
      const sel = document.getElementById('aiProviderSelect');
      let changed = false;
      if (v.startsWith('gsk_')) { sel.value = 'groq'; changed = true; }
      else if (v.startsWith('xai-')) { sel.value = 'xai'; changed = true; }
      else if (v.startsWith('AIza')) { sel.value = 'gemini'; changed = true; }
      else if (v.startsWith('sk-or-')) { sel.value = 'openrouter'; changed = true; }
      else if (v.startsWith('sk-')) { sel.value = 'openai'; changed = true; }
      if (changed) {
        onProviderSelectChanged(sel.value);
      }
    }

    async function openConfigModal() {
      document.getElementById('configModal').style.display = 'flex';
      const res = await fetch('/api/config');
      const data = await res.json();
      if (data.provider) document.getElementById('aiProviderSelect').value = data.provider;
      if (data.model) {
        document.getElementById('aiModelInput').value = data.model;
      } else if (data.provider && defaultModelsByProvider[data.provider]) {
        document.getElementById('aiModelInput').value = defaultModelsByProvider[data.provider];
      }
    }
    function closeConfigModal() { document.getElementById('configModal').style.display = 'none'; }

    async function testKey() {
      const key = document.getElementById('aiKeyInput').value;
      const provider = document.getElementById('aiProviderSelect').value;
      const model = document.getElementById('aiModelInput').value.trim();
      const resEl = document.getElementById('testKeyResult');
      resEl.textContent = "Test en cours auprès du fournisseur IA...";
      resEl.style.color = "#3b82f6";

      const res = await fetch('/api/test-ai', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key: key, provider: provider, model: model })
      });
      const data = await res.json();
      resEl.textContent = data.message;
      resEl.style.color = data.valid ? "green" : "red";
    }

    async function saveKey() {
      const key = document.getElementById('aiKeyInput').value;
      const provider = document.getElementById('aiProviderSelect').value;
      const model = document.getElementById('aiModelInput').value.trim();
      await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ api_key: key, provider: provider, model: model })
      });
      alert("Configuration IA enregistrée avec succès !");
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
