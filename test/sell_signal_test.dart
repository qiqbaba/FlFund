import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/fund_provider.dart';
import 'package:fl_fund/core/ga_optimizer.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SellSignalOptimizer Tests', () {
    test('Should find optimal x correctly when simulated data has sell signals and drop', () {
      // 模拟 120 天的数据，以满足 length >= 30 且支持 3 次去重后的信号
      // 从远到近排列
      final List<double> navs = List.generate(120, (index) => 1.0);
      final List<String> dates = List.generate(120, (index) => '2026-01-${index + 1}');

      // 设 x = 5，我们制造 3 次大于等于 5% 的涨幅，且随后 10 天内均跌幅大于 2%
      // 第一次：从 index 0 到 index 5 涨到 1.06
      navs[0] = 1.0;
      navs[5] = 1.06;
      navs[8] = 0.95;

      // 第二次：从 index 16 到 index 21 涨到 1.06
      navs[16] = 1.0;
      navs[21] = 1.06;
      navs[24] = 0.95;

      // 第三次：从 index 32 到 index 37 涨到 1.06
      navs[32] = 1.0;
      navs[37] = 1.06;
      navs[40] = 0.95;

      final result = SellSignalOptimizer.optimize(allNavs: navs, allDates: dates);
      
      expect(result, isNotNull);
      expect(result!['sell_x'], isNotNull);
      final int encodedVal = result['sell_x'];
      final int sellX = encodedVal >= 100 ? encodedVal ~/ 1000 : encodedVal;
      final double sellPct = encodedVal >= 100 ? (encodedVal % 1000).toDouble() : encodedVal.toDouble();
      expect(sellX >= 3 && sellX <= 20, true);
      expect(sellPct >= 2.0 && sellPct <= 15.0, true);
      expect(result['sell_win_rate'] > 0.0, true);
      expect(result['sell_trades'] >= 1, true);
    });

    test('Should return null if nav data is too short', () {
      final List<double> navs = List.generate(20, (index) => 1.0);
      final List<String> dates = List.generate(20, (index) => '2026-01-${index + 1}');
      final result = SellSignalOptimizer.optimize(allNavs: navs, allDates: dates);
      expect(result, isNull);
    });
  });

  group('FundUIModel Sell Signal Property Tests', () {
    test('isSellSignal should compute correctly based on optimalStrategy', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      
      // navs 从近到远排列：index 0 是最新，index 5 是 5 天前
      // 5天前净值 = 1.0，最新净值 = 1.06，涨幅 6% >= 5%
      model.navs = [1.06, 1.01, 1.02, 1.01, 1.00, 1.00, 1.00]; 
      model.gztime = ''; // 非今日估值
      
      // 设置最优策略
      model.optimalStrategy = {
        'sell_x': 5,
        'sell_win_rate': 80.0,
        'sell_trades': 10,
      };

      // 此时 sell_x = 5, baseNav = 1.00, current = 1.06, 涨幅为 6.0% >= 5.0%
      expect(model.currentRise, closeTo(6.0, 0.001));
      expect(model.isSellSignal, true);

      // 如果最新净值没涨那么多（比如 1.04，涨幅 4.0% < 5%）
      model.navs[0] = 1.04;
      expect(model.currentRise, closeTo(4.0, 0.001));
      expect(model.isSellSignal, false);
    });

    test('isSellSignal should respect today valuation when gsz is available', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      
      // navs: index 0 是上一交易日净值，最新估值是今天。
      model.navs = [1.00, 1.00, 1.00, 1.00, 1.00, 1.00]; 
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      model.gztime = '$todayStr 15:00 [EastMoneyGz]';
      model.gsz = '1.06'; // 估值上涨 6%
      
      model.optimalStrategy = {
        'sell_x': 5,
        'sell_win_rate': 80.0,
        'sell_trades': 10,
      };

      // 此时 fullNavs.first = 1.06, fullNavs[5] = 1.00, 涨幅为 6.0%
      expect(model.isTodayValuation, true);
      expect(model.currentRise, closeTo(6.0, 0.001));
      expect(model.isSellSignal, true);
    });

    test('isSellSignal should compute correctly based on packed optimalStrategy', () {
      final model = FundUIModel(code: '000001', name: 'Test Fund', sector: 'Tech');
      
      // sell_x = 5 天, sellPct = 8% -> packed value = 5008
      model.optimalStrategy = {
        'sell_x': 5008,
        'sell_win_rate': 80.0,
        'sell_trades': 10,
      };

      // 5天前净值为 1.0，最新净值为 1.09，涨幅 9.0% >= 8.0%
      model.navs = [1.09, 1.01, 1.02, 1.01, 1.00, 1.00, 1.00];
      expect(model.currentRise, closeTo(9.0, 0.001));
      expect(model.isSellSignal, true);

      // 如果最新净值没涨那么多（如 1.07，涨幅 7.0% < 8.0%）
      model.navs[0] = 1.07;
      expect(model.currentRise, closeTo(7.0, 0.001));
      expect(model.isSellSignal, false);
    });

    test('currentRise should align with effectiveSellX when position buy point is more recent than sell_x', () {
      final model = FundUIModel(code: '000004', name: 'Test Alignment Fund', sector: 'Tech');
      
      // 策略：5天跌5%买入，20天涨5%卖出 (sell_x = 20005)
      model.optimalStrategy = {
        'buy_days': 5,
        'buy_drop': 5.0,
        'sell_x': 20005,
        'ma_period': 0,
        'rsi_filter_limit': 0.0,
        'macd_filter_enabled': 0,
      };

      // 构造净值数据（从近到远，总共 30 天）：
      // index 0 (今日): 1.06
      // index 1: 1.04
      // index 2: 1.02
      // index 3 (3天前买入日): 1.00 (相比更早高点 1.08 跌 7.4% 触发买入)
      // index 8 (8天前高点): 1.08
      // index 20 (20天前高位): 1.20
      model.navs = List.generate(30, (index) {
        if (index == 0) return 1.06;
        if (index == 1) return 1.04;
        if (index == 2) return 1.02;
        if (index == 3) return 1.00;
        if (index <= 8) return 1.08;
        if (index == 20) return 1.20;
        return 1.10;
      });

      // 验证第 3 天确实触发了买入信号
      expect(model.isBuySignalAt(3), true);

      // 验证今日触发卖出（相对于 3 天前 1.00 涨了 6% >= 5%）
      expect(model.isSellSignal, true);
      expect(model.isSellSignalAt(0), true);

      // 验证 currentRise 准确对齐有效买入日（+6.0%），而不是原始 20 天前的 -11.67%
      expect(model.currentRise, closeTo(6.0, 0.001));
    });
  });

  group('FundUIModel Buy Signal Grid Spacing Tests', () {
    test('isBuySignalAt should filter duplicate signals on consecutive drops', () {
      final model = FundUIModel(code: '000002', name: 'Test Fund 2', sector: 'Tech');
      
      // 策略：30天跌10%触发，不启用均线/MACD/RSI过滤
      model.optimalStrategy = {
        'buy_days': 30,
        'buy_drop': 10.0,
        'target_profit': 10.0,
        'ma_period': 0, // 禁用均线过滤
        'rsi_filter_limit': 0.0,
        'macd_filter_enabled': 0,
      };

      // 模拟净值（从近到远）：
      // index 0: 0.83 (今日) -> 相比前次买入点 0.85 跌 2.35% (< 3% 网格限制)
      // index 1: 0.84 (昨日) -> 相比前次买入点 0.85 跌 1.17% (< 3% 网格限制)
      // index 2: 0.85 (前日) -> 相比最高价 1.00 跌 15% (触发买入)
      // 后面都是 1.0
      model.navs = List.generate(50, (index) {
        if (index == 0) return 0.83;
        if (index == 1) return 0.84;
        if (index == 2) return 0.85;
        return 1.0;
      });

      // 计算的默认网格跌幅：10.0 * 0.3 = 3.0%
      // 验证第 2 天（前日，0.85）能够正常触发买入
      expect(model.isBuySignalAt(2), true);

      // 验证第 1 天（昨日，0.84）因为网格跌幅不足 3%，被降噪过滤
      expect(model.isBuySignalAt(1), false);

      // 验证第 0 天（今日，0.83）同样被降噪过滤
      expect(model.isBuySignalAt(0), false);

      // 如果将今日价格改为 0.82 (相比 0.85 跌 3.53% >= 3.0%)
      model.navs[0] = 0.82;
      expect(model.isBuySignalAt(0), true);
    });

    test('isSellSignal should NOT be swallowed when today also meets buy condition', () {
      final model = FundUIModel(code: '000003', name: 'Test Dual Signal Fund', sector: 'Tech');
      
      model.optimalStrategy = {
        'buy_days': 5,
        'buy_drop': 5.0,
        'sell_x': 7005, // 7 天涨 5.0%
        'ma_period': 0, // 禁用均线过滤
        'rsi_filter_limit': 0.0,
        'macd_filter_enabled': 0,
      };

      final List<String> testDates = List.generate(60, (i) => '2026-08-${(60 - i).toString().padLeft(2, '0')}');
      model.dates = testDates;

      // 构造净值序列（从近到远，index 0 为今日）：
      // index 30 (历史买点): 0.90
      // index 7 (7天前): 1.00
      // index 1 (昨日高点): 1.12
      // index 0 (今日): 1.06
      // 今日 7 天涨幅：(1.06 - 1.00) / 1.00 = +6.0% >= +5.0% (满足卖出)
      // 今日 5 天回撤：(1.06 - 1.12) / 1.12 = -5.35% <= -5.0% (同时满足买入)
      model.navs = List.generate(60, (index) {
        if (index == 0) return 1.06;
        if (index == 1) return 1.12;
        if (index <= 5) return 1.10;
        if (index == 7) return 1.00;
        if (index == 30) return 0.90;
        return 1.00;
      });

      // 验证历史买点（第30天）触发了买入
      expect(model.isBuySignalAt(30), true);

      // 验证今日满足买入条件
      expect(model.isBuySignalAt(0), true);

      // 验证今日卖出信号没有被今日买入信号吞掉
      expect(model.isSellSignal, true);
      expect(model.isSellSignalAt(0), true);

      // 验证模拟盘传入实际买入日（30天前）时也能正确识别卖出
      expect(model.isSellSignalAt(0, buyDateStr: testDates[30]), true);
    });
  });
}

