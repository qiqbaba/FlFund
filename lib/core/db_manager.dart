import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqflite/sqflite.dart' as sqflite;

class FundHistoryDB {
  static final FundHistoryDB _instance = FundHistoryDB._internal();
  factory FundHistoryDB() => _instance;
  FundHistoryDB._internal();

  // ---- SQL 建表语句常量（Windows/Android 共用，消除重复） ----
  static const _sqlFundHistory = '''
    CREATE TABLE IF NOT EXISTS fund_history (
      fund_code TEXT PRIMARY KEY,
      jzrq TEXT,
      update_time REAL,
      ma120 REAL
    );
  ''';

  static const _sqlFundNavDetail = '''
    CREATE TABLE IF NOT EXISTS fund_nav_detail (
      fund_code TEXT,
      jzrq TEXT,
      dwjz REAL,
      ljjz REAL,
      PRIMARY KEY (fund_code, jzrq)
    );
  ''';

  static const _sqlNavDetailIndex = '''
    CREATE INDEX IF NOT EXISTS idx_fund_nav_detail_lookup 
    ON fund_nav_detail (fund_code, jzrq DESC);
  ''';

  static const _sqlOptimalStrategy = '''
    CREATE TABLE IF NOT EXISTS fund_optimal_strategy (
      fund_code TEXT PRIMARY KEY,
      fund_name TEXT,
      buy_days INTEGER,
      buy_drop REAL,
      target_profit REAL,
      hold_min INTEGER,
      hold_max INTEGER,
      win_rate REAL,
      total_trades INTEGER,
      avg_profit REAL,
      sell_x INTEGER,
      sell_win_rate REAL,
      sell_trades INTEGER,
      ma_period INTEGER,
      ma_envelope_pct REAL,
      rsi_filter_limit REAL,
      macd_filter_enabled INTEGER,
      pe_percentile_limit REAL,
      pb_percentile_limit REAL,
      stop_loss_pct REAL,
      trailing_drop_pct REAL,
      trailing_activate_pct REAL,
      short_hold_days INTEGER,
      short_hold_penalty_pct REAL,
      purchase_fee_pct REAL,
      slippage_pct REAL,
      max_grid_adds INTEGER,
      oos_validated INTEGER,
      update_time REAL
    );
  ''';

  static const _sqlAppMeta = '''
    CREATE TABLE IF NOT EXISTS app_meta (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  ''';

  // fund_optimal_strategy 表需要增量追加的列（列名, 类型）
  // 新增字段时只需在此处维护，无需同步修改 Win/Android 两端的升级函数
  static const _strategyColUpgrades = [
    ('sell_x', 'INTEGER'),
    ('sell_win_rate', 'REAL'),
    ('sell_trades', 'INTEGER'),
    ('ma_period', 'INTEGER'),
    ('ma_envelope_pct', 'REAL'),
    ('rsi_filter_limit', 'REAL'),
    ('macd_filter_enabled', 'INTEGER'),
    ('pe_percentile_limit', 'REAL'),
    ('pb_percentile_limit', 'REAL'),
    ('stop_loss_pct', 'REAL'),
    ('trailing_drop_pct', 'REAL'),
    ('trailing_activate_pct', 'REAL'),
    ('short_hold_days', 'INTEGER'),
    ('short_hold_penalty_pct', 'REAL'),
    ('purchase_fee_pct', 'REAL'),
    ('slippage_pct', 'REAL'),
    ('max_grid_adds', 'INTEGER'),
    ('oos_validated', 'INTEGER'),
  ];


  // SQLite 连接句柄
  sqlite.Database? _winDb;
  sqflite.Database? _androidDb;
  DbExecutor? _executor;

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  // 初始化数据库
  Future<void> init() async {
    final dbPath = await _getDatabasePath();
    if (_isWindows) {
      // Windows 使用 FFI sqlite3
      try {
        final winDb = sqlite.sqlite3.open(dbPath);
        _winDb = winDb;
        _executor = WinDbExecutor(winDb);
        _initSchemaWin();
        _upgradeSchemaWin();
      } catch (e) {
        debugPrint('Windows 数据库打开失败: $e');
      }
    } else {
      // Android/iOS 使用 sqflite
      try {
        final androidDb = await sqflite.openDatabase(
          dbPath,
          version: 1,
          onCreate: (db, version) async {
            await _initSchemaAndroid(db);
          },
        );
        _androidDb = androidDb;
        _executor = AndroidDbExecutor(androidDb);
        await _upgradeSchemaAndroid();
        try {
          await androidDb.rawQuery('PRAGMA journal_mode=WAL;');
        } catch (e) {
          debugPrint('Android 设置 WAL 模式失败: $e');
        }
      } catch (e) {
        debugPrint('Android 数据库打开失败: $e');
      }
    }
    await _cleanupFutureData();
  }

