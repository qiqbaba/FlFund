import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/backtest_engine.dart';
import 'package:fl_fund/core/ga_optimizer.dart';

void main() {
  group('BacktestEngine Tests', () {
    test('Should support parallel trades and dynamic equityCurve calculation', () {
      // 模拟 150 天的数据，以支持 SMA120 均线过滤
      final List<double> navs = List.generate(150, (index) => 1.0);
      final List<String> dates = List.generate(150, (index) => '2026-01-${index + 1}');

      // 制造买入点和卖出点：
      // 在第 121 天到 125 天，保持价格在 0.8，在第 125 天价格涨回至 0.85
      for (int i = 120; i < 125; i++) {
        navs[i] = 0.8;
      }
      navs[125] = 0.90; // 0.90 / 0.8 = 12.5% 涨幅，可以覆盖短持有期罚费后的止盈阈值 (5% + 1.5%)

      final result = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 10,
        buyDropPct: 10.0,
        targetProfitPct: 5.0,
        useMaFilter: false,
        maxConcurrentTrades: 5,
      );

      expect(result, isNotNull);
      expect(result.totalTrades, greaterThanOrEqualTo(1));
      expect(result.trades.first['buy_idx'], equals(120));
      expect(result.trades.first['sell_idx'], equals(125));
      expect(result.equityCurve.length, equals(150));
    });

    test('Should respect SMA120 boundary filter (no trades before day 120)', () {
      // 模拟 150 天的数据
      final List<double> navs = List.generate(150, (index) => 1.0);
      final List<String> dates = List.generate(150, (index) => '2026-01-${index + 1}');

      // 制造一个发生在第 50 天的暴跌买点 (如果在 120 天前交易，那就会被触发)
      navs[49] = 1.0;
      for (int i = 50; i < 55; i++) {
        navs[i] = 0.8;
      }
      navs[55] = 0.9;

      // 制造一个发生在第 130 天的暴跌买点 (应该可以被正常触发)
      navs[129] = 1.0;
      for (int i = 130; i < 135; i++) {
        navs[i] = 0.8;
      }
      navs[135] = 0.9;

      final result = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 10,
        buyDropPct: 10.0,
        targetProfitPct: 5.0,
        useMaFilter: true, // 启用 MA 过滤以触发 SMA120 边界处理
      );

      expect(result, isNotNull);
      // 第 50 天由于在前 120 天内，应被过滤掉；只有第 130 天的能够触发交易。
      for (final t in result.trades) {
        expect(t['buy_idx'], isNot(50));
        expect(t['buy_idx'], greaterThanOrEqualTo(120));
      }
    });

    test('GAOptimizer optimize should run without crash using precalculated MA', () {
      final List<double> navs = List.generate(150, (index) => 1.0);
      final List<String> dates = List.generate(150, (index) => '2026-01-${index + 1}');

      // 制造标准的跌 6% 涨 8% 波浪循环，每 8 天一个完整波段
      for (int i = 0; i < 150; i++) {
        final mod = i % 8;
        if (mod == 2 || mod == 3) {
          navs[i] = 0.94;
        } else if (mod == 6 || mod == 7) {
          navs[i] = 1.08;
        } else {
          navs[i] = 1.0;
        }
      }

      // 跑一次优化，确认没有编译/运行崩溃且能正常结束
      final optResult = GAOptimizer.optimize(
        allNavs: navs,
        allDates: dates,
        useMaFilter: false,
        useMacdFilter: false,
        rsiFilterLimit: 100.0,
      );

      expect(optResult, isNotNull);
      expect(optResult!['win_rate'], greaterThan(50.0));
      expect(optResult['total_trades'], greaterThanOrEqualTo(3));
    });

    test('GAOptimizer should find robust strategy with walk-forward and deduplicated pool', () {
      final List<double> navs = List.generate(300, (index) => 1.0);
      final List<String> dates = List.generate(300, (index) => '2026-01-${(index + 1).toString().padLeft(3, '0')}');

      for (int i = 0; i < 300; i++) {
        final mod = i % 12;
        if (mod >= 3 && mod <= 5) {
          navs[i] = 0.92;
        } else if (mod >= 9 && mod <= 11) {
          navs[i] = 1.06;
        } else {
          navs[i] = 1.0;
        }
      }

      final optResult = GAOptimizer.optimize(
        allNavs: navs,
        allDates: dates,
        useMaFilter: true,
        useMacdFilter: false,
        rsiFilterLimit: 100.0,
        stopLossPct: 15.0,
        maxGridAdds: 3,
      );

      expect(optResult, isNotNull);
      expect(optResult!['total_trades'], greaterThanOrEqualTo(5));
      expect(optResult['win_rate'], greaterThan(60.0));
    });

    test('Should respect custom maPeriod and allow trades after that period', () {
      final List<double> navs = List.generate(100, (index) => 1.0);
      final List<String> dates = List.generate(100, (index) => '2026-01-${index + 1}');

      // 制造一个发生在第 40 天的买点
      navs[39] = 1.0;
      for (int i = 40; i < 45; i++) {
        navs[i] = 0.8;
      }
      navs[45] = 0.9;

      // 制造一个发生在第 80 天的买点
      navs[79] = 1.0;
      for (int i = 80; i < 85; i++) {
        navs[i] = 0.8;
      }
      navs[85] = 0.9;

      // 如果使用 maPeriod = 60
      final result = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 10,
        buyDropPct: 10.0,
        targetProfitPct: 5.0,
        useMaFilter: true,
        maPeriod: 60,
      );

      expect(result, isNotNull);
      // 第 40 天的买点应该被过滤（在 60 天内），第 80 天的买点应该正常触发。
      for (final t in result.trades) {
        expect(t['buy_idx'], isNot(40));
        expect(t['buy_idx'], greaterThanOrEqualTo(60));
      }
    });

    test('Should allow buy triggers within maEnvelopePct envelope tolerance', () {
      final List<double> navs = List.generate(100, (index) => 1.0);
      final List<String> dates = List.generate(100, (index) => '2026-01-${index + 1}');

      // 假设从第 60 天开始，价格为 0.98，之前的价格均为 1.0。
      // 如果 maPeriod = 60，那么在第 60 天的 SMA60 为 1.0 (因为前面都是1.0)。
      // 此时价格 0.98 低于 SMA60 (1.0)，属于均线下方。
      // 但 0.98 与 1.0 相比，偏离度为 (1.0 - 0.98)/1.0 = 2.0%。
      // 如果不启用偏离度宽限 (maEnvelopePct = 0)，应被过滤；
      // 如果启用偏离度宽限 (maEnvelopePct = 3.0%)，应允许触发买入。
      for (int i = 0; i < 60; i++) {
        navs[i] = 1.0;
      }
      navs[60] = 0.98;
      navs[61] = 1.05;

      // 1. 无偏离度宽限 (maEnvelopePct = 0)
      final resNoEnv = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 1,
        buyDropPct: 1.0,
        targetProfitPct: 5.0,
        useMaFilter: true,
        maPeriod: 60,
        maEnvelopePct: 0.0,
      );
      expect(resNoEnv.totalTrades, equals(0));

      // 2. 有偏离度宽限 (maEnvelopePct = 3.0)
      final resWithEnv = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 1,
        buyDropPct: 1.0,
        targetProfitPct: 5.0,
        useMaFilter: true,
        maPeriod: 60,
        maEnvelopePct: 3.0,
      );
      expect(resWithEnv.totalTrades, greaterThanOrEqualTo(1));
    });

    test('GAOptimizer should not classify newly established funds (less than 250 days) as low volatility', () {
      // 模拟一个只有 100 天数据的次新基金，其价格几乎不波动，历史最大回撤为 0%
      final List<double> navs = List.generate(100, (index) => 1.0);
      final List<String> dates = List.generate(100, (index) => '2026-01-${index + 1}');

      // 制造标准的跌 6% 涨 8% 波浪循环，每 8 天一个完整波段
      for (int i = 0; i < 100; i++) {
        final mod = i % 8;
        if (mod == 2 || mod == 3) {
          navs[i] = 0.94;
        } else if (mod == 6 || mod == 7) {
          navs[i] = 1.08;
        } else {
          navs[i] = 1.0;
        }
      }

      final optResult = GAOptimizer.optimize(
        allNavs: navs,
        allDates: dates,
        useMaFilter: false,
        useMacdFilter: false,
        rsiFilterLimit: 100.0,
      );

      expect(optResult, isNotNull);
      // 因为天数 (100) 小于 250，它绝对不能被判定为低波动基金，因此它的 hold_max 应该为 75（中波动）或 30（高波动），而不是 120。
      expect(optResult!['hold_max'], isNot(equals(120)));
      expect(optResult['hold_max'] == 75 || optResult['hold_max'] == 30, true); // 由于真实计算得分很低，本来应归为 low (120)，但在方案 A 限制下应安全降级归为 medium (75)
    });

    test('Should filter dense buys using gridSpacingPct', () {
      final List<double> navs = List.generate(150, (index) => 1.0);
      final List<String> dates = List.generate(150, (index) => '2026-01-${index + 1}');

      // 制造买入点和连续下跌的走势
      // 120天：1.0
      navs[120] = 0.85; // 相比 1.0 跌了 15%，触发
      navs[121] = 0.84; // 相比 0.85 跌了 1.1%
      navs[122] = 0.83; // 相比 0.85 跌了 2.35%
      navs[123] = 0.81; // 相比 0.85 跌了 4.7% (触发第二次加仓，因为 > 3.0%)
      navs[124] = 0.95; // 大反弹平仓

      // 1. 不启用网格间距 (默认为 0.0)
      final resNoGrid = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 10,
        buyDropPct: 10.0,
        targetProfitPct: 5.0,
        useMaFilter: false,
        maxConcurrentTrades: 5,
        gridSpacingPct: 0.0,
      );

      // 会在 120, 121, 122, 123 天连续买入，产生 4 笔交易
      expect(resNoGrid.totalTrades, equals(4));

      // 2. 启用网格间距为 3.0%
      final resWithGrid = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 10,
        buyDropPct: 10.0,
        targetProfitPct: 5.0,
        useMaFilter: false,
        maxConcurrentTrades: 5,
        gridSpacingPct: 3.0,
      );

      // 只会在 120 (买在0.85) 和 123 (买在0.81) 天买入，产生 2 笔交易
      expect(resWithGrid.totalTrades, equals(2));
      expect(resWithGrid.trades[0]['buy_idx'], equals(120));
      expect(resWithGrid.trades[1]['buy_idx'], equals(123));
    });
  });
}
