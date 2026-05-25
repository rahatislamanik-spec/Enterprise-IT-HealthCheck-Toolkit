# Enterprise IT Network Diagnostics Toolkit
# Script 04: Wi-Fi Diagnostics
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Captures Wi-Fi adapter details, SSID, signal strength, channel,
#   security type, and connection quality — exports a clean HTML report.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 04 — Wi-Fi Diagnostics             " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Airport Utility Path ───────────────────────────────────────────────────
$airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

# ── Current Wi-Fi Info ─────────────────────────────────────────────────────
Write-Host "Reading Wi-Fi status..." -ForegroundColor Yellow

$airportInfo = if (Test-Path $airportPath) {
    & $airportPath -I 2>/dev/null
} else { @() }

function Parse-Airport {
    param([string[]]$lines, [string]$key)
    $line = $lines | Where-Object { $_ -match "^\s+$key\s*:" }
    if ($line) { ($line -split ":")[1].Trim() } else { "—" }
}

$ssid        = Parse-Airport $airportInfo "SSID"
$bssid       = Parse-Airport $airportInfo "BSSID"
$rssi        = Parse-Airport $airportInfo "agrCtlRSSI"
$noise       = Parse-Airport $airportInfo "agrCtlNoise"
$channel     = Parse-Airport $airportInfo "channel"
$txRate      = Parse-Airport $airportInfo "lastTxRate"
$security    = Parse-Airport $airportInfo "link auth"
$state       = Parse-Airport $airportInfo "state"

# Signal quality from RSSI (dBm)
$signalQuality = "—"
$signalColor   = "#94a3b8"
if ($rssi -ne "—" -and $rssi -match '-?\d+') {
    $rssiVal = [int]$rssi
    if ($rssiVal -ge -50) {
        $signalQuality = "Excellent"; $signalColor = "#45d48a"
    } elseif ($rssiVal -ge -60) {
        $signalQuality = "Good";      $signalColor = "#45d48a"
    } elseif ($rssiVal -ge -70) {
        $signalQuality = "Fair";      $signalColor = "#f2c86d"
    } else {
        $signalQuality = "Poor";      $signalColor = "#ff6b6b"
    }
}

# Band from channel
$band = "—"
if ($channel -match '\d+') {
    $ch = [int]([regex]::Match($channel, '\d+').Value)
    $band = if ($ch -le 14) { "2.4 GHz" } else { "5 GHz" }
}

# SNR
$snr = "—"
if ($rssi -match '-?\d+' -and $noise -match '-?\d+') {
    $snr = "$([int]$rssi - [int]$noise) dB"
}

# ── Available Networks ─────────────────────────────────────────────────────
Write-Host "Scanning for available networks..." -ForegroundColor Yellow
$scanRaw = if (Test-Path $airportPath) {
    & $airportPath -s 2>/dev/null
} else { @() }

$networks = @()
if ($scanRaw) {
    $scanLines = $scanRaw | Select-Object -Skip 1  # skip header
    foreach ($line in $scanLines) {
        if ($line -match '^\s+(.+?)\s+([0-9a-fA-F:]{17})\s+(-\d+)\s+(\d+),') {
            $networks += [PSCustomObject]@{
                SSID     = $Matches[1].Trim()
                BSSID    = $Matches[2]
                RSSI     = $Matches[3]
                Channel  = $Matches[4]
            }
        }
    }
}

# ── Network Interface Info ─────────────────────────────────────────────────
Write-Host "Reading interface details..." -ForegroundColor Yellow
$ifRaw = & networksetup -listallhardwareports 2>/dev/null
$ipAddr = & ipconfig getifaddr en0 2>/dev/null

# ── Console Summary ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Wi-Fi Diagnostics Complete                " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "SSID           : $ssid"           -ForegroundColor Cyan
Write-Host "Signal         : $rssi dBm ($signalQuality)" -ForegroundColor Cyan
Write-Host "Channel / Band : $channel / $band" -ForegroundColor Cyan
Write-Host "Tx Rate        : $txRate Mbps"     -ForegroundColor Cyan
Write-Host "Security       : $security"        -ForegroundColor Cyan
Write-Host "Local IP       : $(if ($ipAddr) { $ipAddr } else { 'Not assigned' })" -ForegroundColor Cyan
Write-Host "Networks Found : $($networks.Count)" -ForegroundColor Cyan

# ── HTML Networks Table ────────────────────────────────────────────────────
$netRows = foreach ($n in ($networks | Sort-Object { [int]$_.RSSI } -Descending | Select-Object -First 15)) {
    $nRssi = [int]$n.RSSI
    $nColor = if ($nRssi -ge -60) { "#45d48a" } elseif ($nRssi -ge -70) { "#f2c86d" } else { "#ff6b6b" }
    $nBand  = if ([int]$n.Channel -le 14) { "2.4 GHz" } else { "5 GHz" }
    $isCurrent = if ($n.SSID -eq $ssid) { " ★" } else { "" }
    "<tr>
      <td><strong>$($n.SSID)$isCurrent</strong></td>
      <td>$($n.BSSID)</td>
      <td><span style='color:$nColor;font-weight:600'>$($n.RSSI) dBm</span></td>
      <td>$($n.Channel)</td>
      <td>$nBand</td>
    </tr>"
}

