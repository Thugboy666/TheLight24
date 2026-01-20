$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RuntimeRoot = Join-Path $RepoRoot "..\runtime"
if (-not (Test-Path $RuntimeRoot)) {
    Write-Host "Runtime non trovato: $RuntimeRoot"
    exit 0
}
$RuntimeDir = Resolve-Path $RuntimeRoot
$PidDir = Join-Path $RuntimeDir "pids"

function Stop-FromPid($PidFile, $Label) {
    if (-not (Test-Path $PidFile)) {
        Write-Host "PID file non trovato per $Label: $PidFile"
        return
    }

    $ProcIdRaw = (Get-Content $PidFile | Select-Object -First 1)
    if ($null -eq $ProcIdRaw) {
        Write-Host "PID non valido per $Label: file vuoto"
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        return
    }

    $ProcIdRaw = $ProcIdRaw.Trim()
    if (-not $ProcIdRaw) {
        Write-Host "PID non valido per $Label: file vuoto"
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        return
    }

    $procId = 0
    if (-not [int]::TryParse($ProcIdRaw, [ref]$procId)) {
        Write-Host "PID non numerico per $Label: $ProcIdRaw"
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        return
    }

    $Process = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $Process) {
        Write-Host "Processo non trovato per $Label (PID $procId)"
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        return
    }

    try {
        Stop-Process -Id [int]$procId -Force -ErrorAction Stop
        Write-Host "Arrestato $Label (PID $procId)"
    } catch {
        Write-Host "Errore arresto $Label (PID $procId): $($_.Exception.Message)"
    }
    Remove-Item $PidFile -ErrorAction SilentlyContinue
}

Stop-FromPid (Join-Path $PidDir "cloudflared.pid") "cloudflared"
Stop-FromPid (Join-Path $PidDir "api.pid") "API"
Stop-FromPid (Join-Path $PidDir "llm.pid") "LLM"

# Micro test manuale:
# 1) avvia start_thelight.ps1
# 2) verifica che runtime\pids contenga i pid
# 3) esegui stop_thelight.ps1 e verifica che le porte 8080/8081 siano libere
