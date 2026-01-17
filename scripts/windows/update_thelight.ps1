$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RuntimeRoot = Join-Path $RepoRoot "..\runtime"
if (-not (Test-Path $RuntimeRoot)) {
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
}
$RuntimeDir = Resolve-Path $RuntimeRoot

Write-Host "Repository root: $RepoRoot"
Write-Host "Runtime dir: $RuntimeDir"
Write-Host "Cambio directory: $RepoRoot"
Set-Location $RepoRoot

Write-Host "Verifico stato repository..."
$Status = & git -C $RepoRoot status --porcelain
$DidStash = $false
if ($Status) {
    Write-Host "Repository dirty: eseguo stash automatico."
    Write-Host "Comando: git -C $RepoRoot stash push -u -m \"auto-stash before pull\""
    & git -C $RepoRoot stash push -u -m "auto-stash before pull" | Out-Null
    $DidStash = $true
}

Write-Host "Comando: git -C $RepoRoot pull --rebase"
& git -C $RepoRoot pull --rebase

if ($DidStash) {
    Write-Host "Ripristino stash: git -C $RepoRoot stash pop"
    & git -C $RepoRoot stash pop
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Conflitti durante lo stash pop. Risolvi manualmente e ripeti se necessario."
    }
}

$RuntimePython = Join-Path $RuntimeDir "python\python.exe"
Write-Host "Runtime python: $RuntimePython"
if (-not (Test-Path $RuntimePython)) {
    Write-Error "Python runtime non trovato: $RuntimePython. Installa Python portable in runtime\python\python.exe."
    exit 1
}

Write-Host "Verifico supporto venv/ensurepip: $RuntimePython"
& $RuntimePython -c "import venv; import ensurepip; print('OK')" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Questo python runtime è embeddable/minimal e non include venv. Usa WinPython 3.10 x64 (portable) e metti python.exe in runtime\python\python.exe"
    exit 1
}

$VenvDir = Join-Path $RuntimeDir "venv"
if (-not (Test-Path $VenvDir)) {
    Write-Host "Creo venv: $VenvDir"
    Write-Host "Comando: $RuntimePython -m venv $VenvDir"
    & $RuntimePython -m venv $VenvDir
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
Write-Host "Venv python: $VenvPython"
if (-not (Test-Path $VenvPython)) {
    Write-Error "Virtualenv non valida: $VenvPython."
    exit 1
}

Write-Host "Verifico pip nella venv..."
& $VenvPython -m pip --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "pip mancante: eseguo ensurepip --upgrade"
    Write-Host "Comando: $VenvPython -m ensurepip --upgrade"
    & $VenvPython -m ensurepip --upgrade
}

Write-Host "Aggiorno pip..."
Write-Host "Comando: $VenvPython -m pip install --upgrade pip"
& $VenvPython -m pip install --upgrade pip | Out-Null

Write-Host "Installo requirements..."
Write-Host "Comando: $VenvPython -m pip install -r $(Join-Path $RepoRoot "requirements.txt")"
& $VenvPython -m pip install -r (Join-Path $RepoRoot "requirements.txt")

Write-Host "Aggiornamento completato."
