import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'safe_compute.dart';

class FundRegistryItem {
  final String code;
  final String pinyinAbbr;
  final String name;
  final String type;
  final String pinyinFull;

  FundRegistryItem({
    required this.code,
    required this.pinyinAbbr,
    required this.name,
    required this.type,
    required this.pinyinFull,
  });
}

class PinyinSearch {
  static final PinyinSearch _instance = PinyinSearch._internal();
  factory PinyinSearch() => _instance;
  PinyinSearch._internal();

  final List<FundRegistryItem> _registry = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  // 供 compute 调用的静态解析函数，后台 Isolate 解析 JSON 并构造列表，避免卡死主线程
  static List<FundRegistryItem> _parseRegistryJson(String jsonStr) {
    final payload = json.decode(jsonStr);
    List rawList;
    if (payload is Map && payload.containsKey('data')) {
      rawList = payload['data'] as List;
    } else if (payload is List) {
      rawList = payload;
    } else {
      return [];
    }

    final List<FundRegistryItem> list = [];
    for (final item in rawList) {
      if (item is List && item.length >= 5) {
        list.add(
          FundRegistryItem(
            code: item[0]?.toString() ?? '',
            pinyinAbbr: item[1]?.toString().toLowerCase() ?? '',
            name: item[2]?.toString() ?? '',
            type: item[3]?.toString() ?? '',
            pinyinFull: item[4]?.toString().toLowerCase() ?? '',
          ),
        );
      }
    }
    return list;
  }

