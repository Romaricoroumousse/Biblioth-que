#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test du pipeline : Extraction PDF -> Groq IA -> SQLite (FTS5)
Permet de tester immédiatement le coeur de l'application sur votre ordinateur.
"""

import os
import sys
import json
import sqlite3
import hashlib
import urllib.request
import urllib.error
from pathlib import Path
from pypdf import PdfReader

# Constantes
GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "llama-3.3-70b-versatile"
FAST_MODEL = "llama-3.1-8b-instant"
DEFAULT_PAGE_COUNT = 3
DB_PATH = "test_library.db"

def calculate_sha256(filepath: str) -> str:
    """Calcule l'empreinte SHA-256 du fichier."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def extract_pdf_pages(filepath: str, max_pages: int = DEFAULT_PAGE_COUNT):
    """Extrait le texte des max_pages premières pages."""
    try:
        reader = PdfReader(filepath)
        total_pages = len(reader.pages)
        pages_to_extract = min(total_pages, max_pages)
        
        extracted_text = []
        for i in range(pages_to_extract):
            text = reader.pages[i].extract_text() or ""
            extracted_text.append(f"--- Page {i+1} ---\n{text.strip()}")
            
        full_text = "\n\n".join(extracted_text)
        # Tronquer à 6000 caractères max
        if len(full_text) > 6000:
            full_text = full_text[:6000] + "\n[...texte tronqué pour l'analyse...]"
            
        return full_text, total_pages
    except Exception as e:
        print(f"[!] Erreur extraction PDF: {e}")
        return "", 0

def call_groq_api(api_key: str, filename: str, text: str, model: str = DEFAULT_MODEL):
    """Interroge l'API Groq en mode JSON structuré."""
    system_prompt = """Tu es un documentaliste universitaire et scientifique expert.
Analyse le nom du document et le texte des premières pages pour le cataloguer.
Tu DOIS répondre STRICTEMENT avec cet objet JSON valide :
{
  "domaine": "Domaine principal (ex: Mathématiques, Statistiques, Informatique, Économie, Finance, Droit, Médecine, Sciences Sociales...)",
  "sous_domaine": "Sous-domaine précis",
  "resume": "Résumé clair et synthétique en 2 ou 3 phrases",
  "mots_cles": ["mot1", "mot2", "mot3", "mot4", "mot5"],
  "langue": "français | anglais | autre",
  "niveau": "débutant | intermédiaire | avancé | recherche"
}
Ne fournis AUCUN texte en dehors du JSON."""

    user_content = f"Nom du fichier : \"{filename}\"\n\nExtrait des pages :\n\"\"\"\n{text}\n\"\"\""

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content}
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
        with urllib.request.urlopen(req, timeout=25) as response:
            res_data = json.loads(response.read().decode("utf-8"))
            content = res_data["choices"][0]["message"]["content"]
            return json.loads(content)
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"[!] Erreur HTTP Groq ({e.code}) : {err_msg}")
        return None
    except Exception as e:
        print(f"[!] Erreur de requête : {e}")
        return None

def init_test_db():
    """Initialise une base SQLite locale de test avec FTS5."""
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT UNIQUE,
            file_name TEXT,
            file_hash TEXT,
            file_size INTEGER,
            page_count INTEGER,
            domain TEXT,
            subdomain TEXT,
            summary TEXT,
            keywords TEXT,
            language TEXT,
            level TEXT
        )
    """)
    cur.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            file_name,
            summary,
            keywords,
            domain,
            subdomain
        )
    """)
    conn.commit()
    return conn

def search_test_db(conn, query: str):
    """Teste la recherche FTS5."""
    cur = conn.cursor()
    fts_query = f'"{query}"*'
    cur.execute("""
        SELECT d.file_name, d.domain, d.subdomain, d.summary, d.keywords
        FROM documents_fts fts
        JOIN documents d ON fts.rowid = d.id
        WHERE documents_fts MATCH ?
    """, (fts_query,))
    return cur.fetchall()

