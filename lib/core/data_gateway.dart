import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'utils/pinyin_search.dart';
import 'utils/safe_compute.dart';

String _formatFundLabel(String code, [String? name]) {
  String? fundName = name;
  if (fundName == null || fundName.trim().isEmpty || fundName == code) {
    final searchName = PinyinSearch().getNameByCode(code);
    if (searchName != code) {
      fundName = searchName;
    }
  }
  if (fundName != null && fundName.trim().isNotEmpty && fundName != code) {
    return '${fundName.trim()} ($code)';
  }
  return '($code)';
}

class FundDataGateway {
  static final FundDataGateway _instance = FundDataGateway._internal();
  factory FundDataGateway() => _instance;
  FundDataGateway._internal() {
    try {
      SecurityContext.defaultContext.allowLegacyUnsafeRenegotiation = true;
    } catch (_) {}
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15'
    };
    _dio.options.connectTimeout = const Duration(seconds: 6);
    _dio.options.receiveTimeout = const Duration(seconds: 8);
    _dio.transformer = SafeTransformer();

    // 仅对已知可信的基金数据源域名跳过 SSL 证书校验
    // 原因：部分机器由于 SSL 证书链验证失败（如 514 拦截或企业代理）导致无法访问基金 API
    // 注意：仅白名单范围内的 host 及其子域名才跳过，避免全局中间人攻击风险
    const trustedHosts = {
      '1234567.com.cn',
      'eastmoney.com',
      'fundmobapi.eastmoney.com',
      'fundf10.eastmoney.com',
      'api.fund.eastmoney.com',
      'push2his.eastmoney.com',
      'push2.eastmoney.com',
      'fund.eastmoney.com',
      'danjuanapp.com',
      'qt.gtimg.cn',
      'unitmob.1234567.com.cn',
      'sinajs.cn',
      'sina.com.cn',
    };
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.idleTimeout = const Duration(seconds: 60);
        client.findProxy = (uri) => 'DIRECT';
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          return trustedHosts
              .any((domain) => host == domain || host.endsWith('.$domain'));
        };
        return client;
      },
    );
  }

  final Dio _dio = Dio();
  Dio get dio => _dio;
  final List<String> errors = [];

  void clearErrors() {
    errors.clear();
  }

  // ---------------- 抓取历史净值 ----------------

  Future<Map<String, dynamic>?> fetchHistory(String code,
      {String? name, int pageSize = 2000}) async {
    // 1. 尝试天天基金移动端 API
    var res = await _tryEastMoneyMobile(code, pageSize, name: name);
    if (res != null) return res;

    // 2. 降级：尝试天天基金网页端 F10 接口 (HTML 正则解析)
    res = await _tryEastMoneyWeb(code, pageSize, name: name);
    return res;
  }

  Future<Map<String, dynamic>?> _tryEastMoneyMobile(
      String code, int pageSize, {String? name}) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url =
            'https://fundmobapi.eastmoney.com/FundMNewApi/FundMNHisNetList?FCODE=$code&pageIndex=1&pageSize=$pageSize&deviceid=Wap&plat=Wap&product=EFund&version=2.0.0';
        final response = await _dio.get(url);
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map && data['ErrCode'] == 0 && data['Datas'] != null) {
            final List datas = data['Datas'];
            final List<double> navs = [];
            final List<double> ljjzs = [];
            final List<String> dates = [];

            for (final item in datas) {
              final val = double.tryParse(item['DWJZ']?.toString() ?? '');
              final dt = item['FSRQ']?.toString() ?? '';
              if (val != null && dt.isNotEmpty) {
                navs.add(val);
                dates.add(dt);
                // 累计净值（LJJZ）用于重建复权净值，消除分红除息造成的净值跳空
                final ljjz = double.tryParse(item['LJJZ']?.toString() ?? '');
                ljjzs.add(ljjz != null && ljjz > 0 ? ljjz : val);
              }
            }

            if (navs.isNotEmpty) {
              return {
                'source': 'EastMoneyMobile',
                'jzrq': dates.first,
                'navs': navs,
                'ljjzs': ljjzs,
                'dates': dates,
                'latest_item': datas.first,
              };
            }
          }
        }
      } catch (e) {
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          final errStr = e is DioException
              ? (e.error?.toString() ?? e.message ?? e.toString())
              : e.toString();
          final label = _formatFundLabel(code, name);
          final msg = 'EastMoneyMobile 抓取失败 $label: $errStr';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryEastMoneyWeb(
      String code, int pageSize, {String? name}) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url =
            'https://fundf10.eastmoney.com/F10DataApi.aspx?type=lsjz&code=$code&page=1&per=$pageSize';
        final response = await _dio.get(url);
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final parsed = await safeCompute(_parseEastMoneyWebHtml, text);
          if (parsed != null) return parsed;
        }
      } catch (e) {
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          final errStr = e is DioException
              ? (e.error?.toString() ?? e.message ?? e.toString())
              : e.toString();
          final label = _formatFundLabel(code, name);
          final msg = 'EastMoneyWeb 抓取失败 $label: $errStr';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

// 独立顶层函数：用于在 compute Isolate 中解耦解析网页大文本 HTML
  Map<String, dynamic>? _parseEastMoneyWebHtml(String text) {
    final reg = RegExp(
        r"""<tr><td>(\d{4}-\d{2}-\d{2})</td><td\s+class=['"]tor\s+bold['"]>([\d.]*?)</td>""");
    final matches = reg.allMatches(text);

    final List<double> navs = [];
    final List<String> dates = [];

    for (final m in matches) {
      final dt = m.group(1);
      final val = double.tryParse(m.group(2) ?? '');
      if (dt != null && val != null) {
        dates.add(dt);
        navs.add(val);
      }
    }

    if (navs.isNotEmpty) {
      return {
        'source': 'EastMoneyWeb',
        'jzrq': dates.first,
        'navs': navs,
        'dates': dates,
        'latest_item': {
          'DWJZ': navs.first.toString(),
          'FSRQ': dates.first,
          'JZZZL': '0.00'
        }
      };
    }
    return null;
  }

  // ---------------- 抓取场内 ETF/股票 历史 K 线（用于指数数据代偿） ----------------

  /// 根据场内代码自动推断交易所前缀（沪: 1, 深: 0）
  static String _etfSecId(String code) {
    // 沪市: 5xx, 6xx 开头
    if (code.startsWith('5') || code.startsWith('6')) return '1.$code';
    // 深市: 0xx, 1xx, 3xx 开头
    return '0.$code';
  }

  /// 获取场内 ETF 的日 K 线历史数据（前复权收盘价作为净值代偿）
  Future<Map<String, dynamic>?> fetchEtfHistory(String etfCode,
      {String? name, int limit = 2000}) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final secId = _etfSecId(etfCode);
        final url = 'https://push2his.eastmoney.com/api/qt/stock/kline/get'
            '?secid=$secId'
            '&fields1=f1,f2,f3,f4,f5,f6'
            '&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
            '&klt=101' // 日 K
            '&fqt=1' // 前复权
            '&beg=0&end=20500101'
            '&lmt=$limit';

        final response = await _dio.get(url);
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map &&
              data['data'] != null &&
              data['data']['klines'] != null) {
            final List klines = data['data']['klines'];
            final List<double> navs = [];
            final List<String> dates = [];

            // klines 格式: "2021-08-05,1.000,1.023,1.030,0.998,123456,..." (日期,开,收,高,低,量,...)
            for (final line in klines) {
              final parts = (line as String).split(',');
              if (parts.length >= 3) {
                final dt = parts[0];
                final close = double.tryParse(parts[2]);
                if (close != null && dt.isNotEmpty) {
                  dates.add(dt);
                  navs.add(close);
                }
              }
            }

            if (navs.isNotEmpty) {
              // 返回格式与 fetchHistory 保持一致（由新到旧排列）
              return {
                'source': 'EtfKline',
                'jzrq': dates.last,
                'navs': navs.reversed.toList(),
                'dates': dates.reversed.toList(),
                'latest_item': {
                  'DWJZ': navs.last.toString(),
                  'FSRQ': dates.last,
                  'JZZZL': '0.00'
                },
              };
            }
          }
        }
      } catch (e) {
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          final errStr = e is DioException
              ? (e.error?.toString() ?? e.message ?? e.toString())
              : e.toString();
          final label = _formatFundLabel(etfCode, name);
          final msg = 'EtfKline 历史抓取失败 $label: $errStr';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  // ---------------- 抓取实时估值 ----------------


  // 场外到场内影子 ETF/股票 的映射表（用于防估值漂移和 QDII 纠偏）
  static const Map<String, String> _shadowEtfMap = {
    // --- 常见宽基与行业指数联接基金 -> 场内ETF影子映射 ---
    '000042': 'sh510300', // 华夏沪深300联接A -> 沪深300ETF
    '002987': 'sz159949', // 广发创业板联接A -> 创业板ETF
    '008282': 'sz159995', // 国泰半导体联接C -> 芯片ETF
    '160632': 'sh512800', // 鹏华中证800证券保险A -> 银行ETF
    '012769': 'sz159869', // 华夏游戏C -> 游戏ETF

    // --- 海外 QDII 跨境基金（利用做市商对期指+汇率的盘中双边实时定价） ---
    '050025': 'sh513100', // 易方达纳指100联接 -> 纳指ETF
    '000043': 'sh513500', // 博时标普500联接A -> 标普500ETF
    '006075': 'sh513500', // 万家标普500C -> 标普500ETF
    '000071': 'sh510900', // 华夏恒生联接 -> 恒生ETF
    '004812': 'sh510900', // 华夏恒生C -> 恒生ETF
    '162411': 'sh513350', // 华宝油气 -> 标普油气ETF
    '008281': 'sh513050', // 易方达中概互联网联接C -> 中概互联网ETF
    '006327': 'sh513050', // 易方达中概互联网联接A -> 中概互联网ETF
  };

  // 特殊子份额与主份额实时估值代理映射表
  static const Map<String, String> _valuationProxyMap = {
    '023715': '012769', // 华夏中证动漫游戏联接D -> 映射为C类(012769)抓取估值
    '015693': '160625', // 鹏华中证800证券保险C -> 映射为A类(160625)抓取估值
  };

  int get valuationSourceCount => 1;

  /// 判断基金是否属于已知无盘中实时估值的品种（如货币基金、理财基金、现金管理、同业存单等）
  static bool isNoLiveValuationFund(String code, {String? name, String? sector}) {
    String fundName = name ?? '';
    if (fundName.isEmpty || fundName == code) {
      final searchName = PinyinSearch().getNameByCode(code);
      if (searchName != code) {
        fundName = searchName;
      }
    }
    final s = sector ?? '';

    return fundName.contains('货币') ||
        fundName.contains('理财') ||
        fundName.contains('现金') ||
        fundName.contains('存单') ||
        fundName.contains('日聚宝') ||
        fundName.contains('日盈') ||
        fundName.contains('日提') ||
        s.contains('货币') ||
        s.contains('理财') ||
        s.contains('现金管理');
  }

  /// 批量获取多只基金的盘中实时估值 (基于新浪财经极速批量接口 fu_code1,fu_code2...)
  Future<Map<String, Map<String, dynamic>>> fetchValuationBatch(
      List<String> codes) async {
    final Map<String, Map<String, dynamic>> results = {};
    final validCodes = codes
        .where((c) => c.isNotEmpty && !isNoLiveValuationFund(c))
        .toSet()
        .toList();
    if (validCodes.isEmpty) return results;

    const chunkSize = 50;
    final List<List<String>> chunks = [];
    for (int i = 0; i < validCodes.length; i += chunkSize) {
      chunks.add(validCodes.sublist(
          i, i + chunkSize > validCodes.length ? validCodes.length : i + chunkSize));
    }

    final futures = chunks.map((chunk) async {
      final listParam = chunk.map((c) => 'fu_$c').join(',');
      final url = 'https://hq.sinajs.cn/list=$listParam';

      try {
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://finance.sina.com.cn',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            },
          ),
        );

        if (response.statusCode == 200) {
          final text = response.data.toString();
          final matches =
              RegExp(r'var hq_str_fu_(\d+)="([^"]+)"').allMatches(text);
          for (final m in matches) {
            final code = m.group(1)!;
            final parts = m.group(2)!.split(',');
            if (parts.length >= 8) {
              final name = parts[0];
              final gztime = parts[1];
              final dwjz = parts[2];
              final gsz = parts[3];
              final gszzl = parts[6];
              final jzrq = parts[7];

              if (double.tryParse(gsz) != null &&
                  gsz != '0.0000' &&
                  gsz.isNotEmpty) {
                final fullGztime =
                    gztime.contains('-') ? gztime : '$jzrq $gztime';
                results[code] = {
                  'source': 'SinaGzBatch',
                  'name': name,
                  'jzrq': jzrq,
                  'dwjz': dwjz,
                  'gsz': gsz,
                  'gszzl': gszzl.replaceAll('%', ''),
                  'gztime': fullGztime
                };
              }
            }
          }
        }
      } catch (e) {
        debugPrint('新浪批量估值抓取失败 chunk [${chunk.first}..]: $e');
      }
    });

    await Future.wait(futures);
    return results;
  }

  Future<Map<String, dynamic>?> fetchValuation(String code,
      {String? name,
      String? sector,
      int? preferredSourceIndex,
      bool preferTencent = false}) async {
    final int sourceIdx = preferredSourceIndex ?? (preferTencent ? 2 : 0);

    // 0. 自动过滤无盘中实时估值的基金品种（货币、理财、存单、现金管理等）
    if (isNoLiveValuationFund(code, name: name, sector: sector)) {
      final label = _formatFundLabel(code, name);
      debugPrint('跳过实时估值轮询 $label: 属于货币/理财/存单类无盘中估值品种');
      return null;
    }

    // 0.1 优先检查场外联接 -> 场内影子 ETF 映射表 (解决 QDII 与指数联接基金无估值 JS 的问题)
    if (_shadowEtfMap.containsKey(code)) {
      final shadowVal =
          await _tryShadowEtfGz(code, _shadowEtfMap[code]!, name: name);
      if (shadowVal != null) return shadowVal;
    }

    if (_valuationProxyMap.containsKey(code)) {
      final proxyCode = _valuationProxyMap[code]!;
      try {
        final results = await Future.wait([
          _tryEastMoneyWeb(code, 1, name: name),
          _fetchValuationDirect(proxyCode, name: name, preferredSourceIndex: sourceIdx)
        ]);
        final childWeb = results[0];
        final proxyVal = results[1];

        if (childWeb != null && proxyVal != null) {
          final latestItem = childWeb['latest_item'] as Map?;
          final childDwjzStr = latestItem?['DWJZ']?.toString();
          final childDwjz = double.tryParse(childDwjzStr ?? '');
          final gszzlStr =
              proxyVal['gszzl']?.toString().replaceAll('%', '') ?? '';
          final gszzl = double.tryParse(gszzlStr);

          if (childDwjz != null && gszzl != null) {
            final childGsz = childDwjz * (1 + gszzl / 100);
            return {
              'source': proxyVal['source'],
              'name': proxyVal['name'] ?? '',
              'jzrq': childWeb['jzrq'] ?? proxyVal['jzrq'],
              'dwjz': childDwjz.toString(),
              'gsz': childGsz.toStringAsFixed(4),
              'gszzl': proxyVal['gszzl'],
              'gztime': proxyVal['gztime'],
              'is_proxy': true
            };
          }
        }
      } catch (e) {
        final label = _formatFundLabel(code, name);
        debugPrint('影子基金估值代理抓取异常 $label -> $proxyCode: $e');
      }
    }

    return _fetchValuationDirect(code, name: name, preferredSourceIndex: sourceIdx);
  }

  Future<Map<String, dynamic>?> _tryShadowEtfGz(
      String code, String etfSecId, {String? name}) async {
    try {
      // 1. 尝试通过 fetchHistory (Mobile 接口优先 + Web 接口兜底) 获取最新单位净值
      final historyData = await fetchHistory(code, name: name, pageSize: 1);
      final childDwjzStr = historyData?['latest_item']?['DWJZ']?.toString() ??
          (historyData?['navs'] as List?)?.firstOrNull?.toString();
      double? childDwjz = double.tryParse(childDwjzStr ?? '');

      // 2. 拉取场内影子 ETF 的实时盘中行情 (优先腾讯 qt.gtimg.cn，次选东财 Push)
      double? etfChangePct;
      String? etfName;

      // 尝试腾讯行情
      try {
        final url = 'https://qt.gtimg.cn/q=$etfSecId';
        final response = await _dio.get(url);
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final match = RegExp(r'v_[^=]+="([^"]+)"').firstMatch(text);
          if (match != null) {
            final parts = match.group(1)!.split('~');
            if (parts.length >= 33) {
              etfName = parts[1];
              etfChangePct = double.tryParse(parts[32]); // 涨跌幅 %
            }
          }
        }
      } catch (_) {}

      // 若腾讯失败，降级尝试东财 Push 接口
      if (etfChangePct == null) {
        try {
          final isSh = etfSecId.startsWith('sh');
          final secIdParam =
              '${isSh ? '1' : '0'}.${etfSecId.replaceAll(RegExp(r'[^\d]'), '')}';
          final url =
              'https://push2.eastmoney.com/api/qt/stock/get?secid=$secIdParam&fields=f58,f170';
          final response = await _dio.get(url);
          if (response.statusCode == 200 && response.data is Map) {
            final data = response.data['data'];
            if (data != null) {
              etfName ??= data['f58']?.toString();
              final rawZzl = (data['f170'] as num?)?.toDouble();
              if (rawZzl != null) {
                etfChangePct = rawZzl / 100.0;
              }
            }
          }
        } catch (_) {}
      }

      if (etfChangePct == null) return null;

      childDwjz ??= 1.0;
      final gsz = childDwjz * (1 + etfChangePct / 100.0);
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final timeStr = DateTime.now().toString().substring(11, 16);
      final jzrqStr = historyData?['jzrq'] ?? todayStr;

      return {
        'source': 'ShadowETF',
        'name': etfName ?? '',
        'jzrq': jzrqStr,
        'dwjz': childDwjz.toString(),
        'gsz': gsz.toStringAsFixed(4),
        'gszzl': etfChangePct.toStringAsFixed(2),
        'gztime': '$todayStr $timeStr [场内影子估值]',
        'is_shadow': true,
      };
    } catch (e) {
      final label = _formatFundLabel(code, name);
      debugPrint('影子 ETF 估值抓取失败 $label -> $etfSecId: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchValuationDirect(String code,
      {String? name, int preferredSourceIndex = 0}) async {
    final sources = <Future<Map<String, dynamic>?> Function()>[
      () => _trySinaGz(code),
    ];

    final total = sources.length;
    final startIndex = (preferredSourceIndex % total + total) % total;

    for (int i = 0; i < total; i++) {
      final sourceIdx = (startIndex + i) % total;
      final val = await sources[sourceIdx]();
      if (val != null) return val;
    }

    final label = _formatFundLabel(code, name);
    final msg = '抓取基金估值失败 $label: 新浪盘中估值数据源无响应';
    debugPrint(msg);
    errors.add(msg);
    return null;
  }

  Future<Map<String, dynamic>?> _trySinaGz(String code) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'https://hq.sinajs.cn/list=fu_$code';
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://finance.sina.com.cn',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            },
          ),
        );
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final match = RegExp(r'var hq_str_fu_\d+="([^"]+)"').firstMatch(text);
          if (match != null) {
            final parts = match.group(1)!.split(',');
            // 实际字段格式（共10个）：
            // [0]=基金名 [1]=估值时间 [2]=昨日净值 [3]=今日估值
            // [4]=估值(同[3]) [5]=涨跌额 [6]=涨跌率% [7]=日期
            if (parts.length >= 8) {
              final name    = parts[0];
              final gztime  = parts[1];            // 估值时间 HH:mm:ss
              final dwjz    = parts[2];            // 昨日净值
              final gsz     = parts[3];            // 今日估算净值
              final gszzl   = parts[6];            // 估算涨跌率 %
              final jzrq    = parts[7];            // 日期 yyyy-MM-dd

              if (double.tryParse(gsz) != null &&
                  gsz != '0.0000' &&
                  gsz.isNotEmpty) {
                // 新浪返回的 gztime 只含时间 HH:mm:ss，无日期，需拼接日期使 isTodayValuation 能正确判断
                final fullGztime = gztime.contains('-')
                    ? gztime
                    : '$jzrq $gztime';
                return {
                  'source': 'SinaGz',
                  'name': name,
                  'jzrq': jzrq,
                  'dwjz': dwjz,
                  'gsz': gsz,
                  'gszzl': gszzl.replaceAll('%', ''),
                  'gztime': fullGztime
                };
              }
            }
          }
        }
      } catch (e) {
        if (attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    return null;
  }


  // ---------------- 抓取基本概况以修正板块 ----------------
  Future<Map<String, String>?> fetchSectorInfo(String code, {String? name}) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'https://fundf10.eastmoney.com/jbgk_$code.html';
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://fundf10.eastmoney.com/',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            },
          ),
        );
        if (response.statusCode == 200) {
          final html = response.data.toString();

          // 匹配 业绩比较基准 和 跟踪标的
          // 示例：<th>业绩比较基准</th><td>中证白酒指数收益率*95%...</td>
          final benchmarkMatch = RegExp(
                  r'<th>业绩比较基准</th>\s*<td[^>]*>(.*?)</td>',
                  caseSensitive: false,
                  dotAll: true)
              .firstMatch(html);
          final targetMatch = RegExp(r'<th>跟踪标的</th>\s*<td[^>]*>(.*?)</td>',
                  caseSensitive: false, dotAll: true)
              .firstMatch(html);

          String benchmark = '';
          String trackingTarget = '';

          if (benchmarkMatch != null) {
            benchmark = _cleanHtmlTags(benchmarkMatch.group(1) ?? '').trim();
          }
          if (targetMatch != null) {
            trackingTarget = _cleanHtmlTags(targetMatch.group(1) ?? '').trim();
          }

          return {
            'benchmark': benchmark,
            'trackingTarget': trackingTarget,
          };
        }
      } catch (e) {
        if (attempt == 2) {
          final label = _formatFundLabel(code, name);
          debugPrint('抓取 jbgk 基本概况失败 $label: $e');
        }
      }
    }
    return null;
  }



  Future<Map<String, dynamic>> testApiConnectivity(
      String apiName, String testUrl,
      {Map<String, String>? headers}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _dio.get(
        testUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      sw.stop();
      if (response.statusCode == 200) {
        return {
          'name': apiName,
          'status': '正常',
          'latencyMs': sw.elapsedMilliseconds,
          'error': null,
        };
      } else {
        return {
          'name': apiName,
          'status': '异常 (${response.statusCode})',
          'latencyMs': sw.elapsedMilliseconds,
          'error': 'HTTP Status ${response.statusCode}',
        };
      }
    } catch (e) {
      sw.stop();
      return {
        'name': apiName,
        'status': '网络失败',
        'latencyMs': sw.elapsedMilliseconds,
        'error': e.toString(),
      };
    }
  }

  String _cleanHtmlTags(String html) {
    // 移除 HTML 标签，如 <a> 链接，并替换 &nbsp;
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ');
  }
}

class SafeTransformer extends BackgroundTransformer {
  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) {
    final contentType = responseBody.headers[Headers.contentTypeHeader];
    if (contentType != null) {
      final List<String> cleaned = [];
      for (final value in contentType) {
        if (value.contains(',')) {
          final parts = value.split(',');
          if (parts.isNotEmpty) {
            cleaned.add(parts.first.trim());
          }
        } else {
          cleaned.add(value);
        }
      }
      responseBody.headers[Headers.contentTypeHeader] = cleaned;
    }
    return super.transformResponse(options, responseBody);
  }
}
