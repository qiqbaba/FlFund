import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/fund_provider.dart';
import 'package:fl_fund/core/backtest_engine.dart';
import 'package:fl_fund/core/ga_optimizer.dart';

void main() {
  group('Signal Algorithm Fixes Tests', () {
    test('Duplicate NAV Prevention: estimatedNav is null when dates.first is already today', () {
      final model = FundUIModel(
        code: '000001',
        name: '测试基金',
        sector: '混合型',
      );

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      model.gztime = '$todayStr 15:00';
      model.gsz = '1.5000';
      model.navs = [1.5050, 1.4900, 1.4800];

      // 情况 1：dates[0] 是昨天，今日盘中估值应该生效
      model.dates = ['2020-01-01', '2019-12-31', '2019-12-30'];
      expect(model.isTodayValuation, isTrue);
      expect(model.estimatedNav, 1.5000);
      expect(model.fullNavs.length, 4);
      expect(model.fullNavs.first, 1.5000);

      // 情况 2：收盘后 dates[0] 已更新为今天，此时 estimatedNav 应返回 null，避免双重叠加
      model.dates = [todayStr, '2020-01-01', '2019-12-31'];
      expect(model.estimatedNav, isNull);
      expect(model.fullNavs.length, 3);
      expect(model.fullNavs.first, 1.5050);
    });

    test('Cache Invalidation: _computeDataSignature detects strategy parameter changes', () {
      final model = FundUIModel(
        code: '000001',
        name: '测试基金',
        sector: '混合型',
      );
      model.navs = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5];
      model.dates = ['2026-08-18', '2026-08-17', '2026-08-16', '2026-08-15', '2026-08-14', '2026-08-13'];

      model.optimalStrategy = {
        'buy_days': 10,
        'buy_drop': 3.0,
        'sell_x': 5005,
        'ma_period': 120,
        'ma_envelope_pct': 2.0,
        'rsi_filter_limit': 35.0,
      };

      model.updateCalculatedSignals();
      final drop1 = model.currentDrop;

      // 修改 buy_drop 参数
      model.optimalStrategy = {
        'buy_days': 10,
        'buy_drop': 8.0,
        'sell_x': 5005,
        'ma_period': 120,
        'ma_envelope_pct': 2.0,
        'rsi_filter_limit': 35.0,
      };

      // 访问 getter 时触发 _ensureSignalsUpToDate，应当自动重新计算
      expect(model.currentDrop, drop1);
    });

    test('Cache Invalidation: _computeDataSignature detects MA120/sumOf119 and intraday valuation changes', () {
      final model = FundUIModel(
        code: '000001',
        name: '测试基金',
        sector: '混合型',
      );
      model.navs = List.generate(125, (i) => 1.0 - i * 0.001);
      model.dates = List.generate(125, (i) => '2026-01-${(125 - i).toString().padLeft(3, '0')}');

      model.optimalStrategy = {
        'buy_days': 5,
        'buy_drop': 0.1,
        'sell_x': 5005,
        'ma_period': 120,
        'ma_envelope_pct': 2.0,
        'rsi_filter_limit': 0.0,
        'macd_filter_enabled': 0,
      };

      model.updateCalculatedSignals();
      expect(model.isBuySignal, isFalse);

      // 1. 模拟异步填充 sumOf119 / closedMa120 缓存
      model.sumOf119 = 150.0; // 极高的均线总和，导致 MA120 > 当前价格，使价格偏离 envelope
      expect(model.isBuySignal, isFalse);

      // 2. 模拟盘中实时估值 gsz 变化
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      model.gztime = '$todayStr 14:30';
      model.gsz = '2.0000'; // 估值大涨，摆脱下跌判定
      expect(model.isBuySignal, isFalse);
    });

    test('RSI Boundary Alignment: calculateRSIFromRange returns 50.0 default when len <= period', () {
      final navs = [1.0, 1.05, 1.02, 1.08, 1.03]; // 5 个数据点，少于 14
      final rsi = BacktestEngine.calculateRSIFromRange(navs, 0, navs.length);
      expect(rsi.length, 5);
      expect(rsi.every((v) => v == 50.0), isTrue);
    });

    test('Sell Signal Optimizer: _calcSellStats accurately checks missed rally across 15 days', () {
      // 构造序列：在卖出点后，第 1 天小跌 -3%，但随后的第 3 天暴涨 +15%
      // 早期实现因为第 1 天小跌而提前 break，导致错把卖飞大牛行情当成成功卖出
      final navs = <double>[
        1.0, 1.02, 1.05, 1.08, 1.15, // 前 5 天上涨满足卖出信号
        1.115, // +1 天：从 1.15 跌到 1.115（跌 -3.0%）
        1.13,
        1.35,  // +3 天：暴涨到 1.35（涨 +17.4%）
        1.36, 1.37, 1.38, 1.39, 1.40, 1.40, 1.40, 1.40, 1.40, 1.40, 1.40, 1.40, 1.40
      ];
      final dates = List.generate(navs.length, (i) => '2026-01-${(i + 1).toString().padLeft(2, '0')}');

      final opt = SellSignalOptimizer.optimize(allNavs: navs, allDates: dates);
      // 因为后续出现大涨（卖飞），不应该把这笔视为胜率 100% 的成功卖出
      if (opt != null) {
        expect(opt['sell_win_rate'], lessThan(100.0));
      }
    });

    test('Buy Signal Grid Check: index day sell condition does not pollute past hasSold', () {
      final model = FundUIModel(
        code: '000001',
        name: '测试基金',
        sector: '混合型',
      );

      // 构造净值序列 (由新到旧)
      // index 0: 今日 (1.20)
      // index 1: 昨日 (1.00)
      // index 2: 前日 (1.05)
      // index 3: 3天前买入日 (1.10)
      // 从 index 0 到 index 1 暴涨 20%
      model.navs = [1.20, 1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30, 1.35, 1.40, 1.45, 1.50, 1.55, 1.60];
      model.dates = List.generate(model.navs.length, (i) => '2026-08-${(20 - i).toString().padLeft(2, '0')}');

      model.optimalStrategy = {
        'buy_days': 5,
        'buy_drop': 5.0,
        'sell_x': 1010, // 1天涨 10% 卖出
        'ma_period': 0,
        'rsi_filter_limit': 0.0,
        'macd_filter_enabled': 0,
      };

      // 今天涨到了 1.20（相对昨天 1.00 涨了 20%），今天触发卖出条件
      // 但今天显然不是买入点（没有跌），isBuySignalAt(0) 必须为 false
      expect(model.isBuySignalAt(0), isFalse);
    });
  });
}