def main():
    print("=" * 60)
    print("  Bibliothèque PDF Intelligente - Test du Pipeline")
    print("=" * 60)

    # Vérification d'un fichier PDF exemple
    default_sample = r"..\QuestionnaireS4.pdf"
    if not os.path.exists(default_sample):
        default_sample = "sample.pdf"

    pdf_path = input(f"Chemin du PDF à tester [par défaut: {default_sample}] : ").strip() or default_sample
    if not os.path.exists(pdf_path):
        print(f"[!] Fichier introuvable : {pdf_path}")
        return

    print(f"\n[1] Extraction du fichier : {pdf_path}")
    file_size = os.path.getsize(pdf_path)
    file_hash = calculate_sha256(pdf_path)
    extracted_text, total_pages = extract_pdf_pages(pdf_path)

    print(f"    - Taille : {file_size / 1024:.1f} Ko")
    print(f"    - Nombre total de pages : {total_pages}")
    print(f"    - Empreinte SHA-256 : {file_hash[:16]}...")
    print(f"    - Longueur du texte extrait : {len(extracted_text)} caractères")
    print("\n--- Extrait du texte ---")
    print(extracted_text[:400] + ("..." if len(extracted_text) > 400 else ""))
    print("------------------------\n")

    api_key = os.environ.get("GROQ_API_KEY") or input("Entrez votre clé API Groq (gsk_...) [laisser vide pour simuler] : ").strip()

    if not api_key:
        print("\n[!] Aucune clé Groq fournie. Utilisation d'une réponse simulée pour le test.")
        ai_data = {
            "domaine": "Statistiques",
            "sous_domaine": "Statistique descriptive et inférentielle",
            "resume": "Questionnaire d'évaluation et exercices appliqués en statistiques pour le semestre 4.",
            "mots_cles": ["statistiques", "questionnaire", "évaluation", "inférence", "exercices"],
            "langue": "français",
            "niveau": "intermédiaire"
        }
    else:
        print(f"\n[2] Appel de l'API Groq ({DEFAULT_MODEL})...")
        ai_data = call_groq_api(api_key, os.path.basename(pdf_path), extracted_text)
        if not ai_data:
            print("[!] Échec de l'appel Groq. Vérifiez votre clé et votre connexion.")
            return

    print("\n[3] Résultat de l'analyse IA :")
    print(json.dumps(ai_data, indent=2, ensure_ascii=False))

    print("\n[4] Enregistrement en base de données SQLite locale avec FTS5...")
    conn = init_test_db()
    cur = conn.cursor()
    cur.execute("""
        INSERT OR REPLACE INTO documents (file_path, file_name, file_hash, file_size, page_count, domain, subdomain, summary, keywords, language, level)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        os.path.abspath(pdf_path),
        os.path.basename(pdf_path),
        file_hash,
        file_size,
        total_pages,
        ai_data.get("domaine"),
        ai_data.get("sous_domaine"),
        ai_data.get("resume"),
        ", ".join(ai_data.get("mots_cles", [])),
        ai_data.get("langue"),
        ai_data.get("niveau")
    ))
    doc_id = cur.lastrowid

    # Indexation FTS5
    cur.execute("""
        INSERT INTO documents_fts (rowid, file_name, summary, keywords, domain, subdomain)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        doc_id,
        os.path.basename(pdf_path),
        ai_data.get("resume", ""),
        ", ".join(ai_data.get("mots_cles", [])),
        ai_data.get("domaine", ""),
        ai_data.get("sous_domaine", "")
    ))
    conn.commit()
    print("    -> Document indexé avec succès !")

    print("\n[5] Test de la recherche intelligente FTS5 :")
    for test_term in ["statistique", "questionnaire", "évaluation"]:
        res = search_test_db(conn, test_term)
        print(f"    - Recherche '{test_term}' : {len(res)} résultat(s) trouvé(s)")
        for r in res:
            print(f"      * [{r[1]} > {r[2]}] {r[0]} : {r[3][:60]}...")

    conn.close()
    print("\n[✓] Test complet réussi avec succès !")

if __name__ == "__main__":
    main()
