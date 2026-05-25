# Enterprise IT Network Diagnostics Toolkit
# Script 08: Latency Baseline & Jitter Analysis
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Sends extended ping bursts to multiple targets, calculates
#   min/max/avg latency, jitter, and packet loss — exports a clean HTML report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 08 — Latency Baseline & Jitter     " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Test Configuration ─────────────────────────────────────────────────────
$packetCount = 20   # pings per target
$timeout     = 2    # seconds per probe

$targets = @(
    [PSCustomObject]@{ Label = "Google DNS";     Host = "8.8.8.8" }
    [PSCustomObject]@{ Label = "Cloudflare DNS"; Host = "1.1.1.1" }
    [PSCustomObject]@{ Label = "Quad9 DNS";      Host = "9.9.9.9" }
    [PSCustomObject]@{ Label = "Google";         Host = "google.com" }
    [PSCustomObject]@{ Label = "Microsoft";      Host = "microsoft.com" }
)

Write-Host "Configuration: $packetCount packets per target, ${timeout}s timeout" -ForegroundColor Gray
Write-Host ""

# ── Run Extended Ping ──────────────────────────────────────────────────────
function Get-LatencyStats {
    param([string]$Host, [int]$Count, [int]$Timeout)

    $raw = & ping -c $Count -W $Timeout $Host 2>&1
    $output = $raw -join "`n"

    # Individual RTT values
    $rtts = [regex]::Matches($output, 'time=([\d.]+)\s+ms') |
            ForEach-Object { [double]$_.Groups[1].Value }

    # Packet loss
    $lossLine  = $raw | Where-Object { $_ -match "packet loss" }
    $lossMatch = [regex]::Match($lossLine, '(\d+(?:\.\d+)?)% packet loss')
    $loss      = if ($lossMatch.Success) { [double]$lossMatch.Groups[1].Value } else { 100 }

    if ($rtts.Count -eq 0) {
        return [PSCustomObject]@{
            Host       = $Host
            Sent       = $Count
            Received   = 0
            Loss       = 100
            MinMs      = "—"; MaxMs = "—"; AvgMs = "—"; Jitter = "—"
            Status     = "FAIL"
            RTTs       = @()
        }
    }

    $min    = [math]::Round(($rtts | Measure-Object -Minimum).Minimum, 2)
    $max    = [math]::Round(($rtts | Measure-Object -Maximum).Maximum, 2)
    $avg    = [math]::Round(($rtts | Measure-Object -Average).Average, 2)
    $received = $rtts.Count

    # Jitter = mean absolute deviation of consecutive differences
    $diffs = @()
    for ($i = 1; $i -lt $rtts.Count; $i++) {
        $diffs += [math]::Abs($rtts[$i] - $rtts[$i-1])
    }
    $jitter = if ($diffs.Count -gt 0) {
        [math]::Round(($diffs | Measure-Object -Average).Average, 2)
    } else { 0 }

    $status = if ($loss -eq 0 -and $avg -lt 50) { "EXCELLENT" }
              elseif ($loss -eq 0 -and $avg -lt 100) { "GOOD" }
              elseif ($loss -lt 10) { "FAIR" }
              elseif ($loss -lt 50) { "POOR" }
              else { "FAIL" }

    return [PSCustomObject]@{
        Host      = $Host
        Sent      = $Count
        Received  = $received
        Loss      = $loss
        MinMs     = $min
        MaxMs     = $max
        AvgMs     = $avg
        Jitter    = $jitter
        Status    = $status
        RTTs      = $rtts
    }
}

# ── Execute ────────────────────────────────────────────────────────────────
$results = @()
foreach ($t in $targets) {
    Write-Host "Testing $($t.Label) ($($t.Host)) — $packetCount packets..." -ForegroundColor Yellow
    $stats = Get-LatencyStats -Host $t.Host -Count $packetCount -Timeout $timeout
    $stats | Add-Member -NotePropertyName Label -NotePropertyValue $t.Label
    $results += $stats

    $statusColor = switch ($stats.Status) {
        "EXCELLENT" { "Green" } "GOOD" { "Green" } "FAIR" { "Yellow" }
        "POOR"      { "Red"   } "FAIL" { "Red"   } default { "Gray" }
    }
    Write-Host "  $($stats.Status) — Avg: $($stats.AvgMs)ms  Jitter: $($stats.Jitter)ms  Loss: $($stats.Loss)%" -ForegroundColor $statusColor
}

