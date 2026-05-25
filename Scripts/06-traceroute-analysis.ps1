# Enterprise IT Network Diagnostics Toolkit
# Script 06: Traceroute Analysis
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Traces the network path to key destinations, reports hop-by-hop
#   latency, identifies timeouts/failures — exports a clean HTML report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 06 — Traceroute Analysis           " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Targets ────────────────────────────────────────────────────────────────
$targets = @(
    [PSCustomObject]@{ Label = "Google";     Host = "google.com" }
    [PSCustomObject]@{ Label = "Microsoft";  Host = "microsoft.com" }
    [PSCustomObject]@{ Label = "Cloudflare"; Host = "1.1.1.1" }
)

# ── Parse traceroute line ──────────────────────────────────────────────────
function Parse-TracerouteLine {
    param([string]$line)
    if ($line -match '^\s*(\d+)\s+(.+)$') {
        $hop  = $Matches[1]
        $rest = $Matches[2].Trim()

        # Timeout hop
        if ($rest -match '^\*\s*\*\s*\*') {
            return [PSCustomObject]@{ Hop = $hop; Host = "* * *"; IP = "—"; RTT1 = "timeout"; RTT2 = "timeout"; RTT3 = "timeout"; Status = "TIMEOUT" }
        }

        # Parse IPs and RTTs
        $ipMatch   = [regex]::Match($rest, '\((\d+\.\d+\.\d+\.\d+)\)')
        $hostMatch = [regex]::Match($rest, '^([^\s(]+)')
        $rttAll    = [regex]::Matches($rest, '([\d.]+)\s+ms')

        $ip   = if ($ipMatch.Success)   { $ipMatch.Groups[1].Value   } else { "—" }
        $host = if ($hostMatch.Success) { $hostMatch.Groups[1].Value } else { "—" }
        $rtts = $rttAll | ForEach-Object { $_.Groups[1].Value + " ms" }
        while ($rtts.Count -lt 3) { $rtts += "—" }

        return [PSCustomObject]@{
            Hop    = $hop
            Host   = $host
            IP     = $ip
            RTT1   = $rtts[0]
            RTT2   = $rtts[1]
            RTT3   = $rtts[2]
            Status = "OK"
        }
    }
    return $null
}

# ── Run Traceroutes ────────────────────────────────────────────────────────
$allResults = @{}

foreach ($t in $targets) {
    Write-Host "Tracing route to $($t.Label) ($($t.Host))..." -ForegroundColor Yellow
    # -m 20 = max 20 hops, -q 3 = 3 probes per hop, -w 2 = 2 second timeout
    $raw  = & traceroute -m 20 -q 3 -w 2 $t.Host 2>&1
    $hops = @()

    foreach ($line in $raw) {
        if ($line -match '^\s*\d+') {
            $parsed = Parse-TracerouteLine -line $line
            if ($parsed) {
                $hops += $parsed
                $status = if ($parsed.Status -eq "TIMEOUT") { "?" } else { "✓" }
                Write-Host "  Hop $($parsed.Hop.PadLeft(2)) $status  $($parsed.Host) ($($parsed.IP))  $($parsed.RTT1)" -ForegroundColor Gray
            }
        }
    }

    $allResults[$t.Label] = [PSCustomObject]@{
        Label   = $t.Label
        Host    = $t.Host
        Hops    = $hops
        HopCount = $hops.Count
        Timeouts = ($hops | Where-Object { $_.Status -eq "TIMEOUT" }).Count
        Reached  = ($hops | Where-Object { $_.Host -match $t.Host -or $_.IP -match $t.Host }).Count -gt 0
    }
    Write-Host ""
}

# ── Summary ────────────────────────────────────────────────────────────────
Write-Host "============================================" -ForegroundColor Green
Write-Host " Traceroute Analysis Complete              " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
foreach ($label in $allResults.Keys) {
    $r = $allResults[$label]
    Write-Host "$($r.Label): $($r.HopCount) hops, $($r.Timeouts) timeouts" -ForegroundColor Cyan
}

# ── Build HTML sections ────────────────────────────────────────────────────
$sections = ""
foreach ($label in $allResults.Keys) {
    $r = $allResults[$label]
    $hopRows = foreach ($h in $r.Hops) {
        $sc = if ($h.Status -eq "TIMEOUT") { "#f2c86d" } else { "#45d48a" }
        "<tr>
          <td style='text-align:center;font-weight:600'>$($h.Hop)</td>
          <td>$($h.Host)</td>
          <td>$($h.IP)</td>
          <td><span class='badge' style='background:$sc'>$($h.Status)</span></td>
          <td>$($h.RTT1)</td>
          <td>$($h.RTT2)</td>
          <td>$($h.RTT3)</td>
        </tr>"
    }
    $timeoutBadge = if ($r.Timeouts -gt 0) { "<span class='badge' style='background:#f2c86d;margin-left:8px'>$($r.Timeouts) timeouts</span>" } else { "" }
    $sections += "
    <div class='section'>
      <h2>$($r.Label) &nbsp;<span style='font-size:0.85rem;color:#64748b;font-weight:400'>($($r.Host))</span>&nbsp; — $($r.HopCount) hops $timeoutBadge</h2>
      <table>
        <thead><tr><th>#</th><th>Hostname</th><th>IP</th><th>Status</th><th>RTT 1</th><th>RTT 2</th><th>RTT 3</th></tr></thead>
        <tbody>$($hopRows -join '')</tbody>
      </table>
    </div>"
}

$totalHops  = ($allResults.Values | Measure-Object -Property HopCount -Sum).Sum
$totalTo    = $allResults.Count
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Traceroute Analysis — Enterprise IT Network Diagnostics Toolkit</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f4f8; color: #1e293b; padding: 24px; }
  .header { background: linear-gradient(135deg, #0078d4, #005a9e); color: white; padding: 26px 30px; border-radius: 12px; margin-bottom: 24px; }
  .header h1 { font-size: 1.4rem; margin-bottom: 4px; }
  .header p  { opacity: 0.85; font-size: 0.875rem; }
  .script-tag { display: inline-block; background: rgba(255,255,255,0.2); border-radius: 20px; padding: 2px 12px; font-size: 0.78rem; margin-bottom: 10px; }
  .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
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
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 06 of 08</div>
  <h1>Traceroute Analysis Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$totalTo</div><div class="stat-label">Destinations Traced</div></div>
  <div class="stat-card"><div class="stat-value">$totalHops</div><div class="stat-label">Total Hops Recorded</div></div>
  <div class="stat-card"><div class="stat-value">20</div><div class="stat-label">Max Hops Limit</div></div>
</div>

$sections

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/06-traceroute-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
