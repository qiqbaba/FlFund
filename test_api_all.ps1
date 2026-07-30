. .\test_api_runner.ps1

# =============================================
# 查找"场外基金交易日当天实时估值排行榜"API
# =============================================

# --- 东方财富/天天基金 API 系列 ---

# 1. 原失效API的不同参数组合
Test-Api -Desc "1. GetFundGZList type=5 sort=3 pageSize=200" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200&canbuy=0"
Test-Api -Desc "2. GetFundGZList type=2(股票型)" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=2&sort=3&orderType=desc&pageIndex=1&pageSize=200"
Test-Api -Desc "3. GetFundGZList type=3(混合型)" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=3&sort=3&orderType=desc&pageIndex=1&pageSize=200"
Test-Api -Desc "4. GetFundGZList type=4(债券型)" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=4&sort=3&orderType=desc&pageIndex=1&pageSize=200"
Test-Api -Desc "5. GetFundGZList type=6(QDII)" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=6&sort=3&orderType=desc&pageIndex=1&pageSize=200"
Test-Api -Desc "6. GetFundGZList type=0(全部)" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=0&sort=3&orderType=desc&pageIndex=1&pageSize=200"

# 7. 使用移动端Referer
Test-Api -Desc "7. GetFundGZList 移动端Referer" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200" -ExtraHeaders @{"Referer"="https://m.fund.eastmoney.com/"}

# 8. FundMobApi 路径
Test-Api -Desc "8. FundMobApi GZList type=5" -Url "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}

# 9. 另一个路径: fundmobapi 不同版本
Test-Api -Desc "9. FundMobApi v640" -Url "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200&version=6.4.0" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}

# 10. 试试POST?
Test-Api -Desc "10. FundMobApi POST" -Url "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"; "Content-Type"="application/json"}

# --- 新浪财经 ---
# 11. 新浪全市场排行
Test-Api -Desc "11. Sina FundRank" -Url "https://vip.stock.finance.sina.com.cn/fund_center/api/jsonp.php/IO.XSRV2.MembershipList/js/?symbol=openfund&datalen=20&page=1&sort=nav&asc=0&type=all" -ExtraHeaders @{"Referer"="https://finance.sina.com.cn/fund/"}

# 12. 新浪基金排行
Test-Api -Desc "12. Sina fund rank" -Url "https://money.finance.sina.com.cn/fund/api/jsonp.php/IO.XSRV2.MembershipList/var%20data=/js/?symbol=openfund&datalen=20&page=1&sort=nav&asc=0&type=all" -ExtraHeaders @{"Referer"="https://money.finance.sina.com.cn/fund/"}

# --- 腾讯财经 ---
# 13. 腾讯基金排行
Test-Api -Desc "13. Tencent fund rank" -Url "https://web.ifzq.gtimg.cn/app/apple7/apple7/getFundList?type=1&sort=1&order=0&num=20&page=1" -ExtraHeaders @{"Referer"="https://web.ifzq.gtimg.cn/"}

# 14. 腾讯基金估值排行
Test-Api -Desc "14. Tencent fund gzlist" -Url "https://web.ifzq.gtimg.cn/app/apple7/apple7/getFundGZList?type=1&sort=1&order=0&num=20&page=1" -ExtraHeaders @{"Referer"="https://web.ifzq.gtimg.cn/"}

# --- 天天基金其他接口 ---
# 15. 天天基金手机版排行
Test-Api -Desc "15. 天天基金手机版排行" -Url "https://fundmobapi.eastmoney.com/FundMobApi/FundMobRank?type=2&sort=3&orderType=desc&pageIndex=1&pageSize=20" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}

# 16. 天天基金手机版估值排行
Test-Api -Desc "16. 天天基金手机版估值排行" -Url "https://fundmobapi.eastmoney.com/FundMobApi/FundMobGZRank?type=2&sort=3&orderType=desc&pageIndex=1&pageSize=20" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}

# --- 京东金融/蛋卷基金 ---
# 17. 蛋卷基金排行
Test-Api -Desc "17. Danjuan rank" -Url "https://danjuanapp.com/djapi/fund/rank?type=1&order=desc&page=1&size=20" -ExtraHeaders @{"Referer"="https://danjuanapp.com/"}

# 18. 蛋卷基金估值排行
Test-Api -Desc "18. Danjuan gzrank" -Url "https://danjuanapp.com/djapi/fund/gzrank?type=1&order=desc&page=1&size=20" -ExtraHeaders @{"Referer"="https://danjuanapp.com/"}

# 19. 蛋卷基金估值排行 v2
Test-Api -Desc "19. Danjuan fund evaluation rank" -Url "https://danjuanapp.com/djapi/fund/evaluation/rank?type=1&page=1&size=20" -ExtraHeaders @{"Referer"="https://danjuanapp.com/"}

# --- 同花顺 ---
# 20. 同花顺基金排行
Test-Api -Desc "20. 10jqka fund rank" -Url "https://fund.10jqka.com.cn/data/api/fundranking/1/1/1/desc/0/20" -ExtraHeaders @{"Referer"="https://fund.10jqka.com.cn/"}

# 21. 同花顺实时估值排行
Test-Api -Desc "21. 10jqka gzrank" -Url "https://fund.10jqka.com.cn/data/api/fundgzrank/1/1/1/desc/0/20" -ExtraHeaders @{"Referer"="https://fund.10jqka.com.cn/"}

# --- 东方财富 PC版 ---
# 22. push2.eastmoney fund rank
Test-Api -Desc "22. push2 fund rank" -Url "https://push2.eastmoney.com/api/qt/clist/get?cb=&pn=1&pz=20&po=1&np=1&fltt=2&invt=2&fid=f3&fs=m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048&fields=f2,f3,f4,f12,f14" -ExtraHeaders @{"Referer"="https://quote.eastmoney.com/"}

# --- 天天基金内部API ---
# 23. 天天基金估值排行 (内部API)
Test-Api -Desc "23. 天天基金估值排行" -Url "https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=gz&ft=all&rs=&gs=0&sc=zzzf&st=desc&pi=1&pn=200&dx=1" -ExtraHeaders @{"Referer"="https://fund.eastmoney.com/data/fundranking.html"}

# 24. 天天基金实时排行
Test-Api -Desc "24. 天天基金实时排行" -Url "https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=kf&ft=all&rs=&gs=0&sc=zzzf&st=desc&pi=1&pn=200&dx=1" -ExtraHeaders @{"Referer"="https://fund.eastmoney.com/data/fundranking.html"}

# 25. 天天基金手机版
Test-Api -Desc "25. 天天基金手机版" -Url "https://fundmobapi.eastmoney.com/FundMobApi/GetFundGZList?type=1&sort=3&orderType=desc&pageIndex=1&pageSize=20&canbuy=0" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}

# 26. 天天基金 - 改UserAgent为Android
Test-Api -Desc "26. GetFundGZList Android UA" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200" -ExtraHeaders @{"User-Agent"="Mozilla/5.0 (Linux; Android 13; SM-S9080) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36"}

# 27. 天天基金 - 改Referer为手机版
Test-Api -Desc "27. GetFundGZList 手机Referer" -Url "https://api.fund.eastmoney.com/FundGuZhi/GetFundGZList?type=5&sort=3&orderType=desc&pageIndex=1&pageSize=200" -ExtraHeaders @{"Referer"="https://fundmobapi.eastmoney.com/"}