# ── Overall Summary ────────────────────────────────────────────────────────
$passing = ($results | Where-Object { $_.Status -in @("EXCELLENT","GOOD","FAIR") }).Count
$failing = ($results | Where-Object { $_.Status -in @("POOR","FAIL") }).Count
$overallAvg = if (($results | Where-Object { $_.AvgMs -ne "—" }).Count -gt 0) {
    [math]::Round(($results | Where-Object { $_.AvgMs -ne "—" } | Measure-Object -Property AvgMs -Average).Average, 2)
} else { "—" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Latency Baseline Complete                 " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Targets Tested : $($results.Count)"   -ForegroundColor Cyan
Write-Host "Passing        : $passing"             -ForegroundColor Green
Write-Host "Failing        : $failing"             -ForegroundColor $(if ($failing -gt 0) { "Red" } else { "Green" })
Write-Host "Overall Avg    : ${overallAvg}ms"      -ForegroundColor Cyan

# ── HTML Table Rows ────────────────────────────────────────────────────────
$tableRows = foreach ($r in $results) {
    $sc = switch ($r.Status) {
        "EXCELLENT" { "#45d48a" } "GOOD" { "#45d48a" } "FAIR" { "#f2c86d" }
        "POOR"      { "#ff6b6b" } "FAIL" { "#dc2626" } default { "#94a3b8" }
    }
    $lossColor = if ($r.Loss -eq 0) { "#45d48a" } elseif ($r.Loss -lt 10) { "#f2c86d" } else { "#ff6b6b" }
    "<tr>
      <td><strong>$($r.Label)</strong></td>
      <td>$($r.Host)</td>
      <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
      <td>$($r.Sent)</td>
      <td>$($r.Received)</td>
      <td style='color:$lossColor;font-weight:600'>$($r.Loss)%</td>
      <td>$($r.MinMs) ms</td>
      <td>$($r.AvgMs) ms</td>
      <td>$($r.MaxMs) ms</td>
      <td>$($r.Jitter) ms</td>
    </tr>"
}

# Sparkline data for inline visualization
$sparkSections = foreach ($r in $results) {
    if ($r.RTTs.Count -gt 0) {
        $maxRtt = ($r.RTTs | Measure-Object -Maximum).Maximum
        $bars = ($r.RTTs | ForEach-Object {
            $pct = if ($maxRtt -gt 0) { [math]::Round($_ / $maxRtt * 40) } else { 1 }
            $color = if ($_ -lt 50) { "#45d48a" } elseif ($_ -lt 100) { "#f2c86d" } else { "#ff6b6b" }
            "<div style='display:inline-block;width:8px;height:${pct}px;background:$color;margin:1px;vertical-align:bottom;border-radius:2px 2px 0 0' title='${_}ms'></div>"
        }) -join ""
        "<div class='sparkline-row'>
          <span class='spark-label'>$($r.Label)</span>
          <div class='sparkline'>$bars</div>
          <span class='spark-range'>$($r.MinMs)ms — $($r.MaxMs)ms</span>
        </div>"
    }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Latency Baseline — Enterprise IT Network Diagnostics Toolkit</title>
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
  tr:hover td { background: #f8fafc; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  .sparkline-row { display: flex; align-items: flex-end; gap: 12px; padding: 10px 0; border-bottom: 1px solid #f1f5f9; }
  .sparkline-row:last-child { border-bottom: none; }
  .spark-label { min-width: 140px; font-size: 0.875rem; font-weight: 600; color: #475569; }
  .sparkline { display: flex; align-items: flex-end; height: 44px; }
  .spark-range { font-size: 0.78rem; color: #94a3b8; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 08 of 08</div>
  <h1>Latency Baseline &amp; Jitter Analysis Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; $packetCount packets per target &nbsp;|&nbsp; Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$($results.Count)</div><div class="stat-label">Targets Tested</div></div>
  <div class="stat-card"><div class="stat-value">$packetCount</div><div class="stat-label">Packets Per Target</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$passing</div><div class="stat-label">Healthy</div></div>
  <div class="stat-card"><div class="stat-value">${overallAvg}ms</div><div class="stat-label">Overall Avg RTT</div></div>
</div>

<div class="section">
  <h2>Latency Results</h2>
  <table>
    <thead><tr><th>Target</th><th>Host</th><th>Quality</th><th>Sent</th><th>Received</th><th>Loss</th><th>Min RTT</th><th>Avg RTT</th><th>Max RTT</th><th>Jitter</th></tr></thead>
    <tbody>$($tableRows -join "")</tbody>
  </table>
</div>

<div class="section">
  <h2>RTT Sparklines &nbsp;<span style="font-size:0.8rem;color:#64748b;font-weight:400">Each bar = one ping. Green &lt;50ms · Yellow &lt;100ms · Red ≥100ms</span></h2>
  $($sparkSections -join "")
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/08-latency-baseline-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
