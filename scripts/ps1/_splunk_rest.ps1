# Shared Splunk REST helpers for Windows PowerShell scripts.
# Dot-source: . "$PSScriptRoot\_splunk_rest.ps1"
# Compatible with Windows PowerShell 5.1 (no -SkipCertificateCheck) and PowerShell 7+.

$script:SplunkTlsReady = $false

function Enable-SplunkInsecureTls {
    if ($script:SplunkTlsReady) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    # Windows PowerShell 5.1 has no -SkipCertificateCheck; trust Splunk's self-signed cert locally.
    [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $script:SplunkTlsReady = $true
}

function Invoke-SplunkWebRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers,
        [object]$Body
    )
    Enable-SplunkInsecureTls
    $params = @{
        Uri             = $Uri
        Method          = $Method
        UseBasicParsing = $true
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($null -ne $Body) { $params.Body = $Body }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $params.SkipCertificateCheck = $true
    }
    Invoke-WebRequest @params
}

function Invoke-SplunkRestMethod {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = "Get",
        [hashtable]$Headers,
        [object]$Body
    )
    Enable-SplunkInsecureTls
    $params = @{
        Uri    = $Uri
        Method = $Method
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($null -ne $Body) { $params.Body = $Body }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $params.SkipCertificateCheck = $true
    }
    Invoke-RestMethod @params
}

function Resolve-SplunkHome {
    if ($env:SPLUNK_HOME -and (Test-Path (Join-Path $env:SPLUNK_HOME "bin\splunk.exe"))) {
        return $env:SPLUNK_HOME
    }
    foreach ($candidate in @("D:\splunk", "C:\Program Files\Splunk")) {
        if (Test-Path (Join-Path $candidate "bin\splunk.exe")) {
            return $candidate
        }
    }
    return $(if ($env:SPLUNK_HOME) { $env:SPLUNK_HOME } else { "D:\splunk" })
}

function Get-SplunkSessionKey {
    param(
        [string]$SplunkUrl = "https://127.0.0.1:8089",
        [string]$Username = "admin",
        [string]$Password = $env:SPLUNK_PASSWORD
    )
    if (-not $Password) {
        throw "Set SPLUNK_PASSWORD to your Splunk admin password (Splunk Web login)."
    }
    $body = @{ username = $Username; password = $Password }
    $response = Invoke-SplunkWebRequest -Uri "$SplunkUrl/services/auth/login" -Method Post -Body $body
    if ($response.Content -match '<sessionKey>([^<]+)</sessionKey>') {
        return $Matches[1]
    }
    if ($response.Content -match '<msg[^>]*>([^<]+)</msg>') {
        throw "Splunk login failed: $($Matches[1])"
    }
    throw "Splunk login failed: no sessionKey in response"
}

function Normalize-SplunkSearch {
    param([string]$Search)
    $s = $Search.Trim()
    if ($s -match '^(?i)search\b') { return $s }
    # Generating commands: leading pipe (implicit search *) for CLI + REST export.
    # Bare "agentsightapprove" via "splunk search" becomes invalid "search agentsightapprove".
    if ($s -match '^(?i)(\|\s*)?agentsight(approve|explain)\b') {
        if ($s.StartsWith("|")) { return $s }
        return "| $s"
    }
    if ($s.StartsWith("|")) { return "search $s" }
    return "search $s"
}

function Get-SplunkField {
    param($Value)
    $current = $Value
    while ($null -ne $current) {
        if ($current -is [string]) { return $current }
        if ($current -is [datetime]) {
            return $current.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
        }
        if ($current -is [System.Collections.IEnumerable]) {
            $items = @($current)
            if ($items.Count -eq 0) { return "" }
            $current = $items[0]
            continue
        }
        return [string]$current
    }
    return ""
}

function Convert-SplunkResultRow {
    param($Result)
    if ($null -eq $Result) { return $null }
    $props = @{}
    foreach ($prop in $Result.PSObject.Properties) {
        $props[$prop.Name] = Get-SplunkField $prop.Value
    }
    return [PSCustomObject]$props
}

function Get-LatestAgentsightCaseId {
    param([string]$SplunkHome)
    $log = Join-Path $SplunkHome "var\log\splunk\agentsight.log"
    if (-not (Test-Path $log)) { return $null }
    $hit = Select-String -Path $log -Pattern 'Created case (case_[a-f0-9]+)' -AllMatches | Select-Object -Last 1
    if (-not $hit) { return $null }
    return $hit.Matches[-1].Groups[1].Value
}

