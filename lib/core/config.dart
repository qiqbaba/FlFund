import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'db_manager.dart';
import 'utils/pinyin_search.dart';
import 'data_gateway.dart';
import 'supabase_manager.dart';

import 'models/fund_info.dart';
export 'models/fund_info.dart';

/// 合法基金代码正则：恰好 6 位数字（提取为常量避免热路径重复编译）
final _fundCodeRegex = RegExp(r'^\d{6}$');

class AppConfig extends ChangeNotifier {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  bool _isLoaded = false;

  Map<String, FundInfo> fundsInfo = {};
  Map<String, FundInfo> deletedFunds = {};
  DateTime? lastSyncTime;
  List<int> dropDays = [2, 3, 4, 5];
  List<int> percentileMonths = [1, 2, 3, 6, 12, 24, 36];
  Map<String, List<String>> hiddenColumns = {
    'special': ['持有金额/\n收益率', '昨日'],
    'my_fund': ['持有金额/\n收益率', '昨日'],
    'ranking': ['持有金额/\n收益率', '昨日'],
    'valuation': ['昨日', '估值状态\n(PE/PB)'],
    'other': ['持有金额/\n收益率', '昨日'],
    'cycle': []
  };
  String themeMode = 'Light';
  String defaultOcrProvider = 'zhipu';
  String zhipuApiKey = '';
  String zhipuApiUrl = 'https://open.bigmodel.cn/api/paas/v4';
  String zhipuModel = 'glm-4.6v-flash';
  String mimoApiKey = '';
  String mimoApiUrl = 'https://api.xiaomimimo.com/v1';
  String mimoModel = 'mimo-v2.5';
  List<Map<String, String>> customApis = [];
  bool freezeColumns = false;
  bool ocrPreferClassC = true;
  String supabaseUrl = 'https://zaslmgurbafajgoafpat.supabase.co';
  String supabaseAnonKey = 'sb_publishable__bq-rBeyAvgANPAzX_daKg_ua76Nj4U';

  double volatilityLowThreshold = 15.0;
  double volatilityHighThreshold = 48.0;
  DateTime? volatilityUpdateTime;

  /// 新基金与标的 ETF 的代偿映射表
  static const Map<String, String> indexProxyMap = {
    '025791': '560660', // 新华中证云计算50ETF联接C -> 新华中证云计算50ETF
    '025197': '159262', // 广发港股通科技ETF联接A -> 广发恒生港股通科技ETF
  };

  static const List<String> marketRepresentativeCodes = [
    // === 1. 低波动类（债基、货币、固收+等，共 15 只） ===
    '000009', // 易方达天天理财货币A
    '000300', // 广发聚鑫债券A
    '000107', // 华夏安康信用优选债券A
    '000147', // 易方达高等级信用债A
    '000032', // 易方达信用债A
    '000854', // 鹏华丰融定期开放债券
    '000189', // 易方达丰和
    '003102', // 南方荣尊混合
    '000389', // 广发聚鑫债券C
    '000111', // 易方达纯债债券A
    '000205', // 易方达投资级信用债A
    '000186', // 华夏债券A
    '000307', // 易方达双债增强债券A
    '000406', // 汇添富双利增强债券A
    '000739', // 广发天天红货币A

    // === 2. 中波动类（宽基指数、红利、偏股混合，共 20 只） ===
    '000051', // 华夏沪深300联接A
    '002987', // 广发沪深300联接A
    '002906', // 南方中证500联接C
    '070018', // 嘉实中证500联接A
    '005313', // 万家中证红利指数A
    '003494', // 富国天惠精选混合C
    '000011', // 华夏大盘精选
    '110011', // 易方达优质精选
    '110003', // 易方达上证50指数A
    '000961', // 天弘沪深300指数A
    '000962', // 天弘中证500指数A
    '000173', // 汇添富沪深300A
    '002005', // 广发沪深300A
    '005827', // 易方达蓝筹精选混合
    '000311', // 景顺长城沪深300
    '001052', // 南方中证500联接A
    '005585', // 银河沪深300A
    '020011', // 国泰沪深300A
    '270010', // 广发沪深300C
    '110020', // 易方达沪深300A

    // === 3. 高波动类（行业指数、主动成长、科技等，共 30 只） ===
    '110026', // 易方达创业板联接A
    '004743', // 易方达科技创新
    '000083', // 汇添富消费行业混合
    '012414', // 招商中证白酒指数C
    '001631', // 天弘中证食品饮料指数A
    '003096', // 中欧医疗健康混合A
    '008985', // 华夏中证新能源汽车联接A
    '001156', // 申万菱信中证环保产业A
    '001605', // 国泰中证计算机A
    '008087', // 华夏中证5G通信联接A
    '011612', // 华夏科创50联接A
    '012803', // 华夏中证1000联接A
    '000021', // 华夏优势增长混合
    '260108', // 景顺长城内需增长
    '004856', // 广发中证全指建材A
    '004851', // 广发中证全指原材料A
    '001552', // 天弘中证证券保险A
    '004069', // 南方中证全指证券公司A
    '001617', // 天弘中证电子A
    '001618', // 天弘中证计算机A
    '001027', // 前海开源中国稀缺资产A
    '002190', // 农银汇理新能源主题
    '005967', // 创金合信工业美景
    '001856', // 易方达环保主题
    '005628', // 万家成长优选
    '007301', // 国泰科创板50联接A
    '001475', // 易方达国防军工混合A
    '001594', // 天弘中证医药100A
    '001632', // 天弘中证医疗A
    '005063', // 广发高端制造混合A

    // === 4. 跨境/商品QDII类（高/中高波动，共 10 只） ===
    '270042', // 广发纳斯达克100联接A
    '000043', // 嘉实美国成长混合
    '000071', // 华夏恒生联接A
    '070031', // 嘉实黄金
    '000179', // 广发美国房地产QDII
    '006327', // 华安纳斯达克100联接A
    '000934', // 国泰大宗商品
    '040046', // 华安大中华升级QDII
    '001668', // 汇添富恒生指数
    '000072', // 华夏恒生联接C
  ];

  // 允许测试时重定向配置文件路径，防止覆盖真实配置文件
  String? customConfigPath;

