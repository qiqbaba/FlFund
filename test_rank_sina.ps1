$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Referer" = "https://fund.eastmoney.com/data/fundranking.html"
}

# 获取200只候选池
$url = "https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=kf&ft=all&rs=&gs=0&sc=rzdf&st=desc&pi=1&pn=200&dx=1"
$r = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
$c = $r.Content
$s = $c.IndexOf("datas:[")
$e = $c.IndexOf("]", $s)
$d = $c.Substring($s, $e - $s + 1)
$json = $d.Substring(6)
$records = $json | ConvertFrom-Json
Write-Host "Total candidates: $($records.Count)"

# 取前3个代码测试新浪实时估值
$codes = @()
foreach ($rec in $records[0..2]) {
    $fields = $rec -split ','
    $codes += "fu_$($fields[0])"
}
$listStr = $codes -join ','
Write-Host "`n=== Testing Sina batch for first 3 codes ==="
$sinaUrl = "http://hq.sinajs.cn/list=$listStr"
$sinaHeaders = @{
    "Referer" = "https://finance.sina.com.cn"
}
$sinaR = Invoke-WebRequest -Uri $sinaUrl -Headers $sinaHeaders -UseBasicParsing
Write-Host $sinaR.Content