# Enterprise IT Network Diagnostics Toolkit
# Script 02: Network Connectivity Check
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Tests gateway reachability, internet connectivity, packet loss,
#   and latency to key public hosts — exports a clean HTML diagnostic report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 02 — Network Connectivity Check    " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Default Gateway ────────────────────────────────────────────────────────
Write-Host "Detecting default gateway..." -ForegroundColor Yellow
$gatewayRaw = & bash -c "route -n get default 2>/dev/null | grep gateway"
$gateway    = if ($gatewayRaw) { ($gatewayRaw -replace "gateway:", "").Trim() } else { $null }
Write-Host "Gateway: $(if ($gateway) { $gateway } else { 'Not detected' })" -ForegroundColor Gray

# ── IP Address ─────────────────────────────────────────────────────────────
$ipAddress = & ipconfig getifaddr en0 2>/dev/null
if (-not $ipAddress) { $ipAddress = & ipconfig getifaddr en1 2>/dev/null }
if (-not $ipAddress) { $ipAddress = "Not detected" }

# ── Hosts to Test ─────────────────────────────────────────────────────────
$hosts = [ordered]@{}
if ($gateway) { $hosts["Default Gateway"] = $gateway }
$hosts["Google DNS (8.8.8.8)"]      = "8.8.8.8"
$hosts["Cloudflare DNS (1.1.1.1)"]  = "1.1.1.1"
$hosts["Quad9 DNS (9.9.9.9)"]       = "9.9.9.9"
$hosts["Google"]                     = "google.com"
$hosts["Microsoft"]                  = "microsoft.com"
$hosts["Cloudflare"]                 = "cloudflare.com"

# ── Ping Each Host ─────────────────────────────────────────────────────────
Write-Host "Running connectivity tests..." -ForegroundColor Yellow

$results = @()

foreach ($name in $hosts.Keys) {
    $target = $hosts[$name]
    Write-Host "  Pinging $target ($name)..." -ForegroundColor Gray

    $raw = & ping -c 4 -W 2 $target 2>&1
    $output = $raw -join "`n"

    # Parse packet loss
    $lossLine = $raw | Where-Object { $_ -match "packet loss" }
    $lossMatch = [regex]::Match($lossLine, '(\d+(?:\.\d+)?)% packet loss')
    $loss = if ($lossMatch.Success) { [double]$lossMatch.Groups[1].Value } else { 100 }

    # Parse latency (round-trip)
    $rtLine = $raw | Where-Object { $_ -match "round-trip|rtt" }
    $rtMatch = [regex]::Match($rtLine, '(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)')
    $minMs  = if ($rtMatch.Success) { $rtMatch.Groups[1].Value } else { "—" }
    $avgMs  = if ($rtMatch.Success) { $rtMatch.Groups[2].Value } else { "—" }
    $maxMs  = if ($rtMatch.Success) { $rtMatch.Groups[3].Value } else { "—" }

    $status = if ($loss -eq 0) { "PASS" } elseif ($loss -lt 50) { "WARN" } else { "FAIL" }

    $results += [PSCustomObject]@{
        Name   = $name
        Target = $target
        Status = $status
        Loss   = "$loss%"
        MinMs  = $minMs
        AvgMs  = $avgMs
        MaxMs  = $maxMs
    }
}