  // 获取配置文件路径
  Future<File> _getConfigFile() async {
    if (customConfigPath != null) {
      return File(customConfigPath!);
    }
    if (!kIsWeb && Platform.isWindows) {
      // 1. 优先尝试当前工作目录 (开发调试阶段)
      final currFile = File(path.join(Directory.current.path, 'my_funds.json'));
      if (await currFile.exists()) {
        return currFile;
      }
      // 2. 其次尝试可执行文件同级目录 (打包/双击运行发布版)
      try {
        final exeDir = path.dirname(Platform.resolvedExecutable);
        final exeFile = File(path.join(exeDir, 'my_funds.json'));
        if (await exeFile.exists()) {
          return exeFile;
        }
      } catch (_) {}

      // 3. Fallback: 默认返回当前工作目录下的文件位置
      return currFile;
    } else {
      // 安卓端则使用应用专属沙盒路径
      final dir = await getApplicationDocumentsDirectory();
      return File(path.join(dir.path, 'my_funds.json'));
    }
  }

  // 加载配置
  Future<void> loadConfig({bool force = false}) async {
    if (_isLoaded && !force) {
      return;
    }
    try {
      final file = await _getConfigFile();
      final prefs = await SharedPreferences.getInstance();

      if (await file.exists()) {
        final content = await file.readAsString(encoding: utf8);
        final Map<String, dynamic> jsonMap = json.decode(content);

        // 解析 funds_info
        if (jsonMap['funds_info'] != null) {
          fundsInfo.clear();
          final Map<String, dynamic> infoMap = jsonMap['funds_info'];
          bool dirty = false;
          infoMap.forEach((code, value) {
            if (_fundCodeRegex.hasMatch(code)) {
              final fund =
                  FundInfo.fromJson(code, value as Map<String, dynamic>);
              if (!fund.isHeld &&
                  (fund.amount != 0.0 || fund.yieldRate != 0.0)) {
                fund.amount = 0.0;
                fund.yieldRate = 0.0;
                dirty = true;
                debugPrint('清理未持有基金的持仓脏数据: $code');
              }
              fundsInfo[code] = fund;
            } else {
              dirty = true;
              debugPrint('过滤非法基金代码: $code');
            }
          });

          // 本地板块重新清洗升级：如果使用细化新规则能匹配到更具体或不同的分类，进行更新
          bool configDirty = false;
          for (final code in fundsInfo.keys) {
            final info = fundsInfo[code]!;
            final oldSector = info.sector;
            final newSector =
                PinyinSearch().getCleanSector(info.name, oldSector);
            if (newSector != oldSector) {
              info.sector = newSector;
              info.updatedAt =
                  DateTime.now(); // 触发板块升级时更新修改时间，避免云端旧板块在差异同步时覆盖本地
              configDirty = true;
              debugPrint(
                  '基金 $code (${info.name}) 本地板块已从 $oldSector 自动升级为 $newSector');
            }
          }
          if (configDirty || dirty) {
            unawaited(saveConfig());
          }
        }

        // 解析 deleted_funds 墓碑
        if (jsonMap['deleted_funds'] != null) {
          deletedFunds.clear();
          final Map<String, dynamic> delMap = jsonMap['deleted_funds'];
          delMap.forEach((code, value) {
            if (_fundCodeRegex.hasMatch(code)) {
              deletedFunds[code] =
                  FundInfo.fromJson(code, value as Map<String, dynamic>);
            }
          });
        }

        // 解析 last_sync_time
        if (jsonMap['last_sync_time'] != null &&
            jsonMap['last_sync_time'].toString().isNotEmpty) {
          lastSyncTime =
              DateTime.tryParse(jsonMap['last_sync_time'].toString());
        } else {
          lastSyncTime = null;
        }

        // 解析其他配置
        if (jsonMap['drop_days'] != null) {
          dropDays = List<int>.from(jsonMap['drop_days']);
        }
        if (jsonMap['percentile_months'] != null) {
          percentileMonths = List<int>.from(jsonMap['percentile_months']);
        }
        if (jsonMap['hidden_columns'] != null) {
          final Map<String, dynamic> hcMap = jsonMap['hidden_columns'];
          hcMap.forEach((key, value) {
            hiddenColumns[key] = value != null ? List<String>.from(value) : [];
          });
        }
        if (jsonMap['theme'] != null) {
          themeMode = jsonMap['theme'];
        }

        // 加载 API 密钥
        final savedZpKey = prefs.getString('zp_api_key');
        zhipuApiKey = (savedZpKey != null && savedZpKey.isNotEmpty)
            ? savedZpKey
            : (jsonMap['zhipu_api_key']?.toString() ?? '');

        if (zhipuApiKey.isNotEmpty && (savedZpKey == null || savedZpKey.isEmpty)) {
          await prefs.setString('zp_api_key', zhipuApiKey);
        }

        final savedMmKey = prefs.getString('mm_api_key');
        mimoApiKey = (savedMmKey != null && savedMmKey.isNotEmpty)
            ? savedMmKey
            : (jsonMap['mimo_api_key']?.toString() ?? '');
        if (mimoApiKey.isNotEmpty && (savedMmKey == null || savedMmKey.isEmpty)) {
          await prefs.setString('mm_api_key', mimoApiKey);
        }

        if (jsonMap['custom_apis'] != null) {
          try {
            customApis = (jsonMap['custom_apis'] as List)
                .map((e) => Map<String, String>.from(e as Map))
                .toList();
            // 填充并迁移自定义提供商密钥
            for (var provider in customApis) {
              final id = provider['id'];
              final jsonKey = provider['key'] ?? '';
              if (id != null) {
                final savedKey = prefs.getString('custom_api_key_$id');
                if (savedKey != null) {
                  provider['key'] = savedKey;
                } else if (jsonKey.isNotEmpty) {
                  provider['key'] = jsonKey;
                  await prefs.setString('custom_api_key_$id', jsonKey);
                } else {
                  provider['key'] = '';
                }
              }
            }
          } catch (e) {
            debugPrint('解析 custom_apis 失败: $e');
            customApis = [];
          }
        } else {
          customApis = [];
        }

        if (jsonMap['default_ocr_provider'] != null) {
          defaultOcrProvider = jsonMap['default_ocr_provider'];
          if (defaultOcrProvider == 'custom' && customApis.isNotEmpty) {
            defaultOcrProvider = customApis.first['id']!;
          }
        }

        if (jsonMap['ocr_prefer_class_c'] != null) {
          ocrPreferClassC = jsonMap['ocr_prefer_class_c'];
        }
        if (jsonMap['supabase_url'] != null &&
            jsonMap['supabase_url'].toString().isNotEmpty) {
          supabaseUrl = jsonMap['supabase_url'];
        }
        if (jsonMap['supabase_anon_key'] != null &&
            jsonMap['supabase_anon_key'].toString().isNotEmpty) {
          supabaseAnonKey = jsonMap['supabase_anon_key'];
        }

        if (jsonMap['volatility_low_threshold'] != null) {
          volatilityLowThreshold =
              (jsonMap['volatility_low_threshold'] as num).toDouble();
        }
        if (jsonMap['volatility_high_threshold'] != null) {
          volatilityHighThreshold =
              (jsonMap['volatility_high_threshold'] as num).toDouble();
        }
        if (jsonMap['volatility_update_time'] != null &&
            jsonMap['volatility_update_time'].toString().isNotEmpty) {
          volatilityUpdateTime =
              DateTime.tryParse(jsonMap['volatility_update_time'].toString());
        } else {
          volatilityUpdateTime = null;
        }

        notifyListeners();

        // 加载配置后，对板块仍为“其它”等粗泛类型的自选基金，在后台静默触发一次自动联网修正
        for (final code in fundsInfo.keys) {
          final sector = fundsInfo[code]!.sector;
          if (sector == '其它' || sector == '混合型' || sector == '股票型') {
            unawaited(autoCorrectSector(code));
          }
        }
      } else {
        // 如果文件不存在，也需要初始化加载 SharedPreferences 里的 API 密钥，避免重置
        zhipuApiKey = prefs.getString('zp_api_key') ?? '';
        mimoApiKey = prefs.getString('mm_api_key') ?? '';
      }
    } catch (e) {
      debugPrint('加载配置失败: $e');
    } finally {
      // 无论配置文件是否存在，或加载是否失败，均确保使用当前的配置参数完成 Supabase 客户端初始化
      await SupabaseManager().init(url: supabaseUrl, anonKey: supabaseAnonKey);
      _isLoaded = true;
    }
  }