$overallStatus = if ($ssid -ne "—" -and $signalQuality -ne "—") { $signalQuality } else { "NOT CONNECTED" }
$headerColor   = $signalColor

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>Wi-Fi Diagnostics — Enterprise IT Network Diagnostics Toolkit</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f4f8; color: #1e293b; padding: 24px; }
  .header { background: linear-gradient(135deg, #0078d4, #005a9e); color: white; padding: 26px 30px; border-radius: 12px; margin-bottom: 24px; }
  .header h1 { font-size: 1.4rem; margin-bottom: 4px; }
  .header p  { opacity: 0.85; font-size: 0.875rem; }
  .script-tag { display: inline-block; background: rgba(255,255,255,0.2); border-radius: 20px; padding: 2px 12px; font-size: 0.78rem; margin-bottom: 10px; }
  .summary { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-bottom: 24px; }
  .stat-card { background: white; border-radius: 10px; padding: 18px 20px; box-shadow: 0 1px 4px rgba(0,0,0,.07); text-align: center; }
  .stat-value { font-size: 1.6rem; font-weight: 700; color: #0078d4; }
  .stat-label { font-size: 0.8rem; color: #64748b; margin-top: 4px; }
  .section { background: white; border-radius: 10px; padding: 22px; box-shadow: 0 1px 4px rgba(0,0,0,.07); margin-bottom: 20px; }
  .section h2 { font-size: 1rem; color: #0078d4; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px; margin-bottom: 16px; }
  .kv { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .kv-row { display: flex; gap: 10px; font-size: 0.875rem; }
  .kv-label { font-weight: 600; min-width: 140px; color: #475569; }
  .kv-value { color: #1e293b; }
  .signal-badge { display: inline-block; padding: 5px 16px; border-radius: 20px; font-size: 0.9rem; font-weight: 700; color: white; background: $signalColor; }
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th { background: #f8fafc; color: #475569; font-weight: 600; padding: 10px 14px; text-align: left; border-bottom: 2px solid #e2e8f0; }
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 04 of 08</div>
  <h1>Wi-Fi Diagnostics Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$ssid</div><div class="stat-label">Connected SSID</div></div>
  <div class="stat-card"><div class="stat-value">$rssi dBm</div><div class="stat-label">Signal Strength</div></div>
  <div class="stat-card"><div class="stat-value">$band</div><div class="stat-label">Frequency Band</div></div>
  <div class="stat-card"><div class="stat-value">$txRate Mbps</div><div class="stat-label">Tx Rate</div></div>
</div>

<div class="section">
  <h2>Connection Details &nbsp; <span class="signal-badge">$overallStatus</span></h2>
  <div class="kv" style="margin-top:12px">
    <div class="kv-row"><span class="kv-label">SSID</span><span class="kv-value">$ssid</span></div>
    <div class="kv-row"><span class="kv-label">BSSID (AP MAC)</span><span class="kv-value">$bssid</span></div>
    <div class="kv-row"><span class="kv-label">Signal (RSSI)</span><span class="kv-value">$rssi dBm</span></div>
    <div class="kv-row"><span class="kv-label">Noise Floor</span><span class="kv-value">$noise dBm</span></div>
    <div class="kv-row"><span class="kv-label">SNR</span><span class="kv-value">$snr</span></div>
    <div class="kv-row"><span class="kv-label">Channel</span><span class="kv-value">$channel</span></div>
    <div class="kv-row"><span class="kv-label">Frequency Band</span><span class="kv-value">$band</span></div>
    <div class="kv-row"><span class="kv-label">Tx Rate</span><span class="kv-value">$txRate Mbps</span></div>
    <div class="kv-row"><span class="kv-label">Security</span><span class="kv-value">$security</span></div>
    <div class="kv-row"><span class="kv-label">State</span><span class="kv-value">$state</span></div>
    <div class="kv-row"><span class="kv-label">Local IP</span><span class="kv-value">$(if ($ipAddr) { $ipAddr } else { 'Not assigned' })</span></div>
    <div class="kv-row"><span class="kv-label">Signal Quality</span><span class="kv-value" style="color:$signalColor;font-weight:600">$signalQuality</span></div>
  </div>
</div>

$(if ($networks.Count -gt 0) {
"<div class='section'>
  <h2>Nearby Networks ($($networks.Count) detected — top 15 by signal) &nbsp; <span style='font-size:0.8rem;color:#64748b'>★ = current network</span></h2>
  <table>
    <thead><tr><th>SSID</th><th>BSSID</th><th>Signal</th><th>Channel</th><th>Band</th></tr></thead>
    <tbody>$($netRows -join '')</tbody>
  </table>
</div>"
})

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/04-wifi-diagnostics-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