  // 初始化并加载 assets
  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final jsonStr =
          await rootBundle.loadString('assets/funds_registry_cache.json');
      final items = await safeCompute(_parseRegistryJson, jsonStr);
      _registry.clear();
      _registry.addAll(items);
      _isLoaded = true;
    } catch (e) {
      // 捕获异常，防止影响主应用加载
      debugPrint('[PinyinSearch] 基金字典加载失败: $e');
      _isLoaded = false;
    }
  }

  static bool _isNumeric(String s) {
    if (s.isEmpty) return false;
    for (int i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      if (code < 48 || code > 57) return false;
    }
    return true;
  }

  static bool _isAlpha(String s) {
    if (s.isEmpty) return false;
    for (int i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      if (code < 97 || code > 122) return false;
    }
    return true;
  }

  // 基金字典搜索逻辑 (拼音 / 缩写 / 代码 / 中文)
  List<FundRegistryItem> search(String query) {
    if (query.isEmpty) return [];

    final cleanQuery = query.trim().toLowerCase();
    final isNumeric = _isNumeric(cleanQuery);
    final isAlpha = _isAlpha(cleanQuery);

    final List<FundRegistryItem> results = [];
    final len = _registry.length;

    for (int i = 0; i < len; i++) {
      final item = _registry[i];
      if (isNumeric) {
        // 纯数字匹配代码
        if (item.code.contains(cleanQuery)) {
          results.add(item);
        }
      } else if (isAlpha) {
        // 纯英文匹配拼音首字母缩写或全拼
        if (item.pinyinAbbr.contains(cleanQuery) ||
            item.pinyinFull.contains(cleanQuery)) {
          results.add(item);
        }
      } else {
        // 中文匹配基金名
        if (item.name.contains(cleanQuery)) {
          results.add(item);
        }
      }

      // 限制联想搜索返回的最大结果条数
      if (results.length >= 100) break;
    }

    return results;
  }

  // 根据代码快速查找单只基金名称
  String getNameByCode(String code) {
    if (code == '006246') return '华夏中小企业100ETF联接A';
    if (code == '006247') return '华夏中小企业100ETF联接C';
    if (code == '014578') return '南方国证在线消费ETF联接A';
    if (code == '014579') return '南方国证在线消费ETF联接C';
    for (final item in _registry) {
      if (item.code == code) return item.name;
    }
    return code;
  }

  // 根据指数名称和代码为该指数找一个最匹配的场外联接基金代码
  String findFundForIndex(String indexCode, String indexName) {
    if (indexCode == '399005') return '006246'; // 华夏中小企业100ETF联接A（本地缓存缺失）
    if (indexCode == '399702') return '070023'; // 深证F120 -> 嘉实深证基本面120ETF联接A
    if (indexCode == '399361') return '014578'; // 在线消费 -> 南方国证在线消费ETF联接A
    if (indexCode == '000933') return '165519'; // 800医卫 -> 中信保诚中证800医药指数(LOF)A（"医卫"是"医药卫生"缩写，与基金名"医药"不匹配）
    if (!_isLoaded || _registry.isEmpty) return indexCode;

    // 清理关键词
    String cleanName = indexName
        .replaceAll('指数', '')
        .replaceAll('价格', '')
        .replaceAll('全收益', '')
        .replaceAll('成指', '')
        .replaceAll('财富', '')
        .replaceAll('等权', '')
        .trim();

    if (cleanName.isEmpty) return indexCode;

    // 常用别名替换
    if (cleanName.contains('中小100')) {
      cleanName = cleanName.replaceAll('中小100', '中小板');
    }
    if (cleanName.contains('证保')) {
      cleanName = cleanName.replaceAll('证保', '证券保险');
    }
    if (cleanName.contains('上证资源')) {
      cleanName = cleanName.replaceAll('上证资源', '上证自然资源');
    }

    final searchKeys = [indexCode, indexName, cleanName];

    // 第一优先级：含有 "联接"
    for (final key in searchKeys) {
      for (final item in _registry) {
        if (item.name.contains(key) &&
            item.name.contains('联接') &&
            !item.name.contains('后端')) {
          return item.code;
        }
      }
    }

    // 第二优先级：场外 ETF 基金 (代号开头 0, 16, 50, 2, 3 且含有 ETF)
    for (final key in searchKeys) {
      for (final item in _registry) {
        final isOtc = item.code.startsWith('0') ||
            item.code.startsWith('16') ||
            item.code.startsWith('50') ||
            item.code.startsWith('2') ||
            item.code.startsWith('3');
        if (item.name.contains(key) &&
            item.name.contains('ETF') &&
            isOtc &&
            !item.name.contains('后端')) {
          return item.code;
        }
      }
    }

    // 第三优先级：LOF 或者 指数 基金 (场外)
    for (final key in searchKeys) {
      for (final item in _registry) {
        final isOtc = item.code.startsWith('0') ||
            item.code.startsWith('16') ||
            item.code.startsWith('50');
        if (item.name.contains(key) &&
            (item.name.contains('LOF') || item.name.contains('指数')) &&
            isOtc &&
            !item.name.contains('后端')) {
          return item.code;
        }
      }
    }

    // 第四优先级：包含关键词的任何场外基金
    for (final key in searchKeys) {
      if (key == indexCode) continue; // 不使用指数纯数字代码去宽泛匹配
      for (final item in _registry) {
        final isOtc = item.code.startsWith('0') ||
            item.code.startsWith('16') ||
            item.code.startsWith('50');
        if (item.name.contains(key) && isOtc && !item.name.contains('后端')) {
          return item.code;
        }
      }
    }

    return indexCode; // 没找到则返回原指数代码
  }

  // 智能模糊匹配基金名称，返回最匹配的基金项
  FundRegistryItem? matchFundByName(String recognizeName,
      {bool preferClassC = false}) {
    if (!_isLoaded || _registry.isEmpty || recognizeName.trim().isEmpty) {
      return null;
    }

    final cleanName = recognizeName.trim().toLowerCase();

    // 1. 提取数字特征
    final Set<String> cleanNumbers =
        RegExp(r'\d+').allMatches(cleanName).map((m) => m.group(0)!).toSet();

    // 2. 提取份额后缀特征 (如 A, C 等)
    final cleanSuffix = _getSuffixLetter(cleanName);

    // 3. 确定筛选前缀，粗筛候选集。固定使用 2 字前缀以包含所有同公司或同指数的候选基金，避免略写被漏掉
    List<FundRegistryItem> candidates = [];
    if (cleanName.length >= 2) {
      final prefix = cleanName.substring(0, 2);
      candidates = _registry
          .where((item) => item.name.toLowerCase().contains(prefix))
          .toList();
    }

    // 如果通过前缀过滤没找到任何基金，则使用全量列表作为候选集（通常不应该发生）
    if (candidates.isEmpty) {
      candidates = List.from(_registry);
    }

    FundRegistryItem? bestMatch;
    double maxScore = -1.0;

    for (final item in candidates) {
      final targetName = item.name.toLowerCase();

      // a. 数字特征匹配：如果双方均有数字且数字集合不相同，说明不是同一只基金，直接排除
      final Set<String> targetNumbers =
          RegExp(r'\d+').allMatches(targetName).map((m) => m.group(0)!).toSet();
      if (cleanNumbers.isNotEmpty &&
          targetNumbers.isNotEmpty &&
          !_isSetEqual(cleanNumbers, targetNumbers)) {
        continue;
      }

      // b. 后缀份额匹配：如果两只基金都有后缀份额，但不同（如 C类 匹配到 A类），直接排除
      final targetSuffix = _getSuffixLetter(targetName);
      if (cleanSuffix != null &&
          targetSuffix != null &&
          cleanSuffix != targetSuffix) {
        continue;
      }

      // 方案 2：计算 LCS 相似度前，对对比双方进行去噪净化，突出核心关键字
      final cleanNameStripped = _stripFundNameForLCS(cleanName);
      final targetNameStripped = _stripFundNameForLCS(targetName);

      // c. 计算 LCS (最长公共子序列) 相似度
      final lcsLen = _computeLCS(cleanNameStripped, targetNameStripped);

      // 方案 1：如果输入是被截断的省略名，分母采用输入降噪后的实际长度，避免长官方名字惩罚
      final hasEllipsis = cleanName.contains('...') || cleanName.contains('…');
      final denom = hasEllipsis
          ? cleanNameStripped.length
          : (cleanNameStripped.length > targetNameStripped.length
              ? cleanNameStripped.length
              : targetNameStripped.length);

      if (denom == 0) continue;

      double score = lcsLen / denom;

      // 额外的微调规则：
      // 如果完全相等，给予满分并加分，确保绝对优先
      if (cleanNameStripped == targetNameStripped) {
        score += 0.2;
      } else if (cleanNameStripped.contains(targetNameStripped) ||
          targetNameStripped.contains(cleanNameStripped)) {
        // 包含关系稍微加分
        score += 0.05;
      }

      // 子序列包含关系（即其中一者是另一者的非连续子序列，且无字面冲突）
      final isSubsequence = lcsLen == cleanNameStripped.length ||
          lcsLen == targetNameStripped.length;
      if (isSubsequence) {
        score += 0.25;
      }

      // 如果份额后缀匹配成功（且都不为空），给予小幅度加分以防歧义
      if (cleanSuffix != null &&
          targetSuffix != null &&
          cleanSuffix == targetSuffix) {
        score += 0.02;
      }

      // 如果用户设置了优先选择C类基金，且截图中未识别出任何后缀，并且该候选基金是C类，给予小幅度加分
      if (preferClassC && cleanSuffix == null && targetSuffix == 'c') {
        score += 0.02;
      }

      if (score > maxScore) {
        maxScore = score;
        bestMatch = item;
      }
    }

    // 相似度阈值设为 0.45，低于此值认为不匹配
    if (maxScore >= 0.45) {
      return bestMatch;
    }

    return null;
  }

  // 为 LCS 匹配清洗名字，去除高频干扰和括号等词，缩短字符串以提升核心关键字的匹配权重
  String _stripFundNameForLCS(String name) {
    return name
        .replaceAll('...', '')
        .replaceAll('…', '')
        .replaceAll(RegExp(r'\(qdii.*?\)|（qdii.*?）'), '')
        .replaceAll(RegExp(r'\(lof\)|（lof）|\(etf.*?\)|（etf.*?）'), '')
        .replaceAll(RegExp(r'发起式|联接|联|混合|债券|指数|etf|lof|fof'), '')
        .replaceAll(RegExp(r'[\(\)（）\s]'), '');
  }

  // 提取份额后缀字母
  String? _getSuffixLetter(String name) {
    String clean = name.toLowerCase();
    // 先把常见的括号干扰项去掉，例如 (qdii), (qdii-lof) 等
    clean = clean.replaceAll(RegExp(r'\(qdii.*?\)|（qdii.*?）'), '');
    clean = clean.replaceAll(RegExp(r'\(lof\)|（lof）|\(etf.*?\)|（etf.*?）'), '');
    // 去除所有括号 and 空白
    clean = clean.replaceAll(RegExp(r'[\(\)（）\s]'), '');
    if (clean.isEmpty) return null;

    if (clean.endsWith('etf') ||
        clean.endsWith('lof') ||
        clean.endsWith('fof') ||
        clean.endsWith('qdii')) {
      return null;
    }

    final lastChar = clean.substring(clean.length - 1);
    if (RegExp(r'^[a-zA-Z]$').hasMatch(lastChar)) {
      if (lastChar == 'f') return null; // 排除 F 字母（多是 ETF / LOF / FOF 的误判）
      return lastChar;
    }
    return null;
  }

  // 计算 LCS 长度
  int _computeLCS(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 1)) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }
    return dp[m][n];
  }

  // 判断两个集合是否相等
  bool _isSetEqual(Set<dynamic> a, Set<dynamic> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  // 根据基金名称和原始分类，清洗提取出更具体好用的板块分类
  // 根据基金名称 and 原始分类，清洗提取出更具体好用的板块分类
  String getCleanSector(String name, String rawType) {
    // 1. 识别并清除已被污染的历史板块分类，防止被 broad 锁死机制误伤
    bool isPolluted = false;
    final String trimmedRaw = rawType.trim();
    if (trimmedRaw.endsWith('发起') ||
        trimmedRaw.contains('混合') ||
        trimmedRaw.contains('灵活配置') ||
        trimmedRaw.contains('期货') ||
        trimmedRaw.contains('LOF') ||
        trimmedRaw.contains('ETF') ||
        trimmedRaw == '沪港深' ||
        trimmedRaw == '港股通' ||
        trimmedRaw == '深港通' ||
        trimmedRaw == '沪港通' ||
        trimmedRaw == '沪深') {
      isPolluted = true;
    }

    // 如果板块名称中包含某些基金公司前缀且长度过长，说明该板块很可能是个基简称，不具聚合意义
    final List<String> checkPollutedComps = [
      '德邦',
      '华商',
      '国投',
      '中欧',
      '永赢',
      '易方达',
      '华夏',
      '广发',
      '富国',
      '招商',
      '嘉实',
      '南方',
      '博时',
      '鹏华',
      '汇添富',
      '天弘',
      '华安',
      '国泰'
    ];
    for (final comp in checkPollutedComps) {
      if (trimmedRaw.contains(comp) && trimmedRaw.length > 3) {
        isPolluted = true;
        break;
      }
    }

    if (isPolluted) {
      rawType = '其它';
    }

    // 如果是复杂的业绩基准（包含+和权重），只提取权重最大的主导部分，避免被次要成分误导
    if (name.contains('+') && (name.contains('%') || name.contains('*'))) {
      final parts = name.split('+');
      double maxWeight = -1;
      String mainPart = name;
      for (final part in parts) {
        final match = RegExp(r'(\d+)\s*%').firstMatch(part);
        if (match != null) {
          final weight = double.tryParse(match.group(1) ?? '0') ?? 0.0;
          if (weight > maxWeight) {
            maxWeight = weight;
            mainPart = part;
          }
        } else {
          final matchDecimal = RegExp(r'\*\s*(0\.\d+)').firstMatch(part);
          if (matchDecimal != null) {
            final weight = double.tryParse(matchDecimal.group(1) ?? '0') ?? 0.0;
            if (weight > maxWeight) {
              maxWeight = weight;
              mainPart = part;
            }
          }
        }
      }
      name = mainPart;
    }

    final List<String> matchCompanies = [
      '华夏',
      '易方达',
      '广发',
      '富国',
      '招商',
      '嘉实',
      '南方',
      '博时',
      '鹏华',
      '汇添富',
      '天弘',
      '华安',
      '国泰',
      '银华',
      '工银',
      '中欧',
      '平安',
      '华泰柏瑞',
      '永赢',
      '国联安',
      '景顺长城',
      '前海开源',
      '东方',
      '华宝',
      '摩根',
      '浦银安盛',
      '兴证全球',
      '万家',
      '大成',
      '建信',
      '中银',
      '德邦',
      '华商',
      '国投瑞银',
      '国投'
    ];

    String cleanName = name;
    for (final comp in matchCompanies) {
      cleanName = cleanName.replaceAll(comp, '');
    }
    cleanName = cleanName
        .replaceAll(
            RegExp(
                r'(发起式?|联接|指数|增强|增强型|LOF|ETF|FOF|QDII|混合型?|股票型?|债券型?|灵活配置|期货|期指|定开|期|基金|收益率?|比较|基准|利率|存款|\s)'),
            '')
        .replaceAll(RegExp(r'[\(\)（）\-\+\*\%]'), '');

    // 仅清除末尾的份额后缀单英文字母 (如 A, B, C, I, H 等)，避免误伤中段的 A500、A50
    cleanName = cleanName.replaceFirst(RegExp(r'[a-zA-Z]$'), '');

    // 港股系单独处理（需要二次匹配内部分类）
    if (cleanName.contains('恒生') ||
        cleanName.contains('港股通') ||
        cleanName.contains('港股')) {
      if (cleanName.contains('互联网')) return '港股互联网';
      if (cleanName.contains('创新药')) return '港股创新药';
      if (cleanName.contains('医药') ||
          cleanName.contains('医疗') ||
          cleanName.contains('药')) {
        return '港股医药';
      }
      if (cleanName.contains('消费50')) return '港股消费50';
      if (cleanName.contains('消费')) return '港股消费';
      if (cleanName.contains('红利')) return '港股红利';
      if (cleanName.contains('科技') || name.contains('科技')) {
        if (cleanName.contains('港股通') || name.contains('港股通')) {
          return '港股通科技';
        }
        return '恒生科技';
      }
      if (cleanName.contains('金融') ||
          cleanName.contains('银行') ||
          cleanName.contains('保险') ||
          cleanName.contains('证券') ||
          cleanName.contains('非银')) {
        return '港股金融';
      }
      if (cleanName.contains('汽车') || cleanName.contains('新能')) return '新能源汽车';
      if (cleanName.contains('专精特新')) return '专精特新';
      if (cleanName.contains('恒生') || name.contains('恒生')) return '恒生指数';
      return '港股';
    }

    // 数据驱动的关键词-分类映射表（顺序优先，越靠前优先级越高）
    // 每条规则：([关键词列表], '分类名称')
    const sectorRules = <(List<String>, String)>[
      // 1. 特定的细分行业 / 概念 / 主题板块 (优先匹配)
      (['中证消费50', '消费50'], '中证消费50'),
      (['港股消费50', '港股通消费50', '恒生消费50'], '港股消费50'),
      (['沪港深消费50'], '沪港深消费50'),
      (['主要消费'], '主要消费'),
      (['可选消费'], '可选消费'),
      (['白酒', '酒'], '白酒'),
      (['食品', '饮料'], '食品饮料'),
      (['家用电器', '家电', '电器'], '家电'),

      (['白银'], '白银'),
      (['黄金股', '黄金产业', '黄金股票', '沪深港黄金'], '黄金股'),
      (['黄金', '上海金'], '黄金'),
      (['金银珠宝', '珠宝'], '金银珠宝'),

      (['数字经济'], '数字经济'),
      (['人工智能', 'AI'], '人工智能'),
      (['科技智选'], '科技'),
      (['全球制造', '全球高端制造'], '全球制造'),
      (['先进制造'], '先进制造'),
      (['高端装备', '装备', '机床', '工业母机'], '高端装备'),

      (['半导体设备'], '半导体设备'),
      (['芯片', '集成电路'], '芯片'),
      (['半导体'], '半导体'),
      (['信息技术', '信息安全'], '信息技术'),

      (['港股通创新药', '港股创新药'], '港股创新药'),
      (['创新药', '生物医药'], '创新药'),
      (['医疗器械', '器械'], '医疗器械'),
      (['中药', '中医'], '中药'),
      (['医药', '医疗', '药', '生物'], '医药'),

      (['中证卫星', '卫星', '卫星通信'], '卫星通信'),
      (['航天航空', '航天', '航空', '航空航天', '国证航天航空'], '国证航空航天'),
      (['军工', '国防'], '军工'),

      (['800证券保险', '证券保险', '证保'], '证券保险'),
      (['金融服务', '金融优选', '金融'], '金融'),
      (['中证800证券', '800证券'], '中证800证券'),
      (['证券', '券商', '非银'], '证券'),
      (['保险'], '保险'),
      (['银行'], '银行'),

      (['新能源汽车', '新能车', '智能汽车', '汽车'], '新能源汽车'),
      (['电池', '锂电'], '锂电池'),
      (['光伏'], '光伏'),
      (['电网设备'], '电网设备'),
      (['智能电网'], '智能电网'),
      (['绿色电力', '电力', '电网'], '电力'),
      (['公用事业'], '公用事业'),

      (['稀有金属'], '稀有金属'),
      (['贵金属'], '贵金属'),
      (['煤炭'], '煤炭'),
      (['工业有色', '工业金属'], '工业金属'),
      (['有色金属', '有色', '金属'], '有色金属'),
      (['钢铁'], '钢铁'),
      (['新能源', '能源'], '新能源'),
      (['绿色低碳', '低碳', '碳中和', '气候变化', '气候', '环保'], '绿色低碳'),

      (['沪深300红利', '300红利'], '沪深300红利'),
      (['沪深300价值', '300价值'], '沪深300价值'),
      (['红利', '低波动', '低波', '高股息'], '红利'),
      (['原油'], '原油'),
      (['石油', '天然气', '油气', '石油石化', '石化'], '油气'),

      (['游戏', '动漫'], '游戏'),
      (['计算机', '软件'], '计算机'),
      (['通信', '5G'], '通信'),
      (['电子'], '电子'),
      (['港股通科技'], '港股通科技'),
      (['恒生科技'], '恒生科技'),
      (['互联科技'], '互联科技'),
      (['互联网'], '互联网'),
      (['东南亚'], '东南亚科技'),
      (['科技'], '科技'),

      (['机器人'], '机器人'),
      (['化工'], '化工'),
      (['畜牧', '养殖'], '畜牧'),
      (['农业', '粮食', '粮食产业'], '农业'),

      (['稀土', '稀土产业'], '稀有金属'),
      (['TMT'], 'TMT'),
      (['大数据', '云计算'], '大数据/云计算'),
      (['资源', '自然资源', '资源产业', 'A股资源'], '资源'),
      (['大宗商品', '商品ETF', '商品股票', '上证商品', '中证商品', '商品'], '大宗商品'),
      (['自由现金流', '现金流'], '自由现金流'),
      (['体育'], '体育'),

      (['基建'], '基建'),
      (['建材', '建筑材料'], '建材'),
      (['地产', '房地产'], '地产'),
      (['消费', '乐享生活', '品质生活', '美好生活', '健康生活'], '消费'),
      (['传媒'], '传媒'),

      // 2. 宽基指数 / 境外宽基 (放在最后匹配，防止特定行业基金因名称中包含宽基名称被错分类)
      (['沪深300'], '沪深300'),
      (['中证A500', 'A500'], 'A500'),
      (['中证A50', 'A50'], '中证A50'),
      (['双创50', '科创创业50', '科创创业'], '双创50'),
      (['创业板'], '创业板'),

      (['科创50', '科创板50'], '科创50'),
      (['科创100', '科创板100'], '科创100'),
      (['科创板200', '科创200'], '科创200'),
      (['新材料'], '新材料'),
      (['科创板', '科创'], '科创'),

      (['中证1000'], '中证1000'),
      (['中证500'], '中证500'),
      (['中证A100', 'A100'], 'A100'),

      (['纳斯达克100', '纳指100'], '纳斯达克100'),
      (['纳斯达克', '纳指'], '纳指'),
      (['标普500', '标普'], '标普500'),
      (['越南'], '越南'),
      (['日本'], '日本'),
      (['欧洲'], '欧洲'),
      (['印度'], '印度'),
      (['上证'], '上证'),
      (['北证50'], '北证50'),
    ];

    for (final rule in sectorRules) {
      final keywords = rule.$1;
      final sector = rule.$2;
      if (keywords.any((kw) => cleanName.contains(kw))) {
        return sector;
      }
    }

    // 原始分类为粗泛大类时，才允许用默认提取算法进行截取兜底
    final isRawBroad = rawType == '指数型-股票' ||
        rawType == '指数型-海外股票' ||
        rawType == '其它' ||
        rawType == '中证全指' ||
        rawType == '混合型' ||
        rawType == '股票型' ||
        rawType == '指数型' ||
        rawType == '联接基金';
    if (!isRawBroad && rawType.isNotEmpty) {
      return rawType;
    }

    // 如果是无特定行业的主动混合型/股票型基金，直接归纳为主动混合/主动股票板块，避免兜底提取出个基简称
    final isNameMixed = name.contains('混合') || name.contains('配置');
    final isNameStock = name.contains('股票') && !name.contains('指数');
    if (rawType == '混合型' || (rawType == '其它' && isNameMixed)) {
      return '主动混合';
    }
    if (rawType == '股票型' || (rawType == '其它' && isNameStock)) {
      return '主动股票';
    }

    // 兜底提取前进行前缀和数字代号的过滤，防止将“中证”、“沪深”等指数提供商或市场词当作板块
    String nameForFallback = cleanName;
    const prefixToSkip = [
      '中证',
      '国证',
      '沪深',
      '上证',
      '深证',
      '中债',
      '标普',
      '纳斯达克',
      '沪港深',
      '港股通',
      '深港通',
      '沪港通',
      '深港'
    ];
    for (final prefix in prefixToSkip) {
      if (nameForFallback.startsWith(prefix)) {
        nameForFallback = nameForFallback.substring(prefix.length);
        break;
      }
    }
    // 过滤掉开头的纯数字和字母代号 (如 800, 300, A500)
    nameForFallback = nameForFallback.replaceFirst(RegExp(r'^[\d\w]+'), '');

    final reg = RegExp(r'^([^\d\w]{2,4})');
    final match = reg.firstMatch(nameForFallback);
    if (match != null) {
      return match.group(1)!;
    } else if (nameForFallback.isNotEmpty) {
      return nameForFallback.substring(
          0, nameForFallback.length > 4 ? 4 : nameForFallback.length);
    }
    return rawType;
  }
}
