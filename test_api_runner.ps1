param (
    [string]$Url,
    [string]$Desc,
    [hashtable]$ExtraHeaders = @{}
)

$baseHeaders = @{
    "User-Agent" = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148"
    "Referer" = "https://fund.eastmoney.com/"
}
foreach ($k in $ExtraHeaders.Keys) { $baseHeaders[$k] = $ExtraHeaders[$k] }

try {
    $r = Invoke-WebRequest -Uri $Url -Headers $baseHeaders -UseBasicParsing -TimeoutSec 15
    $content = $r.Content
    if ($content.Length -gt 300) { $content = $content.Substring(0, 300) + "..." }
    Write-Host "$Desc => $content"
} catch {
    Write-Host "$Desc => ERROR: $($_.Exception.Message)"
}