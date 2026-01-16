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
    if (-not (Test-Path $PidFile)) { return }
    $pid = Get-Content $PidFile | Select-Object -First 1
    if ($pid) {
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "Arrestato $Label (PID $pid)"
        } catch {
            Write-Host "Impossibile arrestare $Label (PID $pid)"
        }
    }
    Remove-Item $PidFile -ErrorAction SilentlyContinue
}

Stop-FromPid (Join-Path $PidDir "cloudflared.pid") "cloudflared"
Stop-FromPid (Join-Path $PidDir "api.pid") "API"
Stop-FromPid (Join-Path $PidDir "llm.pid") "LLM"
