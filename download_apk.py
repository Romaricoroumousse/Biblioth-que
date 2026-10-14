import urllib.request, json, zipfile, io, os, shutil

# Lecture sécurisée du jeton GitHub (depuis l'environnement ou github_token.txt local ignoré par git)
TOKEN = os.environ.get('GITHUB_TOKEN', '')
token_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'github_token.txt')
if not TOKEN and os.path.exists(token_file):
    try:
        with open(token_file, 'r', encoding='utf-8') as f:
            TOKEN = f.read().strip()
    except Exception:
        pass

REPO = 'Romaricoroumousse/Biblioth-que'
HEADERS = {
    'Authorization': f'Bearer {TOKEN}',
    'User-Agent': 'Mozilla/5.0',
    'Accept': 'application/vnd.github.v3+json'
}

print('🔍 Recherche du dernier artefact APK compilé sur GitHub Actions...')

# 1. Obtenir les artefacts récents
artifacts_url = f'https://api.github.com/repos/{REPO}/actions/artifacts?per_page=5'
req = urllib.request.Request(artifacts_url, headers=HEADERS)

try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        artifacts = data.get('artifacts', [])
        
    if not artifacts:
        print('❌ Aucun artefact trouvé.')
        exit(1)

    # Prendre le premier (le plus récent)
    latest = artifacts[0]
    artifact_id = latest['id']
    artifact_name = latest['name']
    print(f'📦 Artefact détecté : {artifact_name} (ID: {artifact_id})')

    download_url = latest['archive_download_url']
    print('⬇️ Téléchargement en cours...')
    dl_req = urllib.request.Request(download_url, headers=HEADERS)
    with urllib.request.urlopen(dl_req) as dl_resp:
        zip_data = dl_resp.read()

    out_dir = r'C:/Users/_APIAS/Downloads/Bibliotheque-APK'
    local_dir = r'Bibliotheque'
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(local_dir, exist_ok=True)

    print('📂 Extraction du fichier APK...')
    with zipfile.ZipFile(io.BytesIO(zip_data)) as z:
        z.extractall(out_dir)
        z.extractall(local_dir)

    print(f'✅ SUCCÈS ! APK disponible dans :')
    print(f'  -> {out_dir}')
    print(f'  -> {local_dir}/app-release.apk')

except Exception as e:
    print(f'❌ Erreur lors du téléchargement : {e}')