  Timer? _saveConfigDebounceTimer;
  Completer<void>? _saveConfigCompleter;

  // 物理写盘逻辑 (密钥存入 SharedPreferences，JSON 文件物理脱敏)
  Future<void> _performSaveConfig() async {
    try {
      final file = await _getConfigFile();

      // 1. 将敏感密钥写入 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zp_api_key', zhipuApiKey);
      await prefs.setString('mm_api_key', mimoApiKey);

      for (final provider in customApis) {
        final id = provider['id'];
        final key = provider['key'];
        if (id != null && key != null) {
          await prefs.setString('custom_api_key_$id', key);
        }
      }

      // 2. 擦除 API 密钥导出
      final cleanCustomApis = customApis.map((provider) {
        final Map<String, String> copy = Map.from(provider);
        copy['key'] = '';
        return copy;
      }).toList();

      final Map<String, dynamic> jsonMap = {
        'funds_info':
            fundsInfo.map((key, value) => MapEntry(key, value.toJson())),
        'deleted_funds':
            deletedFunds.map((key, value) => MapEntry(key, value.toJson())),
        'last_sync_time': lastSyncTime?.toIso8601String() ?? '',
        'drop_days': dropDays,
        'percentile_months': percentileMonths,
        'hidden_columns': hiddenColumns,
        'theme': themeMode,
        'zhipu_api_key': '',
        'zhipu_api_url': zhipuApiUrl,
        'zhipu_model': zhipuModel,
        'mimo_api_key': '',
        'mimo_api_url': mimoApiUrl,
        'mimo_model': mimoModel,
        'custom_apis': cleanCustomApis,
        'default_ocr_provider': defaultOcrProvider,
        'freeze_columns': freezeColumns,
        'ocr_prefer_class_c': ocrPreferClassC,
        'supabase_url': supabaseUrl,
        'supabase_anon_key': supabaseAnonKey,
        'volatility_low_threshold': volatilityLowThreshold,
        'volatility_high_threshold': volatilityHighThreshold,
        'volatility_update_time': volatilityUpdateTime?.toIso8601String() ?? '',
      };

      const encoder = JsonEncoder.withIndent('    ');
      final content = encoder.convert(jsonMap);

      final tempFile = File('${file.path}.tmp');
      await tempFile.writeAsString(content, encoding: utf8);
      try {
        if (Platform.isWindows && await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
      } catch (e) {
        await tempFile.copy(file.path);
        await tempFile.delete();
      }
    } catch (e) {
      debugPrint('保存配置失败: $e');
    }
  }

  // 保存配置（支持 300ms 防抖写入，减少高频写盘引起的 I/O 阻塞）
  Future<void> saveConfig({bool forceImmediate = false}) async {
    if (forceImmediate) {
      _saveConfigDebounceTimer?.cancel();
      await _performSaveConfig();
      return;
    }

    _saveConfigDebounceTimer?.cancel();
    _saveConfigCompleter ??= Completer<void>();
    final currentCompleter = _saveConfigCompleter!;

    _saveConfigDebounceTimer =
        Timer(const Duration(milliseconds: 300), () async {
      try {
        await _performSaveConfig();
        if (!currentCompleter.isCompleted) {
          currentCompleter.complete();
        }
      } catch (e) {
        if (!currentCompleter.isCompleted) {
          currentCompleter.completeError(e);
        }
      } finally {
        if (identical(_saveConfigCompleter, currentCompleter)) {
          _saveConfigCompleter = null;
        }
      }
    });

    return currentCompleter.future;
  }

  /// 更新波动率阈值并保存配置
  Future<void> updateVolatilityThresholds(double low, double high) async {
    volatilityLowThreshold = low;
    volatilityHighThreshold = high;
    volatilityUpdateTime = DateTime.now();
    notifyListeners();
    await saveConfig();
  }

  /// 动态更新/校准全库基金波动率分数标准
  Future<Map<String, dynamic>> recalibrateVolatilityThresholds() async {
    final db = FundHistoryDB();
    final gateway = FundDataGateway();

    // 1. 合并本地历史基金和全市场代表性样本基金的代号（去重）
    final Set<String> allCodes = {};
    try {
      allCodes.addAll(await db.getAllFundCodes());
    } catch (e) {
      debugPrint('获取本地基金代码失败: $e');
    }
    allCodes.addAll(marketRepresentativeCodes);

    // 2. 检查哪些基金没有历史数据或者历史数据已过期（超过 24 小时未更新）
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final List<String> codesToFetch = [];

    for (final code in allCodes) {
      final history = await db.getHistory(code);
      bool needUpdate = false;
      if (history == null ||
          history['dates'] == null ||
          history['navs'] == null) {
        needUpdate = true;
      } else {
        final String dMax = history['jzrq'] ?? '';
        final double updateTime =
            (history['update_time'] as num?)?.toDouble() ?? 0.0;
        final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
        // 增量刷新条件：最新净值日期不是今天，且上次网络获取时间超过了 24 小时
        if (dMax != todayStr && nowTime - updateTime > 86400) {
          needUpdate = true;
        }
      }
      if (needUpdate) {
        codesToFetch.add(code);
      }
    }

    // 3. 多线程/异步限流并发抓取数据（最大并发度为 5）
    if (codesToFetch.isNotEmpty) {
      int nextIndex = 0;
      Future<void> worker() async {
        while (nextIndex < codesToFetch.length) {
          final current = nextIndex++;
          final code = codesToFetch[current];
          try {
            final onlineHis = await gateway.fetchHistory(code);
            if (onlineHis != null) {
              final List<double> navs = List<double>.from(onlineHis['navs'] ?? []);
              final List<String> dates = List<String>.from(onlineHis['dates'] ?? []);
              await db.saveHistory(code, onlineHis['jzrq'], navs, dates);
            }
          } catch (e) {
            debugPrint('校准自动补全历史数据拉取失败 ($code): $e');
          }
        }
      }

      final workers = List.generate(5, (_) => worker());
      await Future.wait(workers);
    }

    // 4. 统一计算代表性基金的波动得分 (仅使用固定的代表性基金池参与标准计算)
    final List<double> scores = [];
    for (final code in marketRepresentativeCodes) {
      final history = await db.getHistory(code);
      if (history == null) continue;
      final List<double> allNavs = List<double>.from(history['navs'] ?? []);
      if (allNavs.length < 250) continue; // 成立时间不足 250 个交易日的不参与标准计算

      // 4.0 统一时间窗口为最近 500 个交易日 (约 2 年)，并反转为升序（时间从远到近，以便正确计算最大回撤）
      const int limit = 500;
      final List<double> navs = allNavs.length > limit
          ? allNavs.sublist(0, limit).reversed.toList()
          : allNavs.reversed.toList();

      // 4.1 计算年化波动率
      double volDaily = 0.0;
      final int totalDays = navs.length;
      if (totalDays > 1) {
        final List<double> dailyReturns =
            List<double>.filled(totalDays - 1, 0.0);
        double returnSum = 0.0;
        for (int t = 1; t < totalDays; t++) {
          final double prev = navs[t - 1];
          dailyReturns[t - 1] = prev > 0.0 ? (navs[t] - prev) / prev : 0.0;
          returnSum += dailyReturns[t - 1];
        }
        final double meanReturn = returnSum / (totalDays - 1);
        double sumOfSquares = 0.0;
        for (int t = 0; t < totalDays - 1; t++) {
          final double diff = dailyReturns[t] - meanReturn;
          sumOfSquares += diff * diff;
        }
        volDaily = sqrt(sumOfSquares / (totalDays - 1));
      }
      final double annVolatility = volDaily * sqrt(250.0);

      // 4.2 计算时间窗口内的最大回撤 (Max Drawdown)
      double maxDrawdown = 0.0;
      if (navs.isNotEmpty) {
        double peak = navs.first;
        for (final nav in navs) {
          if (nav > peak) {
            peak = nav;
          } else if (peak > 0.0) {
            final double drawdown = (peak - nav) / peak;
            if (drawdown > maxDrawdown) {
              maxDrawdown = drawdown;
            }
          }
        }
      }

      // 4.3 计算波动综合得分 (年化波动基准 25%, 最大回撤基准 50%)
      // 不进行 clamp 限制，以防高波动堆积，并在排序中保持高区分度
      final double sVol = (annVolatility / 0.25) * 100;
      final double sDrawdown = (maxDrawdown / 0.50) * 100;
      final double score = sVol * 0.6 + sDrawdown * 0.4;
      scores.add(score);
    }

    if (scores.isEmpty) {
      return {
        'low': volatilityLowThreshold,
        'high': volatilityHighThreshold,
        'count': 0,
      };
    }

    // 5. 排序并取分位数
    scores.sort();
    final int lowIdx = (scores.length * 0.333).floor();
    final int highIdx = (scores.length * 0.667).floor();

    // 限制在合理区间写入配置
    final double newLow = scores[lowIdx].clamp(0.0, 100.0);
    final double newHigh = scores[highIdx].clamp(0.0, 100.0);

    // 6. 更新配置并回写
    await updateVolatilityThresholds(newLow, newHigh);

    return {
      'low': newLow,
      'high': newHigh,
      'count': scores.length,
    };
  }

  // 添加自选
  void addFund(String code, String name, String sector) {
    if (!_fundCodeRegex.hasMatch(code)) {
      debugPrint('拒绝添加非法基金代码: $code');
      return;
    }
    final cleanSector = PinyinSearch().getCleanSector(name, sector);
    if (!fundsInfo.containsKey(code)) {
      final newFund = FundInfo(
          code: code,
          name: name,
          sector: cleanSector,
          updatedAt: DateTime.now());
      fundsInfo[code] = newFund;
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFund(newFund));
      }
      notifyListeners();

      // 异步网络修正板块
      unawaited(autoCorrectSector(code));
    }
  }

  // 修改板块分类
  void updateFundSector(String code, String sector) {
    if (fundsInfo.containsKey(code)) {
      final fund = fundsInfo[code]!;
      fund.sector = sector.trim();
      fund.updatedAt = DateTime.now();
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFund(fund));
      }
      notifyListeners();
    }
  }

  bool _isValidTargetText(String text) {
    if (text.isEmpty || text == '--') return false;
    final lowercase = text.toLowerCase();
    const invalidKeywords = ['未披露', '暂无', '暂未', '不适用', '无跟踪标的', '没有', '无业绩'];
    return !invalidKeywords.any((kw) => lowercase.contains(kw));
  }

  // 异步通过网络修正某只基金的板块分类
  Future<void> autoCorrectSector(String code) async {
    try {
      final info = fundsInfo[code];
      if (info == null) return;

      final name = info.name;
      final currentSector = info.sector;

      final gateway = FundDataGateway();
      final sectorInfo = await gateway.fetchSectorInfo(code);
      if (sectorInfo == null) return;

      final benchmark = sectorInfo['benchmark'] ?? '';
      final trackingTarget = sectorInfo['trackingTarget'] ?? '';

      String targetText = '';
      if (trackingTarget.isNotEmpty &&
          trackingTarget != '--' &&
          !trackingTarget.contains('无跟踪标的')) {
        targetText = trackingTarget;
      } else if (benchmark.isNotEmpty && benchmark != '--') {
        targetText = benchmark;
      }

      if (targetText.isNotEmpty && _isValidTargetText(targetText)) {
        // 使用业绩基准或跟踪标的作为名字去清洗，并指定默认类型为 '其它' 以便强制触发关键字匹配
        final cleanSector = PinyinSearch().getCleanSector(targetText, '其它');

        // 如果清洗出的新板块与原板块不同，且不为“其它”
        if (cleanSector != '其它' && cleanSector != currentSector) {
          info.sector = cleanSector;
          info.updatedAt = DateTime.now();
          await saveConfig();
          notifyListeners();
          debugPrint(
              '基金 $code ($name) 板块分类已从 $currentSector 自动修正为 $cleanSector (根据跟踪标的/业绩基准: $targetText)');
        }
      }
    } catch (e) {
      debugPrint('自动修正板块失败 ($code): $e');
    }
  }

  // 移除自选
  void removeFund(String code) {
    if (fundsInfo.containsKey(code)) {
      final fund = fundsInfo.remove(code);
      if (fund != null && SupabaseManager().isLoggedIn) {
        fund.isDeleted = true;
        fund.updatedAt = DateTime.now();
        deletedFunds[code] = fund;
        unawaited(SupabaseManager().deleteFund(code));
      }
      unawaited(saveConfig());
      notifyListeners();
    }
  }

  // 替换基金匹配：将旧基金的持有信息迁移到新基金上，删除旧基金
  void replaceFund(
      String oldCode, String newCode, String newName, String newSector) {
    if (!_fundCodeRegex.hasMatch(newCode)) {
      debugPrint('拒绝替换为非法基金代码: $newCode');
      return;
    }
    final oldFund = fundsInfo[oldCode];
    if (oldFund == null) return;

    final cleanSector = PinyinSearch().getCleanSector(newName, newSector);

    // 创建新基金并迁移持有信息
    final newFund = FundInfo(
      code: newCode,
      name: newName,
      sector: cleanSector,
      isHeld: oldFund.isHeld,
      isSpecial: oldFund.isSpecial,
      isPinned: oldFund.isPinned,
      amount: oldFund.amount,
      yieldRate: oldFund.yieldRate,
      updatedAt: DateTime.now(),
    );

    // 删除旧基金，添加新基金
    final removedOld = fundsInfo.remove(oldCode);
    if (removedOld != null && SupabaseManager().isLoggedIn) {
      removedOld.isDeleted = true;
      removedOld.updatedAt = DateTime.now();
      deletedFunds[oldCode] = removedOld;
      unawaited(SupabaseManager().deleteFund(oldCode));
    }
    fundsInfo[newCode] = newFund;
    unawaited(saveConfig());
    if (SupabaseManager().isLoggedIn) {
      unawaited(SupabaseManager().uploadFund(newFund));
    }
    notifyListeners();

    // 异步网络修正板块
    unawaited(autoCorrectSector(newCode));
  }

  // 特别关注切换
  void toggleSpecial(String code) {
    if (fundsInfo.containsKey(code)) {
      final fund = fundsInfo[code]!;
      fund.isSpecial = !fund.isSpecial;
      fund.updatedAt = DateTime.now();
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFund(fund));
      }
      notifyListeners();
    }
  }

  // 置顶切换
  void togglePinned(String code) {
    if (fundsInfo.containsKey(code)) {
      final fund = fundsInfo[code]!;
      fund.isPinned = !fund.isPinned;
      fund.updatedAt = DateTime.now();
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFund(fund));
      }
      notifyListeners();
    }
  }

  // 修改持有信息
  void updateHoldInfo(
      String code, bool isHeld, double amount, double yieldRate) {
    if (fundsInfo.containsKey(code)) {
      final fund = fundsInfo[code]!;
      fund.isHeld = isHeld;
      fund.amount = amount;
      fund.yieldRate = yieldRate;
      fund.updatedAt = DateTime.now();
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFund(fund));
      }
      notifyListeners();
    }
  }

  // 批量清除持有信息
  void batchRemoveHoldInfos(List<String> codes) {
    bool changed = false;
    final List<FundInfo> updatedFunds = [];
    for (final code in codes) {
      if (fundsInfo.containsKey(code)) {
        final fund = fundsInfo[code]!;
        fund.isHeld = false;
        fund.amount = 0.0;
        fund.yieldRate = 0.0;
        fund.updatedAt = DateTime.now();
        updatedFunds.add(fund);
        changed = true;
      }
    }
    if (changed) {
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFunds(updatedFunds));
      }
      notifyListeners();
    }
  }

  // 批量添加并修改持有基金信息，仅写入一次文件并通知一次监听者
  void addFundsAndHoldInfos(List<Map<String, dynamic>> funds) {
    bool changed = false;
    final List<FundInfo> updatedFunds = [];
    for (final f in funds) {
      final String code = f['code'] ?? '';
      if (code.isEmpty || !_fundCodeRegex.hasMatch(code)) {
        debugPrint('批量导入拒绝非法基金代码: $code');
        continue;
      }

      final String name = f['name'] ?? '';
      final String sector = f['sector'] ?? '其它';
      final double amount = f['amount'] ?? 0.0;
      final double yieldRate = f['yield_rate'] ?? 0.0;
      final bool isHeld = f['is_held'] ?? true;

      final cleanSector = PinyinSearch().getCleanSector(name, sector);
      if (!fundsInfo.containsKey(code)) {
        fundsInfo[code] = FundInfo(
            code: code,
            name: name,
            sector: cleanSector,
            updatedAt: DateTime.now());
        changed = true;
        // 异步网络修正板块
        unawaited(autoCorrectSector(code));
      }

      final fund = fundsInfo[code]!;
      fund.isHeld = isHeld;
      fund.amount = amount;
      fund.yieldRate = yieldRate;
      fund.updatedAt = DateTime.now();
      updatedFunds.add(fund);
      changed = true;
    }

    if (changed) {
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFunds(updatedFunds));
      }
      notifyListeners();
    }
  }

  // 批量添加自选基金，仅添加不存在的，或者更新已存在基金的名称和分类，但不修改任何持仓状态 and 金额
  void addFunds(List<Map<String, dynamic>> funds) {
    bool changed = false;
    final List<FundInfo> updatedFunds = [];
    for (final f in funds) {
      final String code = f['code'] ?? '';
      if (code.isEmpty || !_fundCodeRegex.hasMatch(code)) {
        debugPrint('批量自选导入拒绝非法基金代码: $code');
        continue;
      }

      final String name = f['name'] ?? '';
      final String sector = f['sector'] ?? '其它';

      final cleanSector = PinyinSearch().getCleanSector(name, sector);
      if (!fundsInfo.containsKey(code)) {
        final newFund = FundInfo(
            code: code,
            name: name,
            sector: cleanSector,
            updatedAt: DateTime.now());
        fundsInfo[code] = newFund;
        updatedFunds.add(newFund);
        changed = true;
        // 异步网络修正板块
        unawaited(autoCorrectSector(code));
      } else {
        final fund = fundsInfo[code]!;
        bool fundChanged = false;
        if (fund.name.isEmpty && name.isNotEmpty) {
          fund.name = name;
          fundChanged = true;
        }
        if ((fund.sector.isEmpty || fund.sector == '其它') &&
            sector.isNotEmpty &&
            sector != '其它') {
          fund.sector = cleanSector;
          fundChanged = true;
          // 异步网络修正板块
          unawaited(autoCorrectSector(code));
        }
        if (fundChanged) {
          fund.updatedAt = DateTime.now();
          updatedFunds.add(fund);
          changed = true;
        }
      }
    }

    if (changed) {
      unawaited(saveConfig());
      if (SupabaseManager().isLoggedIn) {
        unawaited(SupabaseManager().uploadFunds(updatedFunds));
      }
      notifyListeners();
    }
  }

  // 切换主题
  void toggleTheme(String mode) {
    themeMode = mode;
    unawaited(saveConfig());
    notifyListeners();
  }

  // 切换列冻结状态
  void toggleFreezeColumns(bool value) {
    freezeColumns = value;
    unawaited(saveConfig());
    notifyListeners();
  }


  // 批量更新 OCR 配置方法
  void updateOcrConfig({
    required String provider,
    required String zhipuKey,
    required String zhipuUrl,
    required String zhipuModelVal,
    required String mimoKey,
    required String mimoUrl,
    required String mimoModelVal,
    required String customKey,
    required String customUrl,
    required String customModelVal,
  }) {
    zhipuApiKey = zhipuKey;
    zhipuApiUrl = zhipuUrl;
    zhipuModel = zhipuModelVal;
    mimoApiKey = mimoKey;
    mimoApiUrl = mimoUrl;
    mimoModel = mimoModelVal;

    if (provider == 'custom') {
      if (customKey.isNotEmpty &&
          customUrl.isNotEmpty &&
          customModelVal.isNotEmpty) {
        final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
        final existingIndex = customApis.indexWhere((item) =>
            item['url'] == customUrl && item['model'] == customModelVal);
        if (existingIndex != -1) {
          customApis[existingIndex]['key'] = customKey;
          defaultOcrProvider = customApis[existingIndex]['id']!;
        } else {
          customApis.add({
            'id': newId,
            'name': '$customModelVal (${_getHost(customUrl)})',
            'url': customUrl,
            'model': customModelVal,
            'key': customKey,
          });
          defaultOcrProvider = newId;
        }
      } else {
        defaultOcrProvider = 'custom';
      }
    } else if (provider.startsWith('custom_')) {
      final existingIndex =
          customApis.indexWhere((item) => item['id'] == provider);
      if (existingIndex != -1) {
        customApis[existingIndex]['key'] = customKey;
        customApis[existingIndex]['url'] = customUrl;
        customApis[existingIndex]['model'] = customModelVal;
        customApis[existingIndex]['name'] =
            '$customModelVal (${_getHost(customUrl)})';
      }
      defaultOcrProvider = provider;
    } else {
      defaultOcrProvider = provider;
    }

    unawaited(saveConfig());
    notifyListeners();
  }

  // 删除自定义 API
  void deleteCustomApi(String id) {
    customApis.removeWhere((item) => item['id'] == id);
    if (defaultOcrProvider == id) {
      defaultOcrProvider = 'zhipu';
    }
    unawaited(saveConfig());
    notifyListeners();
  }

  String _getHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return '';
    }
  }

  // 更新 OCR 优先选择C类配置
  void updateOcrPreferClassC(bool value) {
    ocrPreferClassC = value;
    unawaited(saveConfig());
    notifyListeners();
  }

  // 选择性导出数据为 JSON 字符串并保存到文件 (支持可选密码加密，未加密导出时自动对密钥脱敏)
  Future<bool> exportSelectedData({
    required String destPath,
    required bool includeFundsList,
    required bool includeHoldings,
    required bool includeSpecials,
    required bool includeStrategies,
    required bool includeSettings,
    String? password,
  }) async {
    try {
      final Map<String, dynamic> backupMap = {
        'version': '1.0',
        'export_time': DateTime.now().toIso8601String(),
      };

      // 1. 导出自选基金列表
      if (includeFundsList) {
        final List<Map<String, dynamic>> list = [];
        fundsInfo.forEach((code, info) {
          list.add({
            'code': code,
            'name': info.name,
            'sector': info.sector,
            'is_pinned': info.isPinned,
          });
        });
        backupMap['funds_list'] = list;
      }

      // 2. 导出持仓数据
      if (includeHoldings) {
        final List<Map<String, dynamic>> list = [];
        fundsInfo.forEach((code, info) {
          if (info.isHeld) {
            list.add({
              'code': code,
              'name': info.name,
              'sector': info.sector,
              'amount': info.amount,
              'yield_rate': info.yieldRate,
            });
          }
        });
        backupMap['holdings'] = list;
      }

      // 3. 导出特别关注列表
      if (includeSpecials) {
        final List<String> list = [];
        fundsInfo.forEach((code, info) {
          if (info.isSpecial) {
            list.add(code);
          }
        });
        backupMap['specials'] = list;
      }

      // 4. 导出回测寻优策略
      if (includeStrategies) {
        final db = FundHistoryDB();
        final allStrategies = await db.getAllOptimalStrategies();
        backupMap['optimal_strategies'] = allStrategies;
      }

      // 5. 导出系统全局设置
      if (includeSettings) {
        final bool shouldRedact = password == null || password.isEmpty;

        final List<Map<String, String>> cleanCustomApis =
            customApis.map((provider) {
          final Map<String, String> copy = Map.from(provider);
          if (shouldRedact) {
            copy['key'] = ''; // 脱敏
          }
          return copy;
        }).toList();

        backupMap['global_settings'] = {
          'theme': themeMode,
          'drop_days': dropDays,
          'percentile_months': percentileMonths,
          'hidden_columns': hiddenColumns,
          'zhipu_api_key': shouldRedact ? '' : zhipuApiKey,
          'zhipu_api_url': zhipuApiUrl,
          'zhipu_model': zhipuModel,
          'mimo_api_key': shouldRedact ? '' : mimoApiKey,
          'mimo_api_url': mimoApiUrl,
          'mimo_model': mimoModel,
          'custom_apis': cleanCustomApis,
          'default_ocr_provider': defaultOcrProvider,
          'freeze_columns': freezeColumns,
        };
      }

      final file = File(destPath);
      const encoder = JsonEncoder.withIndent('    ');
      String fileContent = encoder.convert(backupMap);

      // 加密外壳封装
      if (password != null && password.isNotEmpty) {
        final encryptedBase64 =
            SimpleCrypto.xorEncryptDecrypt(fileContent, password);
        final encryptedMap = {
          'encrypted': true,
          'data': encryptedBase64,
          'export_time': DateTime.now().toIso8601String(),
        };
        fileContent = encoder.convert(encryptedMap);
      }

      await file.writeAsString(fileContent, encoding: utf8);
      return true;
    } catch (e) {
      debugPrint('导出备份数据失败: $e');
      return false;
    }
  }

  // 选择性导入数据 (支持可选密码解密)
  Future<bool> importSelectedData(
    String srcPath, {
    required bool includeFundsList,
    required bool includeHoldings,
    required bool includeSpecials,
    required bool includeStrategies,
    required bool includeSettings,
    required bool isMerge,
    String? password,
  }) async {
    try {
      final file = File(srcPath);
      if (!await file.exists()) return false;
      final content = await file.readAsString(encoding: utf8);
      Map<String, dynamic> backupMap = json.decode(content);

      // 如果数据是加密格式，尝试解密
      if (backupMap['encrypted'] == true) {
        final encryptedData = backupMap['data']?.toString() ?? '';
        if (password == null || password.isEmpty) {
          throw const FormatException('DECRYPT_REQUIRED');
        }
        final decryptedText = SimpleCrypto.xorDecrypt(encryptedData, password);
        if (decryptedText == null) {
          throw const FormatException('DECRYPT_FAILED');
        }
        backupMap = json.decode(decryptedText);
      }

      bool changed = false;
      final prefs = await SharedPreferences.getInstance();

      // 1. 如果是覆盖导入自选列表/持仓/特别关注，则需要先清空或重置它们
      if (!isMerge) {
        if (includeFundsList) {
          fundsInfo.clear();
          changed = true;
        } else {
          if (includeHoldings) {
            fundsInfo.forEach((code, info) {
              info.isHeld = false;
              info.amount = 0.0;
              info.yieldRate = 0.0;
            });
            changed = true;
          }
          if (includeSpecials) {
            fundsInfo.forEach((code, info) {
              info.isSpecial = false;
            });
            changed = true;
          }
        }
      }

      // 2. 导入自选基金列表
      if (includeFundsList && backupMap['funds_list'] != null) {
        final List list = backupMap['funds_list'];
        for (final item in list) {
          if (item is Map) {
            final String code = item['code'] ?? '';
            final String name = item['name'] ?? '';
            final String sector = item['sector'] ?? '其它';
            final bool isPinned = item['is_pinned'] ?? false;

            if (_fundCodeRegex.hasMatch(code)) {
              if (!fundsInfo.containsKey(code)) {
                fundsInfo[code] =
                    FundInfo(code: code, name: name, sector: sector);
              }
              fundsInfo[code]!.isPinned = isPinned;
              changed = true;
            }
          }
        }
      }

      // 3. 导入持仓数据
      if (includeHoldings && backupMap['holdings'] != null) {
        final List list = backupMap['holdings'];
        for (final item in list) {
          if (item is Map) {
            final String code = item['code'] ?? '';
            final double amount =
                double.tryParse(item['amount']?.toString() ?? '') ?? 0.0;
            final double yieldRate =
                double.tryParse(item['yield_rate']?.toString() ?? '') ?? 0.0;

            if (fundsInfo.containsKey(code)) {
              fundsInfo[code]!.isHeld = true;
              fundsInfo[code]!.amount = amount;
              fundsInfo[code]!.yieldRate = yieldRate;
              changed = true;
            } else if (isMerge && _fundCodeRegex.hasMatch(code)) {
              fundsInfo[code] = FundInfo(
                  code: code,
                  name: item['name'] ?? '未知基金',
                  sector: item['sector'] ?? '其它');
              fundsInfo[code]!.isHeld = true;
              fundsInfo[code]!.amount = amount;
              fundsInfo[code]!.yieldRate = yieldRate;
              changed = true;
            }
          }
        }
      }

      // 4. 导入特别关注列表
      if (includeSpecials && backupMap['specials'] != null) {
        final List list = backupMap['specials'];
        for (final code in list) {
          if (code is String && _fundCodeRegex.hasMatch(code)) {
            if (fundsInfo.containsKey(code)) {
              fundsInfo[code]!.isSpecial = true;
              changed = true;
            } else if (isMerge) {
              fundsInfo[code] =
                  FundInfo(code: code, name: '未知基金', sector: '其它');
              fundsInfo[code]!.isSpecial = true;
              changed = true;
            }
          }
        }
      }

      // 5. 导入系统全局设置
      if (includeSettings && backupMap['global_settings'] != null) {
        final Map<String, dynamic> settings = backupMap['global_settings'];
        if (settings['theme'] != null) themeMode = settings['theme'];
        if (settings['drop_days'] != null) {
          dropDays = List<int>.from(settings['drop_days']);
        }
        if (settings['percentile_months'] != null) {
          percentileMonths = List<int>.from(settings['percentile_months']);
        }
        if (settings['hidden_columns'] != null) {
          final Map<String, dynamic> hcMap = settings['hidden_columns'];
          hcMap.forEach((key, value) {
            hiddenColumns[key] = value != null ? List<String>.from(value) : [];
          });
        }

        // 密钥导入写入 SharedPreferences
        if (settings['zhipu_api_key'] != null) {
          zhipuApiKey = settings['zhipu_api_key'];
          await prefs.setString('zp_api_key', zhipuApiKey);
        }
        if (settings['zhipu_api_url'] != null) {
          zhipuApiUrl = settings['zhipu_api_url'];
        }
        if (settings['zhipu_model'] != null) {
          zhipuModel = settings['zhipu_model'];
        }

        if (settings['mimo_api_key'] != null) {
          mimoApiKey = settings['mimo_api_key'];
          await prefs.setString('mm_api_key', mimoApiKey);
        }
        if (settings['mimo_api_url'] != null) {
          mimoApiUrl = settings['mimo_api_url'];
        }
        if (settings['mimo_model'] != null) {
          mimoModel = settings['mimo_model'];
        }

        if (settings['custom_apis'] != null) {
          try {
            customApis = (settings['custom_apis'] as List)
                .map((e) => Map<String, String>.from(e as Map))
                .toList();
            for (var provider in customApis) {
              final id = provider['id'];
              final key = provider['key'] ?? '';
              if (id != null) {
                if (key.isNotEmpty) {
                  await prefs.setString('custom_api_key_$id', key);
                } else {
                  provider['key'] = prefs.getString('custom_api_key_$id') ?? '';
                }
              }
            }
          } catch (e) {
            debugPrint('解析导入的 custom_apis 失败: $e');
            customApis = [];
          }
        }

        if (settings['default_ocr_provider'] != null) {
          defaultOcrProvider = settings['default_ocr_provider'];
        }
        if (settings['freeze_columns'] != null) {
          freezeColumns = settings['freeze_columns'];
        }
        changed = true;
      }

      // 6. 导入回测寻优策略
      if (includeStrategies && backupMap['optimal_strategies'] != null) {
        final Map<String, dynamic> strategies = backupMap['optimal_strategies'];
        final db = FundHistoryDB();
        if (!isMerge) {
          await db.clearOptimalStrategies();
        }

        for (final entry in strategies.entries) {
          final String code = entry.key;
          final dynamic data = entry.value;
          if (data is Map && RegExp(r'^\d{6}$').hasMatch(code)) {
            await db.saveOptimalStrategy(
              fundCode: code,
              fundName: data['fund_name'] ?? '未知基金',
              buyDays: data['buy_days'] ?? 3,
              buyDrop:
                  double.tryParse(data['buy_drop']?.toString() ?? '') ?? 0.0,
              targetProfit:
                  double.tryParse(data['target_profit']?.toString() ?? '') ??
                      0.0,
              holdMin: data['hold_min'] ?? 0,
              holdMax: data['hold_max'] ?? 0,
              winRate:
                  double.tryParse(data['win_rate']?.toString() ?? '') ?? 0.0,
              totalTrades: data['total_trades'] ?? 0,
              avgProfit:
                  double.tryParse(data['avg_profit']?.toString() ?? '') ?? 0.0,
            );
          }
        }
      }

      if (changed) {
        await saveConfig();
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('导入备份数据失败: $e');
      rethrow; // 抛出异常供外部 UI 精确捕获解密等提示
    }
  }

  // 从云端同步数据 (支持可选的交互式冲突解决)
  Future<void> syncWithSupabase({
    Future<Map<String, SyncConflictResolution>> Function(List<SyncConflict>)?
        onConflict,
  }) async {
    if (SupabaseManager().isLoggedIn) {
      await SupabaseManager().syncFromCloud(onConflict: onConflict);
      notifyListeners();
    }
  }
}