  // 升级数据库结构
  void _upgradeSchemaWin() {
    if (_winDb == null) return;
    try {
      final rows = _winDb!.select('PRAGMA table_info(fund_optimal_strategy)');
      final existingColumns = rows.map((row) => row['name'] as String).toSet();

      for (final (col, type) in _strategyColUpgrades) {
        if (!existingColumns.contains(col)) {
          _winDb!.execute('ALTER TABLE fund_optimal_strategy ADD COLUMN $col $type;');
        }
      }

      final histRows = _winDb!.select('PRAGMA table_info(fund_history)');
      final histColumns = histRows.map((row) => row['name'] as String).toSet();
      if (!histColumns.contains('ma120')) {
        _winDb!.execute('ALTER TABLE fund_history ADD COLUMN ma120 REAL;');
      }

      // fund_nav_detail 增补累计净值列（用于复权重建）
      final navRows = _winDb!.select('PRAGMA table_info(fund_nav_detail)');
      final navColumns = navRows.map((row) => row['name'] as String).toSet();
      if (!navColumns.contains('ljjz')) {
        _winDb!.execute('ALTER TABLE fund_nav_detail ADD COLUMN ljjz REAL;');
      }
    } catch (e) {
      debugPrint('Windows 升级数据库结构失败: $e');
    }
  }

  Future<void> _upgradeSchemaAndroid() async {
    if (_androidDb == null) return;
    try {
      final columns = await _androidDb!.rawQuery('PRAGMA table_info(fund_optimal_strategy)');
      final existingColumns = columns.map((col) => col['name'] as String).toSet();

      for (final (col, type) in _strategyColUpgrades) {
        if (!existingColumns.contains(col)) {
          await _androidDb!.execute('ALTER TABLE fund_optimal_strategy ADD COLUMN $col $type;');
        }
      }

      final histColumnsList = await _androidDb!.rawQuery('PRAGMA table_info(fund_history)');
      final histColumns = histColumnsList.map((col) => col['name'] as String).toSet();
      if (!histColumns.contains('ma120')) {
        await _androidDb!.execute('ALTER TABLE fund_history ADD COLUMN ma120 REAL;');
      }

      // fund_nav_detail 增补累计净值列（用于复权重建）
      final navColumnsList = await _androidDb!.rawQuery('PRAGMA table_info(fund_nav_detail)');
      final navColumns = navColumnsList.map((col) => col['name'] as String).toSet();
      if (!navColumns.contains('ljjz')) {
        await _androidDb!.execute('ALTER TABLE fund_nav_detail ADD COLUMN ljjz REAL;');
      }
    } catch (e) {
      debugPrint('Android 升级数据库结构失败: $e');
    }
  }

  // 获取数据库路径
  Future<String> _getDatabasePath() async {
    if (_isWindows) {
      // 1. 优先尝试当前工作目录 (开发调试阶段)
      final currPath = path.join(Directory.current.path, 'fund_history.db');
      if (await File(currPath).exists()) {
        return currPath;
      }
      // 2. 其次尝试可执行文件同级目录 (打包/双击运行发布版)
      try {
        final exeDir = path.dirname(Platform.resolvedExecutable);
        final exePath = path.join(exeDir, 'fund_history.db');
        if (await File(exePath).exists()) {
          return exePath;
        }
      } catch (_) {}
      
      // 3. Fallback: 默认返回当前工作目录下的文件位置
      return currPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      return path.join(docsDir.path, 'fund_history.db');
    }
  }

  // 初始化 Windows 表结构（引用共享 SQL 常量，与 Android 端保持同步）
  void _initSchemaWin() {
    _winDb!.execute('PRAGMA journal_mode=WAL;');
    _winDb!.execute(_sqlFundHistory);
    _winDb!.execute(_sqlFundNavDetail);
    _winDb!.execute(_sqlNavDetailIndex);
    _winDb!.execute(_sqlOptimalStrategy);
    _winDb!.execute(_sqlAppMeta);
  }

