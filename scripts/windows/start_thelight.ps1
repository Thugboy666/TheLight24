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
    if (-not $env:KOBOLDCPP_EXE) { $env:KOBOLDCPP_EXE = (Join-Path $RuntimeDir "bin\koboldcpp.exe") }
    if (-not $env:KOBOLDCPP_HOST) { $env:KOBOLDCPP_HOST = "127.0.0.1" }
    if (-not $env:KOBOLDCPP_PORT) { $env:KOBOLDCPP_PORT = "8081" }
    if ($null -eq $env:KOBOLDCPP_ARGS) { $env:KOBOLDCPP_ARGS = "" }
    if (-not $env:OPENAI_BASE_URL) { $env:OPENAI_BASE_URL = "http://127.0.0.1:8081/v1" }
    if (-not $env:OPENAI_MODEL) { $env:OPENAI_MODEL = "local-model" }
    if (-not $env:LLM_PROVIDER) {
        if (Test-Path $env:KOBOLDCPP_EXE) {
            $env:LLM_PROVIDER = "koboldcpp"
        } else {
            $env:LLM_PROVIDER = "llamacpp"
        }
    }
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
$KoboldExe = $env:KOBOLDCPP_EXE
$KoboldHost = $env:KOBOLDCPP_HOST
$KoboldPort = $env:KOBOLDCPP_PORT
$KoboldArgs = $env:KOBOLDCPP_ARGS
$ModelPath = Join-Path $RuntimeDir (Join-Path "llm\models" $env:LLM_MODEL)
if (-not $env:LLM_PROVIDER) { $env:LLM_PROVIDER = "llamacpp" }
$LlmProvider = $env:LLM_PROVIDER.ToLower()

Write-Report ("Get-Location: {0}" -f (Get-Location))
Write-Report ("RepoRoot: {0}" -f $RepoRoot)
Write-Report ("RuntimeDir: {0}" -f $RuntimeDir)
Write-Report ("llama-server.exe: {0}" -f $LlamaServer)
Write-Report ("koboldcpp.exe: {0}" -f $KoboldExe)
Write-Report ("cloudflared.exe: {0}" -f (Join-Path $RuntimeDir "bin\cloudflared.exe"))
Write-Report ("Model GGUF: {0}" -f $ModelPath)
Write-Report ("LLM_PROVIDER: {0}" -f $LlmProvider)
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

$LlmStartAllowed = $true
if (-not (Test-Path $ModelPath)) {
    Write-Report "Modello GGUF non trovato: $ModelPath"
    Write-Host "Modello GGUF non trovato: $ModelPath"
    $LlmStartAllowed = $false
}

$Threads = $env:LLM_THREADS
if (-not $Threads) { $Threads = [Environment]::ProcessorCount }

$LlmOut = Join-Path $LogDir "llm_out.log"
$LlmErr = Join-Path $LogDir "llm_err.log"
if ($LlmProvider -eq "koboldcpp") {
    $LlmOut = Join-Path $LogDir "kobold_out.log"
    $LlmErr = Join-Path $LogDir "kobold_err.log"
}
$LlmPidFile = Join-Path $PidDir "llm.pid"
New-Item -ItemType File -Force -Path $LlmOut, $LlmErr | Out-Null

$LlmExe = $null
$LlmBinDir = $null
$LlmHost = $env:LLM_HOST
$LlmPort = $env:LLM_PORT
$SafeModeApplied = $false
$llmProc = $null

