$ErrorActionPreference = "Stop"

function Set-EnvDefaults {
    if (-not $env:APP_HOST) { $env:APP_HOST = "0.0.0.0" }
    if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
    if (-not $env:LLM_HOST) { $env:LLM_HOST = "127.0.0.1" }
    if (-not $env:LLM_PORT) { $env:LLM_PORT = "8081" }
    if (-not $env:LLM_MODEL) { $env:LLM_MODEL = "qwen2.5-3b-instruct-q4_k_m.gguf" }
    if (-not $env:LLM_BACKEND_URL) { $env:LLM_BACKEND_URL = "http://127.0.0.1:8081/completion" }
    if (-not $env:LLM_TOTAL_TIMEOUT) { $env:LLM_TOTAL_TIMEOUT = "180" }
    if (-not $env:LLM_CONNECT_TIMEOUT) { $env:LLM_CONNECT_TIMEOUT = "5" }
    if (-not $env:LLM_DEFAULT_N_PREDICT) { $env:LLM_DEFAULT_N_PREDICT = "96" }
}

function Load-DotEnv($Path) {
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"')
        if ($name) { $env:$name = $value }
    }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RuntimeRoot = Join-Path $RepoRoot "..\runtime"
if (-not (Test-Path $RuntimeRoot)) {
    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
}
$RuntimeDir = Resolve-Path $RuntimeRoot

$LogDir = Join-Path $RuntimeDir "logs"
$PidDir = Join-Path $RuntimeDir "pids"
New-Item -ItemType Directory -Force -Path $LogDir, $PidDir | Out-Null

$EnvFile = Join-Path $RuntimeDir ".env"
Load-DotEnv $EnvFile
Set-EnvDefaults

$RuntimePython = Join-Path $RuntimeDir "python\python.exe"
if (-not (Test-Path $RuntimePython)) {
    Write-Error "Python runtime non trovato: $RuntimePython. Installa Python portable in runtime\python\python.exe."
    exit 1
}

$VenvDir = Join-Path $RuntimeDir "venv"
$NewVenv = $false
if (-not (Test-Path $VenvDir)) {
    & $RuntimePython -m venv $VenvDir
    $NewVenv = $true
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Error "Virtualenv non valida: $VenvPython."
    exit 1
}

if ($NewVenv) {
    & $VenvPython -m pip install --upgrade pip | Out-Null
    & $VenvPython -m pip install -r (Join-Path $RepoRoot "requirements.txt")
}

$LlamaServer = Join-Path $RuntimeDir "bin\llama-server.exe"
if (-not (Test-Path $LlamaServer)) {
    Write-Error "llama-server.exe non trovato: $LlamaServer"
    exit 1
}

$ModelPath = Join-Path $RuntimeDir (Join-Path "llm\models" $env:LLM_MODEL)
if (-not (Test-Path $ModelPath)) {
    Write-Error "Modello GGUF non trovato: $ModelPath"
    exit 1
}

$Threads = $env:LLM_THREADS
if (-not $Threads) { $Threads = [Environment]::ProcessorCount }

$LlmLog = Join-Path $LogDir "llm.log"
$LlmErr = Join-Path $LogDir "llm.err.log"
$LlmPidFile = Join-Path $PidDir "llm.pid"

$llmProc = Start-Process -FilePath $LlamaServer -ArgumentList @(
    "--host", $env:LLM_HOST,
    "--port", $env:LLM_PORT,
    "-m", $ModelPath,
    "--n_ctx", "1024",
    "--n_parallel", "2",
    "--n_batch", "256",
    "--threads", $Threads
) -WorkingDirectory (Split-Path $LlamaServer) -RedirectStandardOutput $LlmLog -RedirectStandardError $LlmErr -PassThru
$llmProc.Id | Out-File -FilePath $LlmPidFile -Encoding ascii

$env:API_HOST = $env:APP_HOST
$env:API_PORT = $env:APP_PORT
$env:LLM_BACKEND_URL = "http://127.0.0.1:$($env:LLM_PORT)/completion"

$ApiLog = Join-Path $LogDir "api.log"
$ApiErr = Join-Path $LogDir "api.err.log"
$ApiPidFile = Join-Path $PidDir "api.pid"

$apiProc = Start-Process -FilePath $VenvPython -ArgumentList @("start.py") -WorkingDirectory $RepoRoot -RedirectStandardOutput $ApiLog -RedirectStandardError $ApiErr -PassThru
$apiProc.Id | Out-File -FilePath $ApiPidFile -Encoding ascii

if ($env:CLOUDFLARE_TUNNEL_TOKEN) {
    $Cloudflared = Join-Path $RuntimeDir "bin\cloudflared.exe"
    if (-not (Test-Path $Cloudflared)) {
        Write-Error "cloudflared.exe non trovato: $Cloudflared"
        exit 1
    }
    $CfLog = Join-Path $LogDir "cloudflared.log"
    $CfErr = Join-Path $LogDir "cloudflared.err.log"
    $CfPidFile = Join-Path $PidDir "cloudflared.pid"
    $cfArgs = @("tunnel", "--url", "http://localhost:$($env:APP_PORT)", "--token", $env:CLOUDFLARE_TUNNEL_TOKEN)
    if ($env:CLOUDFLARE_HOSTNAME) {
        $cfArgs += @("--hostname", $env:CLOUDFLARE_HOSTNAME)
    }
    $cfProc = Start-Process -FilePath $Cloudflared -ArgumentList $cfArgs -WorkingDirectory (Split-Path $Cloudflared) -RedirectStandardOutput $CfLog -RedirectStandardError $CfErr -PassThru
    $cfProc.Id | Out-File -FilePath $CfPidFile -Encoding ascii
}

Write-Host "TheLight24 avviato. Log in $LogDir"