  // 初始化 Android 表结构（引用共享 SQL 常量，与 Windows 端保持同步）
  Future<void> _initSchemaAndroid(sqflite.Database db) async {
    await db.execute(_sqlFundHistory);
    await db.execute(_sqlFundNavDetail);
    await db.execute(_sqlNavDetailIndex);
    await db.execute(_sqlOptimalStrategy);
    await db.execute(_sqlAppMeta);
  }

  // 清理未来的脏数据
  Future<void> _cleanupFutureData() async {
    if (_executor == null) return;
    try {
      final nowStr = DateTime.now().toIso8601String().substring(0, 10);
      final lastCleanupStr = await getMeta('last_cleanup_time');
      final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;

      bool shouldCleanup = true;
      if (lastCleanupStr != null) {
        final lastTime = double.tryParse(lastCleanupStr) ?? 0.0;
        if (nowTime - lastTime < 86400) {
          shouldCleanup = false;
        }
      }

      if (shouldCleanup) {
        await _executor!.execute('DELETE FROM fund_nav_detail WHERE jzrq > ?', [nowStr]);
        await _executor!.execute('DELETE FROM fund_history WHERE jzrq > ?', [nowStr]);
        await saveMeta('last_cleanup_time', nowTime.toString());
      }
    } catch (e) {
      debugPrint('清理未来数据失败: $e');
    }
  }

  // ---------------- APP_META 读写 ----------------

  Future<String?> getMeta(String key) async {
    if (_executor == null) return null;
    final rows = await _executor!.query('SELECT value FROM app_meta WHERE key = ?', [key]);
    if (rows.isNotEmpty) {
      return rows.first['value'] as String?;
    }
    return null;
  }

  Future<void> saveMeta(String key, String value) async {
    if (_executor == null) return;
    await _executor!.execute(
      'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
      [key, value]
    );
  }

  // ---------------- 历史净值操作 ----------------

  // 获取单只基金历史净值（返回复权净值序列，消除分红除息跳空）
  Future<Map<String, dynamic>?> getHistory(String fundCode) async {
    if (_executor == null) return null;
    final List<String> dates = [];
    final List<double> dwjzs = [];
    final List<double> ljjzs = [];

    final rows = await _executor!.queryRows('''
      SELECT jzrq, dwjz, ljjz FROM fund_nav_detail 
      WHERE fund_code = ? 
      ORDER BY jzrq DESC
    ''', [fundCode]);

    for (final row in rows) {
      final double dwjz = (row[1] as num).toDouble();
      dates.add(row[0] as String);
      dwjzs.add(dwjz);
      // 旧数据或缺失累计净值时回退为单位净值（等价于不做复权调整）
      final ljjz = row[2] as num?;
      ljjzs.add(ljjz != null && ljjz.toDouble() > 0 ? ljjz.toDouble() : dwjz);
    }

    if (dates.isEmpty) return null;

    final List<double> navs = _buildAdjustedNavs(dwjzs, ljjzs);

    final histRows = await _executor!.query(
      'SELECT update_time, ma120 FROM fund_history WHERE fund_code = ?',
      [fundCode]
    );
    double updateTime = 0.0;
    double? ma120;
    if (histRows.isNotEmpty) {
      updateTime = (histRows.first['update_time'] as num?)?.toDouble() ?? 0.0;
      ma120 = (histRows.first['ma120'] as num?)?.toDouble();
    }

    return {
      'jzrq': dates.first,
      'navs': navs,
      'dates': dates,
      'update_time': updateTime,
      'ma120': ma120,
    };
  }