class SimpleCrypto {
  /// 对输入数据使用基于密码生成的密钥流进行 XOR 加密/解密
  static String xorEncryptDecrypt(String input, String password) {
    if (password.isEmpty) return input;

    final List<int> inputBytes = utf8.encode(input);
    final List<int> passBytes = utf8.encode(password);

    // 生成混淆扩展密钥
    final List<int> keyStream = [];
    for (int i = 0; i < inputBytes.length; i++) {
      keyStream.add((passBytes[i % passBytes.length] + i * 17) ^ (i & 0xFF));
    }

    final List<int> resultBytes = List<int>.generate(inputBytes.length, (i) {
      return inputBytes[i] ^ keyStream[i];
    });

    return base64.encode(resultBytes);
  }

  static String? xorDecrypt(String base64Input, String password) {
    try {
      if (password.isEmpty) return null;
      final List<int> inputBytes = base64.decode(base64Input);
      final List<int> passBytes = utf8.encode(password);

      final List<int> keyStream = [];
      for (int i = 0; i < inputBytes.length; i++) {
        keyStream.add((passBytes[i % passBytes.length] + i * 17) ^ (i & 0xFF));
      }

      final List<int> resultBytes = List<int>.generate(inputBytes.length, (i) {
        return inputBytes[i] ^ keyStream[i];
      });

      return utf8.decode(resultBytes);
    } catch (_) {
      return null;
    }
  }
}
