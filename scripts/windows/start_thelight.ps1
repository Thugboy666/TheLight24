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
	if ($name) { Set-Item -Path ("Env:{0}" -f $name) -Value $value }
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

$StartReport = Join-Path $LogDir "start_report.txt"
Set-Content -Path $StartReport -Value ("Start report - {0}" -f (Get-Date -Format "s"))

function Write-Report {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $StartReport -Value $Message
}

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
$ModelPath = Join-Path $RuntimeDir (Join-Path "llm\models" $env:LLM_MODEL)

Write-Report ("Get-Location: {0}" -f (Get-Location))
Write-Report ("RepoRoot: {0}" -f $RepoRoot)
Write-Report ("RuntimeDir: {0}" -f $RuntimeDir)
Write-Report ("llama-server.exe: {0}" -f $LlamaServer)
Write-Report ("cloudflared.exe: {0}" -f (Join-Path $RuntimeDir "bin\cloudflared.exe"))
Write-Report ("Model GGUF: {0}" -f $ModelPath)
Write-Report "runtime\\bin contents:"
if (Test-Path (Join-Path $RuntimeDir "bin")) {
    Get-ChildItem -Path (Join-Path $RuntimeDir "bin") -Name | ForEach-Object {
        Write-Report ("  - {0}" -f $_)
    }
} else {
    Write-Report "  (runtime\\bin missing)"
}
Write-Report "runtime\\llm\\models contents:"
if (Test-Path (Join-Path $RuntimeDir "llm\\models")) {
    Get-ChildItem -Path (Join-Path $RuntimeDir "llm\\models") -Name | ForEach-Object {
        Write-Report ("  - {0}" -f $_)
    }
} else {
    Write-Report "  (runtime\\llm\\models missing)"
}
$netstatOutput = cmd /c "netstat -ano | findstr :8081"
Write-Report "netstat :8081:"
if ($netstatOutput) {
    $netstatOutput | ForEach-Object { Write-Report ("  {0}" -f $_) }
} else {
    Write-Report "  (none)"
}
$llamaVersion = "not supported"
try {
    $llamaVersionOutput = & $LlamaServer --version 2>$null
    if ($llamaVersionOutput) {
        $llamaVersion = ($llamaVersionOutput | Select-Object -First 1)
    }
} catch {
    $llamaVersion = "not supported"
}
Write-Report ("llama-server version: {0}" -f $llamaVersion)

if (-not (Test-Path $LlamaServer)) {
    Write-Error "llama-server.exe non trovato: $LlamaServer"
    exit 1
}

if (-not (Test-Path $ModelPath)) {
    Write-Error "Modello GGUF non trovato: $ModelPath"
    exit 1
}

$Threads = $env:LLM_THREADS
if (-not $Threads) { $Threads = [Environment]::ProcessorCount }

$LlmOut = Join-Path $LogDir "llm_out.log"
$LlmErr = Join-Path $LogDir "llm_err.log"
$LlmPidFile = Join-Path $PidDir "llm.pid"
New-Item -ItemType File -Force -Path $LlmOut, $LlmErr | Out-Null

$LlmExe = Join-Path $RuntimeDir "bin\llama-server.exe"
$LlmBinDir = Join-Path $RuntimeDir "bin"
$SafeModeApplied = $false
if ($env:LLM_SAFE_MODE -and $env:LLM_SAFE_MODE -eq "1") {
    $RpcDll = Join-Path $LlmBinDir "ggml-rpc.dll"
    $RpcDllDisabled = Join-Path $LlmBinDir "ggml-rpc.dll.disabled"
    if (Test-Path $RpcDll) {
        Move-Item -Path $RpcDll -Destination $RpcDllDisabled -Force
        $SafeModeApplied = $true
        Write-Report "LLM_SAFE_MODE=1: ggml-rpc.dll disabilitata (rinominata in ggml-rpc.dll.disabled)."
    } else {
        Write-Report "LLM_SAFE_MODE=1: ggml-rpc.dll non trovata; nessuna rinomina effettuata."
    }
}
$env:PATH = "$LlmBinDir;$env:PATH"
$Args = @(
    "--host", "127.0.0.1",
    "--port", "8081",
    "--model", $ModelPath,
    "--ctx-size", "1024",
    "--n-parallel", "2"
)