  // 由单位净值 + 累计净值重建前复权净值序列（列表均为从新到旧排列）。
  // 复权收益率 R = (LJJZ[t] - LJJZ[t-1]) / DWJZ[t-1]，等价于官方日增长率，
  // 以最新单位净值为锚点向历史回推，使最新值与实际单位净值一致（显示不受影响），
  // 而历史值消除分红除息的向下跳空。
  static List<double> _buildAdjustedNavs(
      List<double> dwjzs, List<double> ljjzs) {
    final int n = dwjzs.length;
    if (n == 0) return dwjzs;
    // 若累计净值与单位净值处处相等（无分红），无需复权，直接返回
    bool hasDividend = false;
    for (int i = 0; i < n; i++) {
      if ((ljjzs[i] - dwjzs[i]).abs() > 1e-9) {
        hasDividend = true;
        break;
      }
    }
    if (!hasDividend) return dwjzs;

    final adj = List<double>.filled(n, 0.0);
    adj[0] = dwjzs[0]; // 锚点：最新单位净值
    for (int i = 1; i < n; i++) {
      // i 更旧、i-1 更新：从旧到新的复权收益率
      final double prevDwjz = dwjzs[i];
      double factor = 1.0;
      if (prevDwjz > 0) {
        final double r = (ljjzs[i - 1] - ljjzs[i]) / prevDwjz;
        factor = 1.0 + r;
      }
      adj[i] = factor.abs() > 1e-9 ? adj[i - 1] / factor : adj[i - 1];
    }
    return adj;
  }

  // 保存基金历史数据
  Future<void> saveHistory(String fundCode, String jzrq, List<double> navs, [List<String>? dates, double? ma120, List<double>? ljjzs]) async {
    if (_executor == null) return;
    
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    String actualJzrq = jzrq;
    final bool hasLjjz = ljjzs != null && ljjzs.length == navs.length;

    await _executor!.transaction((txn) async {
      if (dates != null && dates.length == navs.length) {
        for (int i = 0; i < dates.length; i++) {
          if (dates[i].compareTo(todayStr) > 0) continue;
          await txn.execute(
            'INSERT OR REPLACE INTO fund_nav_detail (fund_code, jzrq, dwjz, ljjz) VALUES (?, ?, ?, ?)',
            [fundCode, dates[i], navs[i], hasLjjz ? ljjzs[i] : navs[i]]
          );
        }
        actualJzrq = dates.first;
      } else if (navs.isNotEmpty) {
        if (jzrq.compareTo(todayStr) <= 0) {
          await txn.execute(
            'INSERT OR REPLACE INTO fund_nav_detail (fund_code, jzrq, dwjz, ljjz) VALUES (?, ?, ?, ?)',
            [fundCode, jzrq, navs.first, hasLjjz ? ljjzs.first : navs.first]
          );
        }
      }

      final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      await txn.execute(
        'INSERT OR REPLACE INTO fund_history (fund_code, jzrq, update_time, ma120) VALUES (?, ?, ?, ?)',
        [fundCode, actualJzrq, nowTime, ma120]
      );
    });
  }

  // 增量更新已算好的 MA120
  Future<void> updateMa120(String fundCode, double ma120) async {
    if (_executor == null) return;
    await _executor!.execute(
      'UPDATE fund_history SET ma120 = ? WHERE fund_code = ?',
      [ma120, fundCode]
    );
  }