if ($LlmProvider -eq "koboldcpp") {
    $LlmExe = $KoboldExe
    $LlmHost = $KoboldHost
    $LlmPort = $KoboldPort
    if (-not (Test-Path $LlmExe)) {
        Write-Report "koboldcpp.exe non trovato: $LlmExe"
        Write-Host "koboldcpp.exe non trovato: $LlmExe"
        $LlmStartAllowed = $false
    }
    if ($LlmStartAllowed) {
        $LlmBinDir = Split-Path $LlmExe
        $ArgumentString = "--model `"$ModelPath`" --host $LlmHost --port $LlmPort --contextsize 1024"
        if ($KoboldArgs) {
            $ArgumentString = "$ArgumentString $KoboldArgs"
        }
        $llmProc = Start-Process -FilePath $LlmExe -ArgumentList $ArgumentString -WorkingDirectory $LlmBinDir -RedirectStandardOutput $LlmOut -RedirectStandardError $LlmErr -WindowStyle Hidden -PassThru
    }
} else {
    $LlmProvider = "llamacpp"
    $LlmExe = $LlamaServer
    $LlmBinDir = Join-Path $RuntimeDir "bin"
    if (-not (Test-Path $LlmExe)) {
        Write-Report "llama-server.exe non trovato: $LlmExe"
        Write-Host "llama-server.exe non trovato: $LlmExe"
        $LlmStartAllowed = $false
    }
    if ($LlmStartAllowed) {
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
            "--host", $LlmHost,
            "--port", $LlmPort,
            "--model", $ModelPath,
            "--ctx-size", "1024",
            "--n-parallel", "2"
        )
        $llmProc = Start-Process -FilePath $LlmExe -ArgumentList $Args -WorkingDirectory $LlmBinDir -RedirectStandardOutput $LlmOut -RedirectStandardError $LlmErr -WindowStyle Hidden -PassThru
    }
}

if ($llmProc) {
    $llmProc.Id | Out-File -FilePath $LlmPidFile -Encoding ascii
}

$LlmRequired = $true
if ($env:LLM_REQUIRED -and $env:LLM_REQUIRED -eq "0") {
    $LlmRequired = $false
}

$LlmProcessName = "llama-server"
if ($LlmProvider -eq "koboldcpp") {
    $LlmProcessName = "koboldcpp"
}

$llmReady = $false
Write-Report "Diagnostica LLM dopo avvio:"
Write-Report ("netstat :{0}:" -f $LlmPort)
$netstatAfterStart = cmd /c ("netstat -ano | findstr :{0}" -f $LlmPort)
if ($netstatAfterStart) {
    $netstatAfterStart | ForEach-Object { Write-Report ("  {0}" -f $_) }
} else {
    Write-Report "  (none)"
}
Write-Report ("Get-Process {0}:" -f $LlmProcessName)
Get-Process $LlmProcessName -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Report ("  Id={0} CPU={1} WS={2}" -f $_.Id, $_.CPU, $_.WorkingSet64)
}

if ($LlmStartAllowed) {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ($llmProc) {
            $llmProc.Refresh()
            if ($llmProc.HasExited) {
                break
            }
        }
        $listening = Get-NetTCPConnection -LocalPort $LlmPort -State Listen -ErrorAction SilentlyContinue
        if ($listening) {
            $llmReady = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
}

if (-not $llmReady) {
    if ($llmProc) {
        $llmProc.Refresh()
    }
    $exitCode = $null
    if ($llmProc -and $llmProc.HasExited) {
        $exitCode = $llmProc.ExitCode
        Write-Report ("LLM process died before opening port {0}. ExitCode={1}" -f $LlmPort, $exitCode)
        Write-Host ("LLM process died before opening port {0}. ExitCode={1}" -f $LlmPort, $exitCode)
    } elseif (-not $LlmStartAllowed) {
        Write-Report "LLM not started (missing exe or model)."
        Write-Host "LLM not started (missing exe or model)."
    } else {
        Write-Report ("LLM not listening on port {0} after 30s (process may be dead or stuck)." -f $LlmPort)
        Write-Host ("LLM not listening on port {0} after 30s (process may be dead or stuck)." -f $LlmPort)
    }
    if ($LlmProvider -eq "llamacpp") {
        Write-Host "Suggerimento: installa Microsoft Visual C++ Redistributable 2015-2022 (x64) se non presente."
    }
    Write-Report ("netstat :{0} (post-wait):" -f $LlmPort)
    $netstatAfter = cmd /c ("netstat -ano | findstr :{0}" -f $LlmPort)
    if ($netstatAfter) {
        $netstatAfter | ForEach-Object { Write-Report ("  {0}" -f $_) }
    } else {
        Write-Report "  (none)"
    }
    Write-Report ("Get-Process {0} (post-wait):" -f $LlmProcessName)
    Get-Process $LlmProcessName -ErrorAction SilentlyContinue | ForEach-Object {
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
        Write-Host "LLM_REQUIRED=1 ma il backend non è pronto: avvio API comunque in modalità degradada."
        Write-Report "LLM_REQUIRED=1 ma il backend non è pronto: avvio API comunque in modalità degradata."
    }
}

$llmProc.Refresh()
if ($llmReady -and $SafeModeApplied) {
    Write-Report "WARNING: LLM avviato con LLM_SAFE_MODE=1; ggml-rpc.dll disabilitata."
}

$env:API_HOST = $env:APP_HOST
$env:API_PORT = $env:APP_PORT
$env:LLM_MODE = "llamacpp_completion"
$env:LLM_BACKEND_URL = ("http://{0}:{1}/completion" -f $env:LLM_HOST, $env:LLM_PORT)
$env:OPENAI_BASE_URL = ("http://{0}:{1}/v1" -f $KoboldHost, $KoboldPort)
$env:LLM_PROVIDER = $LlmProvider
$env:LLM_CONNECT_TIMEOUT = "2"
$env:LLM_TOTAL_TIMEOUT = "30"
$env:LLM_DEFAULT_N_PREDICT = "96"
if (-not $llmReady -and -not $LlmRequired) {
    $env:LLM_DISABLED = "1"
}
if ($LlmProvider -eq "koboldcpp") {
    $env:LLM_MODE = "openai_chat"
    if (-not $env:OPENAI_BASE_URL) {
        $env:OPENAI_BASE_URL = ("http://{0}:{1}/v1" -f $KoboldHost, $KoboldPort)
    }
} else {
    $env:LLM_MODE = "llamacpp_completion"
    $env:LLM_BACKEND_URL = ("http://{0}:{1}/completion" -f $env:LLM_HOST, $env:LLM_PORT)
}
if (-not $llmReady) {
    $env:LLM_DISABLED = "1"
    $env:LLM_BACKEND_URL = ""
    $env:OPENAI_BASE_URL = ""
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

Write-Host "=== DIAGNOSTICA ==="
Write-Report "=== DIAGNOSTICA ==="
function Write-ExeInfo {
    param([string]$Label, [string]$Path)
    if (Test-Path $Path) {
        $item = Get-Item $Path
        Write-Report ("{0}: {1} size={2} lastwrite={3}" -f $Label, $item.FullName, $item.Length, $item.LastWriteTime)
    } else {
        Write-Report ("{0}: missing ({1})" -f $Label, $Path)
    }
}
Write-ExeInfo -Label "llama-server.exe" -Path $LlamaServer
Write-ExeInfo -Label "koboldcpp.exe" -Path $KoboldExe

$net8080 = cmd /c "netstat -ano | findstr :8080"
Write-Report "netstat :8080:"
if ($net8080) { $net8080 | ForEach-Object { Write-Report ("  {0}" -f $_) } } else { Write-Report "  (none)" }
$net8081 = cmd /c "netstat -ano | findstr :8081"
Write-Report "netstat :8081:"
if ($net8081) { $net8081 | ForEach-Object { Write-Report ("  {0}" -f $_) } } else { Write-Report "  (none)" }

if (Test-Path $LlmErr) {
    Write-Report "---- LLM stderr (last 50 lines) ----"
    Get-Content -Path $LlmErr -Tail 50 | ForEach-Object { Write-Report $_ }
}
if (Test-Path $LlmOut) {
    Write-Report "---- LLM stdout (last 50 lines) ----"
    Get-Content -Path $LlmOut -Tail 50 | ForEach-Object { Write-Report $_ }
}

Start-Sleep -Seconds 2
$healthUrl = "http://127.0.0.1:$($env:APP_PORT)/api/llm/health"
$chatUrl = "http://127.0.0.1:$($env:APP_PORT)/api/llm/chat"
Write-Report ("curl {0}" -f $healthUrl)
$healthResponse = & curl.exe -s $healthUrl
if ($healthResponse) { Write-Report $healthResponse }
Write-Report ("curl {0} (ping)" -f $chatUrl)
$chatPayload = '{"prompt":"ping","n_predict":32}'
$chatResponse = & curl.exe -s -H "Content-Type: application/json" -d $chatPayload $chatUrl
if ($chatResponse) { Write-Report $chatResponse }

Write-Host "TheLight24 avviato. Log in $LogDir"
