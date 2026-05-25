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

# ── System Profiler (primary source) ──────────────────────────────────────
Write-Host "Reading Wi-Fi status via system_profiler..." -ForegroundColor Yellow
$profilerRaw = & system_profiler SPAirPortDataType 2>/dev/null
$profilerText = $profilerRaw -join "`n"

function Parse-Profiler {
    param([string]$text, [string]$key)
    $match = [regex]::Match($text, "$key\s*:\s*(.+)")
    if ($match.Success) { $match.Groups[1].Value.Trim() } else { "—" }
}

$ssid       = Parse-Profiler $profilerText "Current Network Information"
# SSID is the header of the network block — extract differently
$ssidMatch  = [regex]::Match($profilerText, "Current Network Information:\s*\n\s+([^\n:]+):")
$ssid       = if ($ssidMatch.Success) { $ssidMatch.Groups[1].Value.Trim() } else { "—" }

$phyMode    = Parse-Profiler $profilerText "PHY Mode"
$channel    = Parse-Profiler $profilerText "Channel"
$country    = Parse-Profiler $profilerText "Country Code"
$netType    = Parse-Profiler $profilerText "Network Type"
$security   = Parse-Profiler $profilerText "Security"
$status     = Parse-Profiler $profilerText "Status"
$macAddr    = Parse-Profiler $profilerText "MAC Address"
$fwVersion  = Parse-Profiler $profilerText "Firmware Version"
$cardType   = Parse-Profiler $profilerText "Card Type"
$wakeon     = Parse-Profiler $profilerText "Wake On Wireless"
$airdrop    = Parse-Profiler $profilerText "AirDrop"

# Band from channel
$band = "—"
if ($channel -match '\d+') {
    $ch = [int]([regex]::Match($channel, '\d+').Value)
    $band = if ($ch -le 14) { "2.4 GHz" } else { "5 GHz / 6 GHz" }
}

# ── Airport utility (fallback for RSSI) ───────────────────────────────────
Write-Host "Checking signal strength..." -ForegroundColor Yellow
$airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
$rssi  = "—"
$noise = "—"
$txRate = "—"
$linkAuth = "—"

if (Test-Path $airportPath) {
    $airportInfo = & $airportPath -I 2>/dev/null
    foreach ($line in $airportInfo) {
        if ($line -match "agrCtlRSSI\s*:\s*(-?\d+)")  { $rssi    = $Matches[1] }
        if ($line -match "agrCtlNoise\s*:\s*(-?\d+)") { $noise   = $Matches[1] }
        if ($line -match "lastTxRate\s*:\s*(\d+)")    { $txRate  = $Matches[1] }
        if ($line -match "link auth\s*:\s*(.+)")       { $linkAuth = $Matches[1].Trim() }
        if ($line -match "SSID\s*:\s*(.+)" -and $ssid -eq "—") { $ssid = $Matches[1].Trim() }
    }
}

# If security not found, use linkAuth
if ($security -eq "—" -and $linkAuth -ne "—") { $security = $linkAuth }

# Signal quality
$signalQuality = "—"
$signalColor   = "#94a3b8"
if ($rssi -ne "—" -and $rssi -match '-?\d+') {
    $rssiVal = [int]$rssi
    if     ($rssiVal -ge -50) { $signalQuality = "Excellent"; $signalColor = "#45d48a" }
    elseif ($rssiVal -ge -60) { $signalQuality = "Good";      $signalColor = "#45d48a" }
    elseif ($rssiVal -ge -70) { $signalQuality = "Fair";      $signalColor = "#f2c86d" }
    else                      { $signalQuality = "Poor";      $signalColor = "#ff6b6b" }
} elseif ($status -eq "Connected") {
    $signalQuality = "Connected"; $signalColor = "#45d48a"
}

# SNR
$snr = "—"
if ($rssi -match '-?\d+' -and $noise -match '-?\d+') {
    $snr = "$([int]$rssi - [int]$noise) dB"
}

# ── Local IP ───────────────────────────────────────────────────────────────
$ipAddr = & ipconfig getifaddr en0 2>/dev/null
if (-not $ipAddr) { $ipAddr = & ipconfig getifaddr en1 2>/dev/null }
if (-not $ipAddr) { $ipAddr = "Not assigned" }

# ── Supported Channels ─────────────────────────────────────────────────────
$suppChannels = Parse-Profiler $profilerText "Supported Channels"
$channels2g = ($profilerText | Select-String -Pattern '\d+ \(2GHz\)' -AllMatches).Matches.Count
$channels5g = ($profilerText | Select-String -Pattern '\d+ \(5GHz\)' -AllMatches).Matches.Count

