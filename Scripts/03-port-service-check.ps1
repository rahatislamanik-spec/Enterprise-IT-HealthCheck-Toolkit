# Enterprise IT Network Diagnostics Toolkit
# Script 03: Port & Service Availability Check
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Tests reachability of critical enterprise service ports across
#   key hosts — exports a clean HTML report for escalation and ticket documentation.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 03 — Port & Service Check          " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Port Definitions ───────────────────────────────────────────────────────
$portDefs = @(
    [PSCustomObject]@{ Port = 80;   Service = "HTTP";       Category = "Web" }
    [PSCustomObject]@{ Port = 443;  Service = "HTTPS";      Category = "Web" }
    [PSCustomObject]@{ Port = 53;   Service = "DNS";        Category = "DNS" }
    [PSCustomObject]@{ Port = 22;   Service = "SSH";        Category = "Remote Access" }
    [PSCustomObject]@{ Port = 3389; Service = "RDP";        Category = "Remote Access" }
    [PSCustomObject]@{ Port = 445;  Service = "SMB";        Category = "File Sharing" }
    [PSCustomObject]@{ Port = 25;   Service = "SMTP";       Category = "Email" }
    [PSCustomObject]@{ Port = 587;  Service = "SMTP/TLS";   Category = "Email" }
    [PSCustomObject]@{ Port = 993;  Service = "IMAP/SSL";   Category = "Email" }
    [PSCustomObject]@{ Port = 636;  Service = "LDAPS";      Category = "Directory" }
    [PSCustomObject]@{ Port = 389;  Service = "LDAP";       Category = "Directory" }
    [PSCustomObject]@{ Port = 8080; Service = "HTTP-Alt";   Category = "Web" }
)

# ── Test Targets ───────────────────────────────────────────────────────────
$targets = @("google.com", "microsoft.com", "smtp.office365.com")

# ── Port Test Function ─────────────────────────────────────────────────────
function Test-Port {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2000)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $task   = $client.ConnectAsync($HostName, $Port)
        if ($task.Wait($TimeoutMs)) {
            $client.Close()
            return "OPEN"
        } else {
            $client.Close()
            return "TIMEOUT"
        }
    } catch {
        return "CLOSED"
    }
}

# ── Run Tests ──────────────────────────────────────────────────────────────
Write-Host "Testing ports against: $($targets -join ', ')" -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($t in $targets) {
    Write-Host "  Target: $t" -ForegroundColor Cyan
    foreach ($pd in $portDefs) {
        Write-Host "    Port $($pd.Port) ($($pd.Service))..." -ForegroundColor Gray -NoNewline
        $start  = Get-Date
        $status = Test-Port -HostName $t -Port $pd.Port
        $elapsedMs = [math]::Round(((Get-Date) - $start).TotalMilliseconds)
        Write-Host " $status" -ForegroundColor $(if ($status -eq "OPEN") { "Green" } elseif ($status -eq "TIMEOUT") { "Yellow" } else { "DarkGray" })
        $results += [PSCustomObject]@{
            Target    = $t
            Port      = $pd.Port
            Service   = $pd.Service
            Category  = $pd.Category
            Status    = $status
            LatencyMs = if ($status -eq "OPEN") { $elapsedMs } else { "—" }
        }
    }
}

# ── Summary ────────────────────────────────────────────────────────────────
$open    = ($results | Where-Object { $_.Status -eq "OPEN"    }).Count
$closed  = ($results | Where-Object { $_.Status -eq "CLOSED"  }).Count
$timeout = ($results | Where-Object { $_.Status -eq "TIMEOUT" }).Count
$total   = $results.Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Port Check Complete                       " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Total Tests : $total"   -ForegroundColor Cyan
Write-Host "Open        : $open"    -ForegroundColor Green
Write-Host "Closed      : $closed"  -ForegroundColor Gray
Write-Host "Timeout     : $timeout" -ForegroundColor Yellow

# ── HTML Rows ──────────────────────────────────────────────────────────────
# Group by target
$tableRows = ""
foreach ($t in $targets) {
    $tResults = $results | Where-Object { $_.Target -eq $t }
    $tOpen    = ($tResults | Where-Object { $_.Status -eq "OPEN" }).Count
    $tableRows += "<tr style='background:#f1f5f9'><td colspan='6' style='font-weight:600;color:#0078d4;padding:10px 14px;'>$t &nbsp; <span style='font-weight:400;color:#64748b;font-size:0.8rem'>$tOpen / $($tResults.Count) ports open</span></td></tr>"
    foreach ($r in $tResults) {
        $sc = if ($r.Status -eq "OPEN") { "#45d48a" } elseif ($r.Status -eq "TIMEOUT") { "#f2c86d" } else { "#94a3b8" }
        $tableRows += "<tr>
          <td>$($r.Port)</td>
          <td>$($r.Service)</td>
          <td>$($r.Category)</td>
          <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
          <td>$($r.LatencyMs)</td>
        </tr>"
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Port & Service Check — Enterprise IT Network Diagnostics Toolkit</title>
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
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; }
  tr:last-child td { border-bottom: none; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 03 of 08</div>
  <h1>Port &amp; Service Availability Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$total</div><div class="stat-label">Tests Run</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$open</div><div class="stat-label">Open</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#94a3b8">$closed</div><div class="stat-label">Closed</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#f2c86d">$timeout</div><div class="stat-label">Timeout</div></div>
</div>

<div class="section">
  <h2>Port Results by Target</h2>
  <table>
    <thead><tr><th>Port</th><th>Service</th><th>Category</th><th>Status</th><th>Latency</th></tr></thead>
    <tbody>$tableRows</tbody>
  </table>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/03-port-service-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
