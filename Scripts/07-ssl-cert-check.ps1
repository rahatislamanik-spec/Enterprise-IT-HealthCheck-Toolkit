# Enterprise IT Network Diagnostics Toolkit
# Script 07: SSL/TLS Certificate Check
# Author: Md Rahat Islam Anik
# Platform: macOS (PowerShell 7+)
# Description: Checks SSL/TLS certificates for key domains — expiry dates,
#   issuer, subject, protocol version — flags certificates expiring within 30 days.

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Enterprise IT Network Diagnostics Toolkit " -ForegroundColor Cyan
Write-Host "  Script 07 — SSL/TLS Certificate Check     " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Domains to Check ───────────────────────────────────────────────────────
$domains = @(
    "google.com",
    "microsoft.com",
    "github.com",
    "office365.com",
    "cloudflare.com",
    "apple.com",
    "linkedin.com",
    "amazon.com"
)

# ── Certificate Check Function ─────────────────────────────────────────────
function Get-SSLCertInfo {
    param([string]$Domain, [int]$Port = 443, [int]$TimeoutMs = 5000)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $task = $tcpClient.ConnectAsync($Domain, $Port)
        if (-not $task.Wait($TimeoutMs)) {
            $tcpClient.Close()
            return [PSCustomObject]@{ Domain = $Domain; Status = "TIMEOUT"; Error = "Connection timed out" }
        }

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(), $false,
            { param($s,$c,$ch,$e) $true }  # accept any cert for inspection
        )

        $sslStream.AuthenticateAsClient($Domain)
        $cert    = $sslStream.RemoteCertificate
        $cert2   = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)

        $subject  = $cert2.Subject
        $issuer   = $cert2.Issuer
        $expiry   = $cert2.NotAfter
        $validFrom = $cert2.NotBefore
        $daysLeft = [math]::Round(($expiry - (Get-Date)).TotalDays)
        $thumbprint = $cert2.Thumbprint
        $protocol = $sslStream.SslProtocol.ToString()
        $keyAlg   = $cert2.SignatureAlgorithm.FriendlyName

        $sslStream.Close()
        $tcpClient.Close()

        $certStatus = if ($daysLeft -lt 0) {
            "EXPIRED"
        } elseif ($daysLeft -le 14) {
            "CRITICAL"
        } elseif ($daysLeft -le 30) {
            "WARNING"
        } else {
            "VALID"
        }

        return [PSCustomObject]@{
            Domain      = $Domain
            Status      = $certStatus
            DaysLeft    = $daysLeft
            Expiry      = $expiry.ToString("yyyy-MM-dd")
            ValidFrom   = $validFrom.ToString("yyyy-MM-dd")
            Subject     = $subject
            Issuer      = $issuer
            Protocol    = $protocol
            KeyAlg      = $keyAlg
            Thumbprint  = $thumbprint.Substring(0, 16) + "..."
            Error       = ""
        }
    } catch {
        return [PSCustomObject]@{
            Domain     = $Domain
            Status     = "ERROR"
            DaysLeft   = "—"
            Expiry     = "—"
            ValidFrom  = "—"
            Subject    = "—"
            Issuer     = "—"
            Protocol   = "—"
            KeyAlg     = "—"
            Thumbprint = "—"
            Error      = $_.Exception.Message
        }
    }
}

# ── Run Checks ─────────────────────────────────────────────────────────────
Write-Host "Checking SSL/TLS certificates..." -ForegroundColor Yellow
$results = @()

foreach ($domain in $domains) {
    Write-Host "  $domain..." -ForegroundColor Gray -NoNewline
    $info = Get-SSLCertInfo -Domain $domain
    $results += $info
    $statusDisplay = switch ($info.Status) {
        "VALID"    { " VALID ($($info.DaysLeft)d)" }
        "WARNING"  { " WARNING ($($info.DaysLeft)d)" }
        "CRITICAL" { " CRITICAL ($($info.DaysLeft)d)" }
        "EXPIRED"  { " EXPIRED" }
        default    { " $($info.Status)" }
    }
    $color = switch ($info.Status) {
        "VALID"    { "Green" }
        "WARNING"  { "Yellow" }
        "CRITICAL" { "Red" }
        "EXPIRED"  { "Red" }
        default    { "DarkGray" }
    }
    Write-Host $statusDisplay -ForegroundColor $color
}

# ── Summary ────────────────────────────────────────────────────────────────
$valid    = ($results | Where-Object { $_.Status -eq "VALID"    }).Count
$warning  = ($results | Where-Object { $_.Status -eq "WARNING"  }).Count
$critical = ($results | Where-Object { $_.Status -eq "CRITICAL" }).Count
$expired  = ($results | Where-Object { $_.Status -eq "EXPIRED"  }).Count
$errors   = ($results | Where-Object { $_.Status -eq "ERROR"    }).Count
$total    = $results.Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " SSL/TLS Check Complete                    " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "Total    : $total"    -ForegroundColor Cyan
Write-Host "Valid    : $valid"    -ForegroundColor Green
Write-Host "Warning  : $warning"  -ForegroundColor Yellow
Write-Host "Critical : $critical" -ForegroundColor Red
Write-Host "Expired  : $expired"  -ForegroundColor Red
Write-Host "Errors   : $errors"   -ForegroundColor Gray

