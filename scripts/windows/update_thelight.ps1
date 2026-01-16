$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RuntimeRoot = Join-Path $RepoRoot "..\runtime"
if (-not (Test-Path $RuntimeRoot)) {
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
}
$RuntimeDir = Resolve-Path $RuntimeRoot

Write-Host "Aggiorno repository in $RepoRoot"
& git -C $RepoRoot pull

$RuntimePython = Join-Path $RuntimeDir "python\python.exe"
if (-not (Test-Path $RuntimePython)) {
    Write-Error "Python runtime non trovato: $RuntimePython. Installa Python portable in runtime\python\python.exe."
    exit 1
}

$VenvDir = Join-Path $RuntimeDir "venv"
if (-not (Test-Path $VenvDir)) {
    & $RuntimePython -m venv $VenvDir
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Error "Virtualenv non valida: $VenvPython."
    exit 1
}

& $VenvPython -m pip install --upgrade pip | Out-Null
& $VenvPython -m pip install -r (Join-Path $RepoRoot "requirements.txt")

Write-Host "Aggiornamento completato."