# ── Console Summary ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Wi-Fi Diagnostics Complete                " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "SSID           : $ssid"            -ForegroundColor Cyan
Write-Host "Status         : $status"           -ForegroundColor $(if ($status -eq "Connected") { "Green" } else { "Yellow" })
Write-Host "PHY Mode       : $phyMode"          -ForegroundColor Cyan
Write-Host "Channel / Band : $channel / $band"  -ForegroundColor Cyan
Write-Host "Signal (RSSI)  : $(if ($rssi -ne '—') { "$rssi dBm ($signalQuality)" } else { $signalQuality })" -ForegroundColor Cyan
Write-Host "Tx Rate        : $(if ($txRate -ne '—') { "$txRate Mbps" } else { '—' })" -ForegroundColor Cyan
Write-Host "Security       : $security"         -ForegroundColor Cyan
Write-Host "MAC Address    : $macAddr"          -ForegroundColor Cyan
Write-Host "Local IP       : $ipAddr"           -ForegroundColor Cyan
Write-Host "2.4 GHz Channels : $channels2g"    -ForegroundColor Gray
Write-Host "5 GHz Channels   : $channels5g"    -ForegroundColor Gray

# ── HTML Report ────────────────────────────────────────────────────────────
$overallBadgeColor = $signalColor
$overallLabel      = if ($status -eq "Connected") { $signalQuality } else { "NOT CONNECTED" }

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
  .stat-value { font-size: 1.5rem; font-weight: 700; color: #0078d4; }
  .stat-label { font-size: 0.8rem; color: #64748b; margin-top: 4px; }
  .section { background: white; border-radius: 10px; padding: 22px; box-shadow: 0 1px 4px rgba(0,0,0,.07); margin-bottom: 20px; }
  .section h2 { font-size: 1rem; color: #0078d4; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px; margin-bottom: 16px; }
  .kv { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  .kv-row { display: flex; gap: 10px; font-size: 0.875rem; padding: 6px 0; border-bottom: 1px solid #f1f5f9; }
  .kv-label { font-weight: 600; min-width: 150px; color: #475569; }
  .kv-value { color: #1e293b; }
  .signal-badge { display: inline-block; padding: 5px 16px; border-radius: 20px; font-size: 0.9rem; font-weight: 700; color: white; background: $overallBadgeColor; }
  .channels-bar { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; }
  .ch-tag { background: #eff6ff; border: 1px solid #bfdbfe; color: #1d4ed8; border-radius: 6px; padding: 2px 8px; font-size: 0.75rem; font-family: monospace; }
  .ch-tag.five { background: #f0fdf4; border-color: #86efac; color: #16a34a; }
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
  <div class="stat-card"><div class="stat-value">$phyMode</div><div class="stat-label">PHY Mode</div></div>
  <div class="stat-card"><div class="stat-value">$band</div><div class="stat-label">Frequency Band</div></div>
  <div class="stat-card"><div class="stat-value">Ch $channel</div><div class="stat-label">Channel</div></div>
</div>

<div class="section">
  <h2>Connection Status &nbsp; <span class="signal-badge">$overallLabel</span></h2>
  <div class="kv" style="margin-top:12px">
    <div class="kv-row"><span class="kv-label">SSID</span><span class="kv-value">$ssid</span></div>
    <div class="kv-row"><span class="kv-label">Status</span><span class="kv-value">$status</span></div>
    <div class="kv-row"><span class="kv-label">PHY Mode</span><span class="kv-value">$phyMode</span></div>
    <div class="kv-row"><span class="kv-label">Channel</span><span class="kv-value">$channel</span></div>
    <div class="kv-row"><span class="kv-label">Frequency Band</span><span class="kv-value">$band</span></div>
    <div class="kv-row"><span class="kv-label">Signal (RSSI)</span><span class="kv-value">$(if ($rssi -ne '—') { "$rssi dBm — $signalQuality" } else { $signalQuality })</span></div>
    <div class="kv-row"><span class="kv-label">Noise Floor</span><span class="kv-value">$(if ($noise -ne '—') { "$noise dBm" } else { '—' })</span></div>
    <div class="kv-row"><span class="kv-label">SNR</span><span class="kv-value">$snr</span></div>
    <div class="kv-row"><span class="kv-label">Tx Rate</span><span class="kv-value">$(if ($txRate -ne '—') { "$txRate Mbps" } else { '—' })</span></div>
    <div class="kv-row"><span class="kv-label">Security</span><span class="kv-value">$security</span></div>
    <div class="kv-row"><span class="kv-label">Network Type</span><span class="kv-value">$netType</span></div>
    <div class="kv-row"><span class="kv-label">Country Code</span><span class="kv-value">$country</span></div>
    <div class="kv-row"><span class="kv-label">MAC Address</span><span class="kv-value">$macAddr</span></div>
    <div class="kv-row"><span class="kv-label">Local IP</span><span class="kv-value">$ipAddr</span></div>
    <div class="kv-row"><span class="kv-label">Card Type</span><span class="kv-value">$cardType</span></div>
    <div class="kv-row"><span class="kv-label">Wake On Wireless</span><span class="kv-value">$wakeon</span></div>
    <div class="kv-row"><span class="kv-label">AirDrop</span><span class="kv-value">$airdrop</span></div>
    <div class="kv-row"><span class="kv-label">2.4 GHz Channels</span><span class="kv-value">$channels2g supported</span></div>
    <div class="kv-row"><span class="kv-label">5 GHz Channels</span><span class="kv-value">$channels5g supported</span></div>
  </div>
</div>

<div class="section">
  <h2>Firmware</h2>
  <p style="font-size:0.82rem;color:#475569;font-family:monospace">$fwVersion</p>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/04-wifi-diagnostics-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