$llmProc = Start-Process -FilePath $LlmExe -ArgumentList $Args -WorkingDirectory $LlmBinDir -RedirectStandardOutput $LlmOut -RedirectStandardError $LlmErr -WindowStyle Hidden -PassThru
$llmProc.Id | Out-File -FilePath $LlmPidFile -Encoding ascii

$LlmRequired = $true
if ($env:LLM_REQUIRED -and $env:LLM_REQUIRED -eq "0") {
    $LlmRequired = $false
}

$llmReady = $false
Write-Report "Diagnostica LLM dopo avvio:"
Write-Report "netstat :8081:"
$netstatAfterStart = cmd /c "netstat -ano | findstr :8081"
if ($netstatAfterStart) {
    $netstatAfterStart | ForEach-Object { Write-Report ("  {0}" -f $_) }
} else {
    Write-Report "  (none)"
}
Write-Report "Get-Process llama-server:"
Get-Process llama-server -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Report ("  Id={0} CPU={1} WS={2}" -f $_.Id, $_.CPU, $_.WorkingSet64)
}

$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    $llmProc.Refresh()
    if ($llmProc.HasExited) {
        break
    }
    $listening = Get-NetTCPConnection -LocalPort 8081 -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
        $llmReady = $true
        break
    }
    Start-Sleep -Milliseconds 250
}

if (-not $llmReady) {
    $llmProc.Refresh()
    $exitCode = $null
    if ($llmProc.HasExited) {
        $exitCode = $llmProc.ExitCode
        Write-Report ("LLM process died before opening port 8081. ExitCode={0}" -f $exitCode)
        Write-Host ("LLM process died before opening port 8081. ExitCode={0}" -f $exitCode)
    } else {
        Write-Report "LLM not listening on port 8081 after 20s (process may be dead or stuck)."
        Write-Host "LLM not listening on port 8081 after 20s (process may be dead or stuck)."
    }
    Write-Host "Suggerimento: installa Microsoft Visual C++ Redistributable 2015-2022 (x64) se non presente."
    Write-Report "netstat :8081 (post-wait):"
    $netstatAfter = cmd /c "netstat -ano | findstr :8081"
    if ($netstatAfter) {
        $netstatAfter | ForEach-Object { Write-Report ("  {0}" -f $_) }
    } else {
        Write-Report "  (none)"
    }
    Write-Report "Get-Process llama-server (post-wait):"
    Get-Process llama-server -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Report ("  Id={0} CPU={1} WS={2}" -f $_.Id, $_.CPU, $_.WorkingSet64)
    }
    if ($llmProc -and -not $llmProc.HasExited) {
        Write-Report ("LLM process running: {0}" -f $llmProc.Id)
    } elseif ($llmProc -and $llmProc.HasExited) {
        Write-Report ("LLM process exited with code {0}" -f $llmProc.ExitCode)
    }
    if (Test-Path $LlmErr) {
        Write-Host "---- llm_err.log (last 120 lines) ----"
        Get-Content -Path $LlmErr -Tail 120 | ForEach-Object { Write-Host $_ }
    }
    if (Test-Path $LlmOut) {
        Write-Host "---- llm_out.log (last 120 lines) ----"
        Get-Content -Path $LlmOut -Tail 120 | ForEach-Object { Write-Host $_ }
    }

    if ($LlmRequired) {
        exit 1
    }
}

$llmProc.Refresh()
if ($llmReady -and $SafeModeApplied) {
    Write-Report "WARNING: LLM avviato con LLM_SAFE_MODE=1; ggml-rpc.dll disabilitata."
}

$env:API_HOST = $env:APP_HOST
$env:API_PORT = $env:APP_PORT
$env:LLM_BACKEND_URL = "http://127.0.0.1:8081/completion"
$env:LLM_CONNECT_TIMEOUT = "2"
$env:LLM_TOTAL_TIMEOUT = "30"
$env:LLM_DEFAULT_N_PREDICT = "96"
if (-not $llmReady -and -not $LlmRequired) {
    $env:LLM_DISABLED = "1"
}

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
