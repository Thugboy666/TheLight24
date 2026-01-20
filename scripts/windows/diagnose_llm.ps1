$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$RuntimeRoot = Join-Path $RepoRoot "..\runtime"
if (-not (Test-Path $RuntimeRoot)) {
    Write-Host "Runtime non trovato: $RuntimeRoot"
    exit 0
}
$RuntimeDir = Resolve-Path $RuntimeRoot
$LogDir = Join-Path $RuntimeDir "logs"
$PidDir = Join-Path $RuntimeDir "pids"

Write-Host "=== netstat :8081 ==="
cmd /c "netstat -ano | findstr :8081"

Write-Host "=== Get-NetTCPConnection :8081 ==="
Get-NetTCPConnection -LocalPort 8081 -ErrorAction SilentlyContinue | Format-Table -AutoSize

$LlmPidFile = Join-Path $PidDir "llm.pid"
if (Test-Path $LlmPidFile) {
    $pidRaw = (Get-Content $LlmPidFile | Select-Object -First 1).Trim()
    if ($pidRaw) {
        Write-Host "=== tasklist PID $pidRaw ==="
        cmd /c "tasklist /FI \"PID eq $pidRaw\""
    } else {
        Write-Host "PID file presente ma vuoto: $LlmPidFile"
    }
} else {
    Write-Host "PID file non trovato: $LlmPidFile"
}

$LlmErr = Join-Path $LogDir "llm_err.log"
$LlmOut = Join-Path $LogDir "llm_out.log"

if (Test-Path $LlmErr) {
    Write-Host "=== llm_err.log (last 80 lines) ==="
    Get-Content -Path $LlmErr -Tail 80
} else {
    Write-Host "llm_err.log non trovato: $LlmErr"
}

if (Test-Path $LlmOut) {
    Write-Host "=== llm_out.log (last 80 lines) ==="
    Get-Content -Path $LlmOut -Tail 80
} else {
    Write-Host "llm_out.log non trovato: $LlmOut"
}

Write-Host "=== curl ping /completion ==="
try {
    & curl.exe -s -X POST -H "Content-Type: application/json" -d "{\"prompt\":\"ping\",\"n_predict\":1}" "http://127.0.0.1:8081/completion"
} catch {
    Write-Host "curl ping failed: $($_.Exception.Message)"
}