# ── HTML Table ─────────────────────────────────────────────────────────────
$tableRows = foreach ($r in $results) {
    $sc = switch ($r.Status) {
        "VALID"    { "#45d48a" }
        "WARNING"  { "#f2c86d" }
        "CRITICAL" { "#ff6b6b" }
        "EXPIRED"  { "#dc2626" }
        default    { "#94a3b8" }
    }
    $daysDisplay = if ($r.DaysLeft -is [int]) { "$($r.DaysLeft) days" } else { $r.DaysLeft }
    "<tr>
      <td><strong>$($r.Domain)</strong></td>
      <td><span class='badge' style='background:$sc'>$($r.Status)</span></td>
      <td>$daysDisplay</td>
      <td>$($r.Expiry)</td>
      <td>$($r.ValidFrom)</td>
      <td style='font-size:0.8rem'>$($r.Protocol)</td>
      <td style='font-size:0.78rem;color:#64748b'>$(($r.Issuer -replace 'O=','') -replace 'CN=','')</td>
    </tr>"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$report = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<title>SSL Certificate Check — Enterprise IT Network Diagnostics Toolkit</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', Arial, sans-serif; background: #f0f4f8; color: #1e293b; padding: 24px; }
  .header { background: linear-gradient(135deg, #0078d4, #005a9e); color: white; padding: 26px 30px; border-radius: 12px; margin-bottom: 24px; }
  .header h1 { font-size: 1.4rem; margin-bottom: 4px; }
  .header p  { opacity: 0.85; font-size: 0.875rem; }
  .script-tag { display: inline-block; background: rgba(255,255,255,0.2); border-radius: 20px; padding: 2px 12px; font-size: 0.78rem; margin-bottom: 10px; }
  .summary { display: grid; grid-template-columns: repeat(5, 1fr); gap: 16px; margin-bottom: 24px; }
  .stat-card { background: white; border-radius: 10px; padding: 18px 20px; box-shadow: 0 1px 4px rgba(0,0,0,.07); text-align: center; }
  .stat-value { font-size: 2rem; font-weight: 700; color: #0078d4; }
  .stat-label { font-size: 0.8rem; color: #64748b; margin-top: 4px; }
  .section { background: white; border-radius: 10px; padding: 22px; box-shadow: 0 1px 4px rgba(0,0,0,.07); margin-bottom: 20px; }
  .section h2 { font-size: 1rem; color: #0078d4; border-bottom: 2px solid #e2e8f0; padding-bottom: 10px; margin-bottom: 16px; }
  table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  th { background: #f8fafc; color: #475569; font-weight: 600; padding: 10px 14px; text-align: left; border-bottom: 2px solid #e2e8f0; }
  td { padding: 10px 14px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78rem; font-weight: 600; color: white; }
  .legend { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 16px; font-size: 0.8rem; }
  .legend-item { display: flex; align-items: center; gap: 6px; }
  .dot { width: 10px; height: 10px; border-radius: 50%; }
  .footer { text-align: center; font-size: 0.75rem; color: #94a3b8; margin-top: 24px; }
</style>
</head>
<body>

<div class="header">
  <div class="script-tag">Script 07 of 08</div>
  <h1>SSL/TLS Certificate Check Report</h1>
  <p>Generated: $timestamp &nbsp;|&nbsp; Author: Md Rahat Islam Anik &nbsp;|&nbsp; Enterprise IT Network Diagnostics Toolkit</p>
</div>

<div class="summary">
  <div class="stat-card"><div class="stat-value">$total</div><div class="stat-label">Domains Checked</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#45d48a">$valid</div><div class="stat-label">Valid</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#f2c86d">$warning</div><div class="stat-label">Expiring Soon</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#ff6b6b">$critical</div><div class="stat-label">Critical</div></div>
  <div class="stat-card"><div class="stat-value" style="color:#dc2626">$expired</div><div class="stat-label">Expired</div></div>
</div>

<div class="section">
  <h2>Certificate Results</h2>
  <div class="legend">
    <div class="legend-item"><div class="dot" style="background:#45d48a"></div> Valid (&gt;30 days)</div>
    <div class="legend-item"><div class="dot" style="background:#f2c86d"></div> Warning (&lt;30 days)</div>
    <div class="legend-item"><div class="dot" style="background:#ff6b6b"></div> Critical (&lt;14 days)</div>
    <div class="legend-item"><div class="dot" style="background:#dc2626"></div> Expired</div>
    <div class="legend-item"><div class="dot" style="background:#94a3b8"></div> Error / Unreachable</div>
  </div>
  <table>
    <thead><tr><th>Domain</th><th>Status</th><th>Days Remaining</th><th>Expiry Date</th><th>Valid From</th><th>Protocol</th><th>Issuer</th></tr></thead>
    <tbody>$($tableRows -join "")</tbody>
  </table>
</div>

<div class="footer">Enterprise IT Network Diagnostics Toolkit &nbsp;·&nbsp; Md Rahat Islam Anik &nbsp;·&nbsp; $timestamp</div>
</body>
</html>
"@

if (!(Test-Path "./Reports")) { New-Item -ItemType Directory -Path "./Reports" | Out-Null }
$reportPath = "./Reports/07-ssl-cert-report.html"
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host ""
Write-Host "Report saved to: $reportPath" -ForegroundColor Green