  // 保存策略参数寻优结果
  Future<void> saveOptimalStrategy({
    required String fundCode,
    required String fundName,
    int? buyDays,
    double? buyDrop,
    double? targetProfit,
    int? holdMin,
    int? holdMax,
    double? winRate,
    int? totalTrades,
    double? avgProfit,
    int? sellX,
    double? sellWinRate,
    int? sellTrades,
    int? maPeriod,
    double? maEnvelopePct,
    double? rsiFilterLimit,
    int? macdFilterEnabled,
    double? pePercentileLimit,
    double? pbPercentileLimit,
    double? stopLossPct,
    double? trailingDropPct,
    double? trailingActivatePct,
    int? shortHoldDays,
    double? shortHoldPenaltyPct,
    double? purchaseFeePct,
    double? slippagePct,
    int? maxGridAdds,
    int? oosValidated,
  }) async {
    if (_executor == null) return;
    final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    await _executor!.execute('''
      INSERT OR REPLACE INTO fund_optimal_strategy 
      (fund_code, fund_name, buy_days, buy_drop, target_profit, hold_min, hold_max, win_rate, total_trades, avg_profit, sell_x, sell_win_rate, sell_trades, ma_period, ma_envelope_pct, rsi_filter_limit, macd_filter_enabled, pe_percentile_limit, pb_percentile_limit, stop_loss_pct, trailing_drop_pct, trailing_activate_pct, short_hold_days, short_hold_penalty_pct, purchase_fee_pct, slippage_pct, max_grid_adds, oos_validated, update_time)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      fundCode, fundName, buyDays, buyDrop, targetProfit,
      holdMin, holdMax, winRate, totalTrades, avgProfit, sellX, sellWinRate, sellTrades, maPeriod, maEnvelopePct,
      rsiFilterLimit, macdFilterEnabled, pePercentileLimit, pbPercentileLimit,
      stopLossPct, trailingDropPct, trailingActivatePct, shortHoldDays, shortHoldPenaltyPct, purchaseFeePct, slippagePct, maxGridAdds, oosValidated,
      nowTime
    ]);
  }

  // 批量保存策略参数寻优结果
  Future<void> saveOptimalStrategies(List<Map<String, dynamic>> strategies) async {
    if (_executor == null || strategies.isEmpty) return;
    final double nowTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    await _executor!.transaction((txn) async {
      for (final s in strategies) {
        await txn.execute('''
          INSERT OR REPLACE INTO fund_optimal_strategy 
          (fund_code, fund_name, buy_days, buy_drop, target_profit, hold_min, hold_max, win_rate, total_trades, avg_profit, sell_x, sell_win_rate, sell_trades, ma_period, ma_envelope_pct, rsi_filter_limit, macd_filter_enabled, pe_percentile_limit, pb_percentile_limit, stop_loss_pct, trailing_drop_pct, trailing_activate_pct, short_hold_days, short_hold_penalty_pct, purchase_fee_pct, slippage_pct, max_grid_adds, oos_validated, update_time)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          s['fund_code'], s['fund_name'], s['buy_days'], s['buy_drop'], s['target_profit'],
          s['hold_min'], s['hold_max'], s['win_rate'], s['total_trades'], s['avg_profit'], s['sell_x'], s['sell_win_rate'], s['sell_trades'], s['ma_period'], s['ma_envelope_pct'],
          s['rsi_filter_limit'], s['macd_filter_enabled'], s['pe_percentile_limit'], s['pb_percentile_limit'],
          s['stop_loss_pct'], s['trailing_drop_pct'], s['trailing_activate_pct'], s['short_hold_days'], s['short_hold_penalty_pct'], s['purchase_fee_pct'], s['slippage_pct'], s['max_grid_adds'], s['oos_validated'],
          nowTime
        ]);
      }
    });
  }

  // 获取特定基金的策略参数
  Future<Map<String, dynamic>?> getOptimalStrategy(String fundCode) async {
    if (_executor == null) return null;
    final rows = await _executor!.query('''
      SELECT buy_days, buy_drop, target_profit, hold_min, hold_max, win_rate, total_trades, avg_profit, sell_x, sell_win_rate, sell_trades, ma_period, ma_envelope_pct, rsi_filter_limit, macd_filter_enabled, pe_percentile_limit, pb_percentile_limit, stop_loss_pct, trailing_drop_pct, trailing_activate_pct, short_hold_days, short_hold_penalty_pct, purchase_fee_pct, slippage_pct, max_grid_adds, oos_validated, update_time 
      FROM fund_optimal_strategy WHERE fund_code = ? AND buy_days IS NOT NULL
    ''', [fundCode]);

    if (rows.isNotEmpty) {
      final row = rows.first;
      return {
        'buy_days': (row['buy_days'] as num?)?.toInt(),
        'buy_drop': (row['buy_drop'] as num?)?.toDouble(),
        'target_profit': (row['target_profit'] as num?)?.toDouble(),
        'hold_min': (row['hold_min'] as num?)?.toInt(),
        'hold_max': (row['hold_max'] as num?)?.toInt(),
        'win_rate': (row['win_rate'] as num?)?.toDouble() ?? 0.0,
        'total_trades': (row['total_trades'] as num?)?.toInt() ?? 0,
        'avg_profit': (row['avg_profit'] as num?)?.toDouble() ?? 0.0,
        'sell_x': (row['sell_x'] as num?)?.toInt(),
        'sell_win_rate': (row['sell_win_rate'] as num?)?.toDouble(),
        'sell_trades': (row['sell_trades'] as num?)?.toInt(),
        'ma_period': (row['ma_period'] as num?)?.toInt(),
        'ma_envelope_pct': (row['ma_envelope_pct'] as num?)?.toDouble(),
        'rsi_filter_limit': (row['rsi_filter_limit'] as num?)?.toDouble(),
        'macd_filter_enabled': (row['macd_filter_enabled'] as num?)?.toInt(),
        'pe_percentile_limit': (row['pe_percentile_limit'] as num?)?.toDouble(),
        'pb_percentile_limit': (row['pb_percentile_limit'] as num?)?.toDouble(),
        'stop_loss_pct': (row['stop_loss_pct'] as num?)?.toDouble(),
        'trailing_drop_pct': (row['trailing_drop_pct'] as num?)?.toDouble(),
        'trailing_activate_pct': (row['trailing_activate_pct'] as num?)?.toDouble(),
        'short_hold_days': (row['short_hold_days'] as num?)?.toInt(),
        'short_hold_penalty_pct': (row['short_hold_penalty_pct'] as num?)?.toDouble(),
        'purchase_fee_pct': (row['purchase_fee_pct'] as num?)?.toDouble(),
        'slippage_pct': (row['slippage_pct'] as num?)?.toDouble(),
        'max_grid_adds': (row['max_grid_adds'] as num?)?.toInt(),
        'oos_validated': (row['oos_validated'] as num?)?.toInt(),
        'update_time': (row['update_time'] as num?)?.toDouble(),
      };
    }
    return null;
  }

  // 一次性获取所有策略参数
  Future<Map<String, Map<String, dynamic>>> getAllOptimalStrategies() async {
    if (_executor == null) return {};
    final Map<String, Map<String, dynamic>> result = {};

    final rows = await _executor!.query('''
      SELECT fund_code, fund_name, buy_days, buy_drop, target_profit, hold_min, hold_max, win_rate, total_trades, avg_profit, sell_x, sell_win_rate, sell_trades, ma_period, ma_envelope_pct, rsi_filter_limit, macd_filter_enabled, pe_percentile_limit, pb_percentile_limit, stop_loss_pct, trailing_drop_pct, trailing_activate_pct, short_hold_days, short_hold_penalty_pct, purchase_fee_pct, slippage_pct, max_grid_adds, oos_validated, update_time 
      FROM fund_optimal_strategy WHERE buy_days IS NOT NULL
    ''');

    for (final row in rows) {
      result[row['fund_code'] as String] = {
        'fund_name': row['fund_name'] as String? ?? '',
        'buy_days': (row['buy_days'] as num?)?.toInt(),
        'buy_drop': (row['buy_drop'] as num?)?.toDouble(),
        'target_profit': (row['target_profit'] as num?)?.toDouble(),
        'hold_min': (row['hold_min'] as num?)?.toInt(),
        'hold_max': (row['hold_max'] as num?)?.toInt(),
        'win_rate': (row['win_rate'] as num?)?.toDouble() ?? 0.0,
        'total_trades': (row['total_trades'] as num?)?.toInt() ?? 0,
        'avg_profit': (row['avg_profit'] as num?)?.toDouble() ?? 0.0,
        'sell_x': (row['sell_x'] as num?)?.toInt(),
        'sell_win_rate': (row['sell_win_rate'] as num?)?.toDouble(),
        'sell_trades': (row['sell_trades'] as num?)?.toInt(),
        'ma_period': (row['ma_period'] as num?)?.toInt(),
        'ma_envelope_pct': (row['ma_envelope_pct'] as num?)?.toDouble(),
        'rsi_filter_limit': (row['rsi_filter_limit'] as num?)?.toDouble(),
        'macd_filter_enabled': (row['macd_filter_enabled'] as num?)?.toInt(),
        'pe_percentile_limit': (row['pe_percentile_limit'] as num?)?.toDouble(),
        'pb_percentile_limit': (row['pb_percentile_limit'] as num?)?.toDouble(),
        'stop_loss_pct': (row['stop_loss_pct'] as num?)?.toDouble(),
        'trailing_drop_pct': (row['trailing_drop_pct'] as num?)?.toDouble(),
        'trailing_activate_pct': (row['trailing_activate_pct'] as num?)?.toDouble(),
        'short_hold_days': (row['short_hold_days'] as num?)?.toInt(),
        'short_hold_penalty_pct': (row['short_hold_penalty_pct'] as num?)?.toDouble(),
        'purchase_fee_pct': (row['purchase_fee_pct'] as num?)?.toDouble(),
        'slippage_pct': (row['slippage_pct'] as num?)?.toDouble(),
        'max_grid_adds': (row['max_grid_adds'] as num?)?.toInt(),
        'oos_validated': (row['oos_validated'] as num?)?.toInt(),
        'update_time': (row['update_time'] as num?)?.toDouble(),
      };
    }
    return result;
  }

  // 清空所有最优策略参数
  Future<void> clearOptimalStrategies() async {
    if (_executor == null) return;
    await _executor!.execute('DELETE FROM fund_optimal_strategy');
  }

  // 获取所有在库的历史基金代码
  Future<List<String>> getAllFundCodes() async {
    if (_executor == null) return [];
    final rows = await _executor!.query('SELECT fund_code FROM fund_history');
    return rows.map((row) => row['fund_code'] as String).toList();
  }

  // 关闭释放数据库连接
  Future<void> close() async {
    try {
      if (_executor != null) {
        _executor!.dispose();
      }
      if (_winDb != null) {
        _winDb!.dispose();
        _winDb = null;
        debugPrint('Windows SQLite 数据库连接已释放');
      }
      if (_androidDb != null) {
        await _androidDb!.close();
        _androidDb = null;
        debugPrint('Android SQLite 数据库连接已关闭');
      }
      _executor = null;
    } catch (e) {
      debugPrint('释放数据库资源时发生异常: $e');
    }
  }
}