function Invoke-SplunkCliSearch {
    param(
        [string]$Search,
        [string]$SplunkHome,
        [string]$Password,
        [string]$Username = "admin",
        [string]$App = "agentsight",
        [int]$TimeoutSec = 0
    )
    $splunkExe = Join-Path $SplunkHome "bin\splunk.exe"
    $normalized = Normalize-SplunkSearch -Search $Search
    # splunk.exe writes benign TLS warnings to stderr; PS 5.1 treats those as terminating errors.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $args = @(
            "search", $normalized,
            "-auth", "${Username}:${Password}",
            "-app", $App
        )
        if ($TimeoutSec -gt 0) { $args += @("-timeout", [string]$TimeoutSec) }
        $raw = & $splunkExe @args 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    $lines = @()
    foreach ($item in @($raw)) {
        if ($item -is [System.Management.Automation.ErrorRecord]) {
            $lines += $item.ToString()
        } else {
            $lines += [string]$item
        }
    }
    $text = ($lines -join "`n").Trim()
    if ($exit -ne 0 -and -not $text) {
        throw "splunk search failed (exit $exit): $normalized"
    }
    return $text
}

function Invoke-SplunkOneshotSearch {
    param(
        [string]$Search,
        [string]$SessionKey,
        [string]$SplunkUrl = "https://127.0.0.1:8089",
        [string]$Earliest = "-15m",
        [string]$Latest = "now",
        [string]$App = "agentsight"
    )
    $Search = Normalize-SplunkSearch -Search $Search
    $headers = @{ Authorization = "Splunk $SessionKey" }
    $body = @{
        search        = $Search
        output_mode   = "json"
        earliest_time = $Earliest
        latest_time   = $Latest
        app           = $App
    }
    try {
        $raw = Invoke-SplunkWebRequest -Uri "$SplunkUrl/services/search/jobs/export" -Method Post `
            -Headers $headers -Body $body
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw "Splunk search failed: $detail`nQuery: $Search"
    }
    $rows = @()
    foreach ($line in ($raw.Content -split "`n")) {
        if (-not $line.Trim()) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.result) { $rows += Convert-SplunkResultRow $obj.result }
        } catch {
            # skip non-json lines
        }
    }
    return $rows
}

function Wait-SplunkSearchJob {
    param(
        [string]$Sid,
        [string]$SessionKey,
        [string]$SplunkUrl = "https://127.0.0.1:8089",
        [int]$TimeoutSec = 120
    )
    $headers = @{ Authorization = "Splunk $SessionKey" }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $status = Invoke-SplunkRestMethod -Uri "$SplunkUrl/services/search/jobs/$Sid" `
            -Headers $headers
        $state = $status.entry.content.dispatchState
        if ($state -eq "DONE") { return $true }
        if ($state -in @("FAILED", "INTERNAL_CANCEL")) {
            throw "Search job $Sid failed: $state"
        }
        Start-Sleep -Seconds 2
    }
    throw "Search job $Sid timed out after ${TimeoutSec}s"
}

function Get-SplunkSearchResults {
    param(
        [string]$Sid,
        [string]$SessionKey,
        [string]$SplunkUrl = "https://127.0.0.1:8089",
        [int]$Count = 100
    )
    $headers = @{ Authorization = "Splunk $SessionKey" }
    $uri = "$SplunkUrl/services/search/jobs/$Sid/results?output_mode=json&count=$Count"
    $raw = Invoke-SplunkWebRequest -Uri $uri -Headers $headers
    $rows = @()
    foreach ($line in ($raw.Content -split "`n")) {
        if (-not $line.Trim()) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.result) { $rows += Convert-SplunkResultRow $obj.result }
        } catch { }
    }
    return $rows
}

function Start-SplunkSearchJob {
    param(
        [string]$Search,
        [string]$SessionKey,
        [string]$SplunkUrl = "https://127.0.0.1:8089",
        [string]$Earliest = "-15m",
        [string]$Latest = "now"
    )
    $Search = Normalize-SplunkSearch -Search $Search
    $headers = @{ Authorization = "Splunk $SessionKey" }
    $body = @{
        search        = $Search
        earliest_time = $Earliest
        latest_time   = $Latest
    }
    $resp = Invoke-SplunkRestMethod -Uri "$SplunkUrl/services/search/jobs" -Method Post `
        -Headers $headers -Body $body
    return $resp.sid
}

function Write-GzipCsv {
    param(
        [string]$Path,
        [string[]]$Headers,
        [hashtable[]]$Rows
    )
    $lines = @(($Headers -join ","))
    foreach ($row in $Rows) {
        $cells = foreach ($h in $Headers) {
            $v = $row[$h]
            if ($null -eq $v) { $v = "" }
            $v = [string]$v
            if ($v -match '[,"\r\n]') {
                '"' + ($v -replace '"', '""') + '"'
            } else { $v }
        }
        $lines += ($cells -join ",")
    }
    $csvBytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n")
    $fs = [System.IO.File]::Create($Path)
    try {
        $gz = New-Object System.IO.Compression.GzipStream($fs, [System.IO.Compression.CompressionMode]::Compress)
        $gz.Write($csvBytes, 0, $csvBytes.Length)
        $gz.Close()
    } finally {
        $fs.Close()
    }
}
