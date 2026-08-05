# Auto-detect IP location and update android/gradle/wrapper/gradle-wrapper.properties
$projectDir = Split-Path -Parent $PSScriptRoot
$gradleProp = Join-Path $projectDir "android\gradle\wrapper\gradle-wrapper.properties"

if (-not (Test-Path $gradleProp)) {
    Write-Host "Warning: $gradleProp not found."
    exit 0
}

Write-Host "Auto-detecting IP location for Gradle distribution..."

$countryCode = ""

# Primary API
try {
    $res = Invoke-RestMethod -Uri "http://ip-api.com/json" -TimeoutSec 3 -ErrorAction Stop
    if ($res -and $res.countryCode) {
        $countryCode = $res.countryCode
    }
} catch {}

# Fallback API if primary failed
if (-not $countryCode) {
    try {
        $res = Invoke-RestMethod -Uri "https://ipinfo.io/json" -TimeoutSec 3 -ErrorAction Stop
        if ($res -and $res.country) {
            $countryCode = $res.country
        }
    } catch {}
}

$officialUrl = "https\://services.gradle.org/distributions/gradle-8.11.1-all.zip"
$domesticUrl = "https\://mirrors.cloud.tencent.com/gradle/gradle-8.11.1-all.zip"

if ($countryCode -eq "CN") {
    Write-Host "Detected domestic IP (CN). Using Tencent Cloud Gradle mirror."
    $targetUrl = $domesticUrl
} elseif ($countryCode) {
    Write-Host "Detected overseas IP ($countryCode). Using official Gradle distribution."
    $targetUrl = $officialUrl
} else {
    Write-Host "Could not determine IP location. Defaulting to official Gradle distribution."
    $targetUrl = $officialUrl
}

$content = Get-Content $gradleProp -Raw
$updatedContent = $content -replace 'distributionUrl=.*', "distributionUrl=$targetUrl"

if ($content -ne $updatedContent) {
    Set-Content -Path $gradleProp -Value $updatedContent -NoNewline
    Write-Host "Updated distributionUrl in $gradleProp -> $targetUrl"
} else {
    Write-Host "distributionUrl is already up to date ($targetUrl)."
}
