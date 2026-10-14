import urllib.request, json, zipfile, io, os, shutil, sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Lecture sécurisée du jeton GitHub
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

class NoAuthRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Supprime l'en-tête Authorization lors de la redirection vers Azure Blob pour éviter le 401."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_req and 'Authorization' in new_req.headers:
            del new_req.headers['Authorization']
        return new_req

print('[INFO] Recherche du dernier artefact APK compile sur GitHub Actions...')

artifacts_url = f'https://api.github.com/repos/{REPO}/actions/artifacts?per_page=5'
req = urllib.request.Request(artifacts_url, headers=HEADERS)

try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        artifacts = data.get('artifacts', [])
        
    if not artifacts:
        print('[ERREUR] Aucun artefact trouve.')
        exit(1)

    latest = artifacts[0]
    artifact_id = latest['id']
    artifact_name = latest['name']
    print(f'[INFO] Artefact detecte : {artifact_name} (ID: {artifact_id})')

    download_url = f'https://api.github.com/repos/{REPO}/actions/artifacts/{artifact_id}/zip'
    print('[INFO] Telechargement de l\'APK en cours...')
    
    opener = urllib.request.build_opener(NoAuthRedirectHandler)
    dl_req = urllib.request.Request(download_url, headers=HEADERS)
    with opener.open(dl_req) as dl_resp:
        zip_data = dl_resp.read()

    out_dir = r'C:/Users/_APIAS/Downloads/Bibliotheque-APK'
    local_dir = r'Bibliotheque'
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(local_dir, exist_ok=True)

    print(f'[INFO] Archive recue ({len(zip_data)} octets). Extraction...')
    with zipfile.ZipFile(io.BytesIO(zip_data)) as z:
        z.extractall(out_dir)
        z.extractall(local_dir)

    print('\n=============================================================')
    print(' [SUCCES] NOUVEL APK DISPONIBLE ET PRET POUR INSTALLATION !')
    print('=============================================================')
    print(f'1. Dossier Telechargements : {out_dir}\\app-release.apk')
    print(f'2. Dossier Projet           : {local_dir}\\app-release.apk')
    print('Vous pouvez l\'installer directement sur votre smartphone Android.')

except Exception as e:
    print(f'[ERREUR] Erreur lors du telechargement : {e}')
