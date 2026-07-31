import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'utils/safe_compute.dart';

class FundDataGateway {
  static final FundDataGateway _instance = FundDataGateway._internal();
  factory FundDataGateway() => _instance;
  FundDataGateway._internal() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15'
    };
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    _dio.transformer = SafeTransformer();

    // 仅对已知可信的基金数据源域名跳过 SSL 证书校验
    // 原因：部分机器由于 SSL 证书链验证失败（如 514 拦截或企业代理）导致无法访问基金 API
    // 注意：仅白名单范围内的 host 及其子域名才跳过，避免全局中间人攻击风险
    const trustedHosts = {
      'fundgz.1234567.com.cn',
      'fundmobapi.eastmoney.com',
      'fundf10.eastmoney.com',
      'api.fund.eastmoney.com',
      'danjuanapp.com',
      'qt.gtimg.cn',
      'unitmob.1234567.com.cn',
    };
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          return trustedHosts
              .any((trusted) => host == trusted || host.endsWith('.$trusted'));
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
      {int pageSize = 2000}) async {
    // 1. 尝试天天基金移动端 API
    var res = await _tryEastMoneyMobile(code, pageSize);
    if (res != null) return res;

    // 2. 降级一：尝试新浪财经历史净值 API
    res = await _trySinaHistory(code, pageSize);
    if (res != null) return res;

    // 3. 降级二：尝试天天基金网页端 F10 接口 (HTML 正则解析)
    res = await _tryEastMoneyWeb(code, pageSize);
    return res;
  }

  Future<Map<String, dynamic>?> _trySinaHistory(
      String code, int pageSize) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url =
            'http://stock.finance.sina.com.cn/fundInfo/api/openapi.php/CaihuiFundInfoService.getNav?symbol=$code&num=$pageSize';
        final response = await _dio.get(
          url,
          options: Options(
            headers: {
              'Referer': 'https://finance.sina.com.cn',
            },
          ),
        );
        if (response.statusCode == 200) {
          final data = response.data;
          if (data is Map &&
              data['result'] != null &&
              data['result']['data'] != null) {
            final List list = data['result']['data']['data'] ?? [];
            final List<double> navs = [];
            final List<String> dates = [];

            for (final item in list) {
              final val = double.tryParse(item['jjjz']?.toString() ?? '');
              var dt = item['fbrq']?.toString() ?? '';
              if (dt.length >= 10) {
                dt = dt.substring(0, 10);
              }
              if (val != null && dt.isNotEmpty) {
                navs.add(val);
                dates.add(dt);
              }
            }

            if (navs.isNotEmpty) {
              return {
                'source': 'SinaHistory',
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
          }
        }
      } catch (e) {
        if (attempt == 2) {
          final msg = 'SinaHistory 抓取失败 ($code): $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryEastMoneyMobile(
      String code, int pageSize) async {
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
        if (attempt == 2) {
          final msg = 'EastMoneyMobile 抓取失败 ($code): $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryEastMoneyWeb(
      String code, int pageSize) async {
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
        if (attempt == 2) {
          final msg = 'EastMoneyWeb 抓取失败 ($code): $e';
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
      {int limit = 2000}) async {
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
        if (attempt == 2) {
          final msg = 'EtfKline 历史抓取失败 ($etfCode): $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  // ---------------- 抓取实时估值 ----------------

  Future<Map<String, Map<String, dynamic>>> fetchValuationsSinaBatch(
      List<String> codes) async {
    if (codes.isEmpty) return {};
    try {
      final List<String> queryList = [];
      final Map<String, String> etfToFundCode = {}; // 记录影子 ETF 代码到原基金代码的映射

      for (final c in codes) {
        if (_shadowEtfMap.containsKey(c)) {
          final etfCode = _shadowEtfMap[c]!;
          queryList.add(etfCode);
          etfToFundCode[etfCode] = c;
        } else {
          queryList.add('fu_$c');
        }
      }

      final listStr = queryList.join(',');
      final url = 'http://hq.sinajs.cn/list=$listStr';
      final response = await _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://finance.sina.com.cn',
          },
        ),
      );
      if (response.statusCode == 200) {
        final text = response.data.toString();
        // 匹配 fu_ 格式的基金，或 sh/sz 格式的影子 ETF
        final reg = RegExp(r'var hq_str_(fu_\d{6}|sh\d{6}|sz\d{6})="([^"]*)"');
        final matches = reg.allMatches(text);
        final Map<String, Map<String, dynamic>> results = {};
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);

        for (final m in matches) {
          final key = m.group(1)!;
          final dataStr = m.group(2);
          if (dataStr != null && dataStr.isNotEmpty) {
            final parts = dataStr.split(',');

            if (key.startsWith('fu_')) {
              final code = key.substring(3);
              if (parts.length >= 8) {
                final gsz = parts[2];
                final gszzl = parts[6];
                final jzrq = parts[7];
                final timeStr = parts[1];

                if (jzrq == todayStr) {
                  results[code] = {
                    'source': 'SinaBatch',
                    'jzrq': jzrq,
                    'dwjz': parts[3],
                    'gsz': gsz,
                    'gszzl': gszzl,
                    'gztime': '$jzrq $timeStr'
                  };
                }
              }
            } else {
              // 影子 ETF (sh/sz)
              final code = etfToFundCode[key];
              if (code != null && parts.length >= 32) {
                final name = parts[0];
                final yesterdayClose = double.tryParse(parts[2]) ?? 0.0;
                final currentPrice = double.tryParse(parts[3]) ?? 0.0;
                final dateStr = parts[30];
                final timeStr = parts[31];

                if (yesterdayClose > 0 && currentPrice > 0) {
                  final changePct =
                      ((currentPrice - yesterdayClose) / yesterdayClose * 100);
                  results[code] = {
                    'source': 'ShadowETF',
                    'name': name,
                    'jzrq': dateStr,
                    'dwjz': yesterdayClose.toStringAsFixed(4),
                    'gsz': currentPrice.toStringAsFixed(4),
                    'gszzl': changePct.toStringAsFixed(2),
                    'gztime': '$dateStr $timeStr',
                    'is_shadow': true
                  };
                }
              }
            }
          }
        }
        return results;
      }
    } catch (e) {
      debugPrint('SinaBatch 批量估值抓取失败: $e');
    }
    return {};
  }

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

  Future<Map<String, dynamic>?> _trySinaStockGz(String etfCode) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'http://hq.sinajs.cn/list=$etfCode';
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://finance.sina.com.cn',
            },
          ),
        );
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final reg = RegExp('var hq_str_$etfCode="([^"]*)"');
          final match = reg.firstMatch(text);
          if (match != null) {
            final dataStr = match.group(1);
            if (dataStr != null && dataStr.isNotEmpty) {
              final parts = dataStr.split(',');
              if (parts.length >= 32) {
                final name = parts[0];
                final yesterdayClose = double.tryParse(parts[2]) ?? 0.0;
                final currentPrice = double.tryParse(parts[3]) ?? 0.0;
                final dateStr = parts[30];
                final timeStr = parts[31];

                if (yesterdayClose > 0 && currentPrice > 0) {
                  final changePct =
                      ((currentPrice - yesterdayClose) / yesterdayClose * 100);
                  return {
                    'source': 'ShadowETF',
                    'name': name,
                    'jzrq': dateStr,
                    'dwjz': yesterdayClose.toStringAsFixed(4),
                    'gsz': currentPrice.toStringAsFixed(4),
                    'gszzl': changePct.toStringAsFixed(2),
                    'gztime': '$dateStr $timeStr',
                    'is_shadow': true
                  };
                }
              }
            }
          }
        }
      } catch (e) {
        if (attempt == 2) {
          debugPrint('ShadowETF ($etfCode) 估值抓取失败: $e');
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchValuation(String code,
      {bool preferSina = false, bool preferTencent = false}) async {
    // 1. 优先检查场外到场内影子 ETF 的代理映射
    if (_shadowEtfMap.containsKey(code)) {
      final etfCode = _shadowEtfMap[code]!;
      final shadowVal = await _trySinaStockGz(etfCode);
      if (shadowVal != null) {
        return shadowVal;
      }
    }

    if (_valuationProxyMap.containsKey(code)) {
      final proxyCode = _valuationProxyMap[code]!;
      try {
        final results = await Future.wait([
          _tryEastMoneyWeb(code, 1),
          _fetchValuationDirect(proxyCode,
              preferSina: preferSina, preferTencent: preferTencent)
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
        debugPrint('影子基金估值代理抓取异常 ($code -> $proxyCode): $e');
      }
    }

    return _fetchValuationDirect(code,
        preferSina: preferSina, preferTencent: preferTencent);
  }

  Future<Map<String, dynamic>?> _fetchValuationDirect(String code,
      {bool preferSina = false, bool preferTencent = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (preferTencent) {
      // 1. 优先尝试腾讯估值
      var val = await _tryTencentGz(code);
      if (val != null) return val;

      // 2. 降级：尝试天天基金估值
      val = await _tryEastMoneyGz(code, timestamp);
      if (val != null) return val;

      // 3. 降级：尝试新浪估值
      val = await _trySinaGz(code);
      return val;
    } else if (preferSina) {
      // 1. 优先尝试新浪估值
      var val = await _trySinaGz(code);
      if (val != null) return val;

      // 2. 降级：尝试天天基金估值
      val = await _tryEastMoneyGz(code, timestamp);
      return val;
    } else {
      // 1. 优先尝试天天基金估值
      var val = await _tryEastMoneyGz(code, timestamp);
      if (val != null) return val;

      // 2. 降级：尝试新浪估值
      val = await _trySinaGz(code);
      return val;
    }
  }

  Future<Map<String, dynamic>?> _tryEastMoneyGz(
      String code, int timestamp) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'https://fundgz.1234567.com.cn/js/$code.js?rt=$timestamp';
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://fund.eastmoney.com/',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            },
          ),
        );
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final match = RegExp(r'jsonpgz\((.*?)\);').firstMatch(text);
          if (match != null) {
            final content = match.group(1);
            if (content != null && content.trim().isNotEmpty) {
              final rawJson = json.decode(content);
              return {
                'source': 'EastMoneyGz',
                'name': rawJson['name'],
                'jzrq': rawJson['jzrq'],
                'dwjz': rawJson['dwjz'],
                'gsz': rawJson['gsz'],
                'gszzl': rawJson['gszzl'],
                'gztime': rawJson['gztime']
              };
            }
          }
        }
      } catch (e) {
        if (attempt == 2) {
          if (e is DioException &&
              (e.response?.statusCode == 404 ||
                  e.response?.statusCode == 514)) {
            final statusCode = e.response?.statusCode;
            final msg = 'EastMoneyGz 暂无估值 ($code) [HTTP $statusCode]';
            debugPrint('$msg, 详情: ${e.message}');
            errors.add(msg);
          } else {
            final msg = 'EastMoneyGz 估值抓取失败 ($code): $e';
            debugPrint(msg);
            errors.add(msg);
          }
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _tryTencentGz(String code) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'https://qt.gtimg.cn/q=jj$code';
        final response = await _dio.get(url);
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final match = RegExp(r'v_jj\d+="([^"]+)"').firstMatch(text);
          if (match != null) {
            final parts = match.group(1)!.split('~');
            if (parts.length >= 9) {
              final gsz = parts[5];
              final gszzl = parts[7];
              final jzrq = parts[8];

              final todayStr =
                  DateTime.now().toIso8601String().substring(0, 10);
              if (jzrq != todayStr) {
                // 如果腾讯返回的不是今天的日期，说明盘中未更新，返回 null 以便降级到天天基金抓取
                return null;
              }

              return {
                'source': 'TencentGz',
                'jzrq': jzrq,
                'dwjz': gsz, // 腾讯降级时用估值代替昨日净值
                'gsz': gsz,
                'gszzl': gszzl,
                'gztime': '$jzrq ${DateTime.now().toString().substring(11, 16)}'
              };
            }
          }
        }
      } catch (e) {
        if (attempt == 2) {
          final msg = 'TencentGz 估值抓取失败 ($code): $e';
          debugPrint(msg);
          errors.add(msg);
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _trySinaGz(String code) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final url = 'http://hq.sinajs.cn/list=fu_$code';
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://finance.sina.com.cn',
            },
          ),
        );
        if (response.statusCode == 200) {
          final text = response.data.toString();
          final match =
              RegExp(r'var hq_str_fu_(\d{6})="([^"]*)"').firstMatch(text);
          if (match != null) {
            final dataStr = match.group(2);
            if (dataStr != null && dataStr.isNotEmpty) {
              final parts = dataStr.split(',');
              if (parts.length >= 8) {
                final gsz = parts[2];
                final gszzl = parts[6];
                final jzrq = parts[7];
                final timeStr = parts[1];

                final todayStr =
                    DateTime.now().toIso8601String().substring(0, 10);
                if (jzrq == todayStr) {
                  return {
                    'source': 'Sina',
                    'jzrq': jzrq,
                    'dwjz': parts[3],
                    'gsz': gsz,
                    'gszzl': gszzl,
                    'gztime': '$jzrq $timeStr'
                  };
                }
              }
            }
          }
        }
      } catch (e) {
        if (attempt == 2) {
          debugPrint('SinaGz 估值抓取失败 ($code): $e');
        }
      }
    }
    return null;
  }

  // ---------------- 抓取基本概况以修正板块 ----------------
  Future<Map<String, String>?> fetchSectorInfo(String code) async {
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
          debugPrint('抓取 jbgk 基本概况失败 ($code): $e');
        }
      }
    }
    return null;
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
