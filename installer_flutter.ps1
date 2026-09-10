<#
.SYNOPSIS
Script d'aide à l'installation locale de Flutter et compilation de l'APK sur Windows.
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Compilation Locale de l'APK Flutter pour Android" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Vérification de Flutter
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutterCmd) {
    Write-Host "[!] Flutter n'est pas encore installé dans votre PATH Windows." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Pour installer Flutter rapidement :" -ForegroundColor White
    Write-Host "1. Téléchargez Flutter SDK (archive zip) :" -ForegroundColor Gray
    Write-Host "   https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.19.6-stable.zip" -ForegroundColor Gray
    Write-Host "2. Décompressez-le dans : C:\src\flutter" -ForegroundColor Gray
    Write-Host "3. Ajoutez 'C:\src\flutter\bin' à vos variables d'environnement PATH." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Astuce : Vous pouvez aussi utiliser GitHub Actions (déjà configuré dans .github/workflows) pour compiler votre APK gratuitement dans le cloud sans rien installer !" -ForegroundColor Green
    exit 0
}

Write-Host "[✓] Flutter détecté : $($flutterCmd.Source)" -ForegroundColor Green

# 2. Récupération des dépendances
Write-Host "`n[1/2] Téléchargement des dépendances Flutter..." -ForegroundColor Yellow
flutter pub get

# 3. Compilation de l'APK
Write-Host "`n[2/2] Compilation de l'APK Release pour Android..." -ForegroundColor Yellow
flutter build apk --release

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    Write-Host "`n[✓] SUCCÈS ! Votre fichier APK est prêt :" -ForegroundColor Green
    Write-Host (Resolve-Path $apkPath) -ForegroundColor Cyan
    Write-Host "Vous pouvez le transférer par câble USB ou WhatsApp sur votre téléphone pour l'installer !" -ForegroundColor White
} else {
    Write-Host "[!] La compilation a échoué. Vérifiez vos outils Android SDK." -ForegroundColor Red
}
