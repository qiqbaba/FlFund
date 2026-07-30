$headers = @{
    "User-Agent" = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"
    "Referer" = "https://fund.eastmoney.com/"
}

# 1. 尝试不同的移动端API
Write-Host "=== 1. FundMobApi (移动端估值排行) ==="
$url1 = "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=5&canbuy=0"
$r1 = Invoke-WebRequest -Uri $url1 -Headers $headers -UseBasicParsing
Write-Host $r1.Content

# 2. 不同的type参数
Write-Host "=== 2. type=3 (ETF) ==="
$url2 = "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=3&sort=3&orderType=desc&pageIndex=1&pageSize=5"
$r2 = Invoke-WebRequest -Uri $url2 -Headers $headers -UseBasicParsing
Write-Host $r2.Content

# 3. 试试不同的API路径
Write-Host "=== 3. api.fund 手机版 ==="
$url3 = "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=5"
$r3 = Invoke-WebRequest -Uri $url3 -Headers $headers -UseBasicParsing
Write-Host $r3.Content

# 4. 实时估值排行 (另一个端点)
Write-Host "=== 4. FundRankInfo ==="
$url4 = "https://api.fund.eastmoney.com/FundMobApi/FundRankInfo?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=5"
$r4 = Invoke-WebRequest -Uri $url4 -Headers $headers -UseBasicParsing
Write-Host $r4.Content

# 5. 试试排列组合不同的参数
Write-Host "=== 5. type=5 sort=1 (按估值) ==="
$url5 = "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=1&orderType=desc&pageIndex=1&pageSize=5"
$r5 = Invoke-WebRequest -Uri $url5 -Headers $headers -UseBasicParsing
Write-Host $r5.Content

# 6. 试试 v320 的 FundMobApi
Write-Host "=== 6. FundMobApi PGTop10 ==="
$url6 = "https://fundmobapi.eastmoney.com/FundMobApi/PGTop10?pageIndex=1&pageSize=5"
$r6 = Invoke-WebRequest -Uri $url6 -Headers $headers -UseBasicParsing
Write-Host $r6.Content

# 7. 试试 FundMobApi 的 GetFundGZList 带 version
Write-Host "=== 7. FundMobApi GetFundGZList v320 ==="
$url7 = "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=5&canbuy=0&version=6.4.5"
$r7 = Invoke-WebRequest -Uri $url7 -Headers $headers -UseBasicParsing
Write-Host $r7.Content

# 8. 试试带有更多参数的 GetFundGZList
Write-Host "=== 8. type=5 带完整参数 ==="
$url8 = "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=5&canbuy=0&isBuy=0&isSale=0"
$r8 = Invoke-WebRequest -Uri $url8 -Headers $headers -UseBasicParsing
Write-Host $r8.Content