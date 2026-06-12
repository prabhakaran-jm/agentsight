# Ensure Ollama is running (needed for | ai / Foundation-Sec classify even in demo mode).
param(
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [int]$WaitSec = 60
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_splunk_rest.ps1"

function Test-OllamaUp {
    try {
        Invoke-SplunkRestMethod -Uri "$OllamaUrl/api/tags" -Method Get | Out-Null
        return $true
    } catch {
        return $false
    }
}

if (Test-OllamaUp) {
    Write-Host "Ollama OK at $OllamaUrl" -ForegroundColor Green
    exit 0
}

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
    Write-Host "WARN: ollama not in PATH. Start Ollama Desktop or install from https://ollama.com" -ForegroundColor Yellow
    exit 1
}

Write-Host "Starting ollama serve in background..."
Start-Process -FilePath $ollama.Source -ArgumentList "serve" -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds($WaitSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if (Test-OllamaUp) {
        Write-Host "Ollama ready at $OllamaUrl" -ForegroundColor Green
        exit 0
    }
}

Write-Host "FAIL: Ollama did not respond within ${WaitSec}s" -ForegroundColor Red
exit 1