# ── Summary ────────────────────────────────────────────────────────────────
$pass    = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$warn    = ($results | Where-Object { $_.Status -eq "WARN" }).Count
$fail    = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total   = $results.Count
$overall = if ($fail -eq 0 -and $warn -eq 0) { "HEALTHY" } elseif ($fail -eq $total) { "NO CONNECTIVITY" } else { "DEGRADED" }
$statusColor = if ($overall -eq "HEALTHY") { "#45d48a" } elseif ($overall -eq "DEGRADED") { "#f2c86d" } else { "#ff6b6b" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Connectivity Check Complete               " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Local IP   : $ipAddress" -ForegroundColor Cyan
Write-Host "Gateway    : $(if ($gateway) { $gateway } else { 'Not detected' })" -ForegroundColor Cyan
Write-Host "PASS       : $pass"      -ForegroundColor Green
Write-Host "WARN       : $warn"      -ForegroundColor Yellow
Write-Host "FAIL       : $fail"      -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
Write-Host "Overall    : $overall"   -ForegroundColor $(if ($overall -eq "HEALTHY") { "Green" } elseif ($overall -eq "DEGRADED") { "Yellow" } else { "Red" })

# ── HTML Rows ──────────────────────────────────────────────────────────────
$tableRows = foreach ($r in $results) {
    $sc = if ($r.Status -eq "PASS") { "#45d48a" } elseif ($r.Status -eq "WARN") { "#f2c86d" } else { "#ff6b6b" }
    "<tr>
      <td>$($r.Name)</td>
      <td>$($r.Target)</td>
      <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
      <td>$($r.Loss)</td>
      <td>$($r.MinMs) ms</td>
      <td>$($r.AvgMs) ms</td>
      <td>$($r.MaxMs) ms</td>
    </tr>"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ── HTML Report ────────────────────────────────────────────────────────────
$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Network Connectivity Report — Enterprise IT Network Diagnostics Toolkit</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f4f8; color: #1e293b; padding: 24px; }
  .header { background: linear-gradient(135deg, #0078d4, #005a9e); color: white; padding: 26px 30px; border-radius: 12px; margin-bottom: 24px; }
  .header h1 { font-size: 1.4rem; margin-bottom: 4px; }
  .header p  { opacity: 0.85; font-size: 0.875rem; }
  .script-tag { display: inline-block; background: rgba(255,255,255,0.2); border-radius: 20px; padding: 2px 12px; font-size: 0.78rem; margin-bottom: 10px; }
  .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px; }
  .stat-card { background: white; border-radius: 10px; padding: 18px 20px; box-shadow: 0 1px 4px rgba(0,0,0,.07); text-align: center; }
  .stat-value { font-size: 2rem; font-weight: 700; color: #0078d4; }
  .stat-label { font-size: 0.8rem; color: #64748b; margin-top: 4px; }
  .section { background: white; border-radius: 10px; padding: 22px; box-shadow: 0 1px 4px rgba(0,0,0,.07); margin-bottom: 20px; }
  .section h2 { font-size: 1rem; color: #0078d4; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px; margin-bottom: 16px; }
  .env-row { display: flex; gap: 32px; flex-wrap: wrap; font-size: 0.875rem; }
  .env-item { display: flex; flex-direction: column; gap: 2px; }
  .env-label { font-size: 0.75rem; color: #64748b; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; }
  .env-value { color: #1e293b; font-weight: 500; }
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th { background: #f8fafc; color: #475569; font-weight: 600; padding: 10px 14px; text-align: left; border-bottom: 2px solid #e2e8f0; }
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  .overall { display: inline-block; padding: 6px 18px; border-radius: 20px; font-size: 0.95rem; font-weight: 700; color: white; background: $statusColor; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 02 of 08</div>
  <h1>Network Connectivity Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$total</div><div class="stat-label">Hosts Tested</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$pass</div><div class="stat-label">Passing</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#f2c86d">$warn</div><div class="stat-label">Degraded</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#ff6b6b">$fail</div><div class="stat-label">Failed</div></div>
</div>

<div class="section">
  <h2>Environment &nbsp; <span class="overall">$overall</span></h2>
  <div class="env-row" style="margin-top:12px">
    <div class="env-item"><span class="env-label">Local IP</span><span class="env-value">$ipAddress</span></div>
    <div class="env-item"><span class="env-label">Default Gateway</span><span class="env-value">$(if ($gateway) { $gateway } else { 'Not detected' })</span></div>
    <div class="env-item"><span class="env-label">Tested</span><span class="env-value">$timestamp</span></div>
  </div>
</div>

<div class="section">
  <h2>Connectivity Results</h2>
  <table>
    <thead><tr><th>Host</th><th>Target</th><th>Status</th><th>Packet Loss</th><th>Min RTT</th><th>Avg RTT</th><th>Max RTT</th></tr></thead>
    <tbody>$($tableRows -join "")</tbody>
  </table>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/02-network-connectivity-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