// ---------------- 数据库执行抽象层与平台适配器 ----------------

abstract class DbExecutor {
  Future<void> execute(String sql, [List<Object?>? arguments]);
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? arguments]);
  Future<List<List<Object?>>> queryRows(String sql, [List<Object?>? arguments]);
  Future<void> transaction(Future<void> Function(DbExecutor txn) action);
  void dispose() {}
}

class WinDbExecutor implements DbExecutor {
  final sqlite.Database db;
  final Map<String, sqlite.PreparedStatement> _stmtCache = {};

  WinDbExecutor(this.db);

  sqlite.PreparedStatement _getStatement(String sql) {
    return _stmtCache.putIfAbsent(sql, () => db.prepare(sql));
  }

  @override
  void dispose() {
    for (final stmt in _stmtCache.values) {
      try {
        stmt.dispose();
      } catch (_) {}
    }
    _stmtCache.clear();
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (arguments != null && arguments.isNotEmpty) {
      final stmt = _getStatement(sql);
      stmt.execute(arguments);
    } else {
      db.execute(sql);
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? arguments]) async {
    final stmt = _getStatement(sql);
    final rows = stmt.select(arguments ?? []);
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  @override
  Future<List<List<Object?>>> queryRows(String sql, [List<Object?>? arguments]) async {
    final stmt = _getStatement(sql);
    final rows = stmt.select(arguments ?? []);
    return rows.map((row) => row.values.toList()).toList();
  }

  @override
  Future<void> transaction(Future<void> Function(DbExecutor txn) action) async {
    db.execute('BEGIN TRANSACTION;');
    try {
      await action(this);
      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }
}

class AndroidDbExecutor implements DbExecutor {
  final sqflite.Database db;
  AndroidDbExecutor(this.db);

  @override
  void dispose() {}

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await db.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? arguments]) async {
    return await db.rawQuery(sql, arguments);
  }

  @override
  Future<List<List<Object?>>> queryRows(String sql, [List<Object?>? arguments]) async {
    final rows = await db.rawQuery(sql, arguments);
    if (rows.isEmpty) return [];
    final keys = rows.first.keys.toList();
    return rows.map((row) => keys.map((k) => row[k]).toList()).toList();
  }

  @override
  Future<void> transaction(Future<void> Function(DbExecutor txn) action) async {
    await db.transaction((txn) async {
      final executor = AndroidTxnExecutor(txn);
      await action(executor);
    });
  }
}

class AndroidTxnExecutor implements DbExecutor {
  final sqflite.Transaction txn;
  AndroidTxnExecutor(this.txn);

  @override
  void dispose() {}

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    await txn.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? arguments]) async {
    return await txn.rawQuery(sql, arguments);
  }

  @override
  Future<List<List<Object?>>> queryRows(String sql, [List<Object?>? arguments]) async {
    final rows = await txn.rawQuery(sql, arguments);
    if (rows.isEmpty) return [];
    final keys = rows.first.keys.toList();
    return rows.map((row) => keys.map((k) => row[k]).toList()).toList();
  }

  @override
  Future<void> transaction(Future<void> Function(DbExecutor txn) action) async {
    await action(this);
  }
}

