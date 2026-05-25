# Enterprise IT Network Diagnostics Toolkit
# Script 01: DNS Diagnostics
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Resolves multiple domains, checks system DNS servers, detects failures,
#   performs reverse lookups, and exports a clean HTML diagnostic report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 01 — DNS Diagnostics               " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── DNS Servers ────────────────────────────────────────────────────────────
Write-Host "Reading system DNS servers..." -ForegroundColor Yellow

$dnsRaw = & bash -c "scutil --dns 2>/dev/null | grep 'nameserver\[[0-9]*\]' | head -6"
$dnsServers = if ($dnsRaw) {
    ($dnsRaw -split "`n" | ForEach-Object {
        $_.Trim() -replace "nameserver\[\d+\]\s*:\s*", ""
    } | Where-Object { $_ -ne "" } | Select-Object -Unique)
} else { @("Not detected") }

$dnsDisplay = $dnsServers -join ", "
Write-Host "DNS Servers: $dnsDisplay" -ForegroundColor Gray

# ── Domains to Test ────────────────────────────────────────────────────────
$testDomains = @(
    "google.com",
    "microsoft.com",
    "github.com",
    "cloudflare.com",
    "office365.com",
    "apple.com",
    "amazon.com"
)

# ── DNS Resolution Tests ───────────────────────────────────────────────────
Write-Host "Running DNS resolution tests..." -ForegroundColor Yellow

$results = @()

foreach ($domain in $testDomains) {
    Write-Host "  Testing $domain..." -ForegroundColor Gray
    try {
        $start = Get-Date
        $addresses = [System.Net.Dns]::GetHostAddresses($domain)
        $elapsed = [math]::Round(((Get-Date) - $start).TotalMilliseconds, 1)
        $ipv4 = ($addresses | Where-Object { $_.AddressFamily -eq "InterNetwork" } | Select-Object -First 1).ToString()
        $ipv6 = ($addresses | Where-Object { $_.AddressFamily -eq "InterNetworkV6" } | Select-Object -First 1).ToString()
        $results += [PSCustomObject]@{
            Domain    = $domain
            Status    = "RESOLVED"
            IPv4      = if ($ipv4) { $ipv4 } else { "—" }
            IPv6      = if ($ipv6) { $ipv6 } else { "—" }
            LatencyMs = $elapsed
        }
    } catch {
        $results += [PSCustomObject]@{
            Domain    = $domain
            Status    = "FAILED"
            IPv4      = "—"
            IPv6      = "—"
            LatencyMs = "—"
        }
    }
}

# ── Reverse Lookup ─────────────────────────────────────────────────────────
Write-Host "Running reverse DNS lookups..." -ForegroundColor Yellow

$reverseTargets = @("8.8.8.8", "1.1.1.1", "9.9.9.9")
$reverseResults = @()

foreach ($ip in $reverseTargets) {
    try {
        $hostname = [System.Net.Dns]::GetHostEntry($ip).HostName
        $reverseResults += [PSCustomObject]@{ IP = $ip; Hostname = $hostname; Status = "OK" }
    } catch {
        $reverseResults += [PSCustomObject]@{ IP = $ip; Hostname = "No PTR record"; Status = "FAIL" }
    }
}

# ── Summary Stats ──────────────────────────────────────────────────────────
$resolved = ($results | Where-Object { $_.Status -eq "RESOLVED" }).Count
$failed   = ($results | Where-Object { $_.Status -eq "FAILED"   }).Count
$total    = $results.Count
$avgMs    = if ($resolved -gt 0) {
    [math]::Round(($results | Where-Object { $_.LatencyMs -ne "—" } | Measure-Object -Property LatencyMs -Average).Average, 1)
} else { "—" }

$overallStatus = if ($failed -eq 0) { "HEALTHY" } elseif ($failed -lt $total) { "DEGRADED" } else { "FAILED" }
$statusColor   = if ($overallStatus -eq "HEALTHY") { "#45d48a" } elseif ($overallStatus -eq "DEGRADED") { "#f2c86d" } else { "#ff6b6b" }

# ── Console Summary ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " DNS Diagnostics Complete                  " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Domains Tested  : $total"      -ForegroundColor Cyan
Write-Host "Resolved        : $resolved"   -ForegroundColor Green
Write-Host "Failed          : $failed"     -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "Avg Latency     : ${avgMs}ms"  -ForegroundColor Cyan
Write-Host "Overall Status  : $overallStatus" -ForegroundColor $(if ($overallStatus -eq "HEALTHY") { "Green" } elseif ($overallStatus -eq "DEGRADED") { "Yellow" } else { "Red" })

# ── Build HTML Rows ────────────────────────────────────────────────────────
$tableRows = foreach ($r in $results) {
    $sc = if ($r.Status -eq "RESOLVED") { "#45d48a" } else { "#ff6b6b" }
    "<tr>
      <td>$($r.Domain)</td>
      <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
      <td>$($r.IPv4)</td>
      <td>$($r.IPv6)</td>
      <td>$($r.LatencyMs) ms</td>
    </tr>"
}

$reverseRows = foreach ($r in $reverseResults) {
    $sc = if ($r.Status -eq "OK") { "#45d48a" } else { "#f2c86d" }
    "<tr>
      <td>$($r.IP)</td>
      <td>$($r.Hostname)</td>
      <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
    </tr>"
}

$dnsServerList = ($dnsServers | ForEach-Object { "<li>$_</li>" }) -join ""

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ── HTML Report ────────────────────────────────────────────────────────────
$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>DNS Diagnostics Report — Enterprise IT Network Diagnostics Toolkit</title>
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
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th { background: #f8fafc; color: #475569; font-weight: 600; padding: 10px 14px; text-align: left; border-bottom: 2px solid #e2e8f0; }
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; color: #1e293b; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  .overall { display: inline-block; padding: 6px 18px; border-radius: 20px; font-size: 0.95rem; font-weight: 700; color: white; background: $statusColor; }
  ul { padding-left: 18px; }
  ul li { padding: 4px 0; font-size: 0.875rem; color: #334155; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 01 of 08</div>
  <h1>DNS Diagnostics Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$total</div><div class="stat-label">Domains Tested</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$resolved</div><div class="stat-label">Resolved</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#ff6b6b">$failed</div><div class="stat-label">Failed</div></div>
  <div class="stat-card"><div class="stat-value">${avgMs}ms</div><div class="stat-label">Avg Latency</div></div>
</div>

<div class="section">
  <h2>Overall DNS Health &nbsp; <span class="overall">$overallStatus</span></h2>
  <h2 style="margin-top:16px; border:none; padding:0; color:#475569; font-size:0.9rem;">System DNS Servers</h2>
  <ul style="margin-top:8px">$dnsServerList</ul>
</div>

<div class="section">
  <h2>DNS Resolution Results</h2>
  <table>
    <thead><tr><th>Domain</th><th>Status</th><th>IPv4</th><th>IPv6</th><th>Latency</th></tr></thead>
    <tbody>$($tableRows -join "")</tbody>
  </table>
</div>

<div class="section">
  <h2>Reverse DNS Lookups</h2>
  <table>
    <thead><tr><th>IP Address</th><th>Hostname</th><th>Status</th></tr></thead>
    <tbody>$($reverseRows -join "")</tbody>
  </table>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

# ── Export ─────────────────────────────────────────────────────────────────
if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/01-dns-diagnostics-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
