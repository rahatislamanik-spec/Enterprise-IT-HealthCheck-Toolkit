# Enterprise IT Network Diagnostics Toolkit
# Script 05: Network Adapter Health
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Enumerates all network interfaces, reports IP/MAC/MTU/status,
#   flags inactive or misconfigured adapters — exports a clean HTML report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 05 — Network Adapter Health        " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Enumerating network interfaces..." -ForegroundColor Yellow

# ── Parse ifconfig ─────────────────────────────────────────────────────────
$ifconfigRaw = & ifconfig 2>/dev/null
$interfaces  = @()
$currentIf   = $null

foreach ($line in $ifconfigRaw) {
    # New interface block
    if ($line -match '^(\w+):') {
        if ($currentIf) { $interfaces += $currentIf }
        $currentIf = [PSCustomObject]@{
            Name    = $Matches[1]
            Status  = "inactive"
            IPv4    = "—"
            IPv6    = "—"
            MAC     = "—"
            MTU     = "—"
            Flags   = ""
            Media   = "—"
        }
        if ($line -match 'mtu (\d+)') { $currentIf.MTU = $Matches[1] }
        if ($line -match '<(.+?)>') {
            $currentIf.Flags = $Matches[1]
            if ($currentIf.Flags -match 'UP') { $currentIf.Status = "active" }
        }
    }
    if (-not $currentIf) { continue }
    if ($line -match '^\s+inet (\d+\.\d+\.\d+\.\d+)')   { $currentIf.IPv4  = $Matches[1] }
    if ($line -match '^\s+inet6 ([a-f0-9:]+)')            { if ($currentIf.IPv6 -eq "—") { $currentIf.IPv6 = $Matches[1] } }
    if ($line -match '^\s+ether ([0-9a-f:]{17})')         { $currentIf.MAC   = $Matches[1] }
    if ($line -match 'media:\s+(.+)$')                    { $currentIf.Media = $Matches[1].Trim() }
}
if ($currentIf) { $interfaces += $currentIf }

# ── Filter interesting interfaces ──────────────────────────────────────────
$relevant = $interfaces | Where-Object {
    $_.Name -match '^(en|utun|ipsec|bridge|vlan|lo)\d*$'
}

# ── Routing Table Summary ──────────────────────────────────────────────────
Write-Host "Reading routing table..." -ForegroundColor Yellow
$routeRaw = & bash -c "netstat -rn 2>/dev/null | head -25"
$routeText = $routeRaw -join "`n"

# ── Default Gateway ────────────────────────────────────────────────────────
$gatewayRaw = & bash -c "route -n get default 2>/dev/null | grep gateway"
$gateway    = if ($gatewayRaw) { ($gatewayRaw -replace "gateway:", "").Trim() } else { "—" }

# ── Summary Stats ──────────────────────────────────────────────────────────
$active   = ($relevant | Where-Object { $_.Status -eq "active"   }).Count
$inactive = ($relevant | Where-Object { $_.Status -eq "inactive" }).Count
$withIP   = ($relevant | Where-Object { $_.IPv4   -ne "—"        }).Count
$total    = $relevant.Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Network Adapter Health Complete           " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Interfaces Found : $total"    -ForegroundColor Cyan
Write-Host "Active           : $active"   -ForegroundColor Green
Write-Host "Inactive         : $inactive" -ForegroundColor Gray
Write-Host "With IP Address  : $withIP"   -ForegroundColor Cyan
Write-Host "Default Gateway  : $gateway"  -ForegroundColor Cyan

foreach ($if in $relevant | Where-Object { $_.Status -eq "active" }) {
    Write-Host "  $($if.Name) — $($if.IPv4) — $($if.MAC)" -ForegroundColor Gray
}

# ── HTML Table Rows ────────────────────────────────────────────────────────
$tableRows = foreach ($if in $relevant) {
    $sc = if ($if.Status -eq "active") { "#45d48a" } else { "#94a3b8" }
    $ipHl = if ($if.IPv4 -ne "—") { "<strong>$($if.IPv4)</strong>" } else { "—" }
    "<tr>
      <td><strong>$($if.Name)</strong></td>
      <td><span class='badge' style='background:$sc'>$($if.Status.ToUpper())</span></td>
      <td>$ipHl</td>
      <td>$($if.IPv6)</td>
      <td>$($if.MAC)</td>
      <td>$($if.MTU)</td>
      <td style='font-size:0.78rem;color:#64748b'>$($if.Media)</td>
    </tr>"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Network Adapter Health — Enterprise IT Network Diagnostics Toolkit</title>
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
  .env-row { display: flex; gap: 32px; font-size: 0.875rem; }
  .env-item { display: flex; flex-direction: column; gap: 2px; }
  .env-label { font-size: 0.75rem; color: #64748b; font-weight: 600; text-transform: uppercase; }
  .env-value { color: #1e293b; font-weight: 500; }
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th { background: #f8fafc; color: #475569; font-weight: 600; padding: 10px 14px; text-align: left; border-bottom: 2px solid #e2e8f0; }
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  pre { background: #f8fafc; border: 1px solid #e2e8f0; padding: 14px; border-radius: 6px; font-size: 0.78rem; overflow-x: auto; white-space: pre; margin: 0; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 05 of 08</div>
  <h1>Network Adapter Health Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$total</div><div class="stat-label">Interfaces</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$active</div><div class="stat-label">Active</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#94a3b8">$inactive</div><div class="stat-label">Inactive</div></div>
  <div class="stat-card"><div class="stat-value">$withIP</div><div class="stat-label">With IP</div></div>
</div>

<div class="section">
  <h2>Environment</h2>
  <div class="env-row">
    <div class="env-item"><span class="env-label">Default Gateway</span><span class="env-value">$gateway</span></div>
    <div class="env-item"><span class="env-label">Interfaces Found</span><span class="env-value">$total</span></div>
    <div class="env-item"><span class="env-label">Scan Time</span><span class="env-value">$timestamp</span></div>
  </div>
</div>

<div class="section">
  <h2>Interface Details</h2>
  <table>
    <thead><tr><th>Interface</th><th>Status</th><th>IPv4</th><th>IPv6</th><th>MAC Address</th><th>MTU</th><th>Media</th></tr></thead>
    <tbody>$($tableRows -join "")</tbody>
  </table>
</div>

<div class="section">
  <h2>Routing Table (summary)</h2>
  <pre>$routeText</pre>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/05-network-adapter-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
