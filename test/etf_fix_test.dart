import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/fund_provider.dart';
import 'package:fl_fund/core/config.dart';
import 'package:fl_fund/core/backtest_engine.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('ETF & Realtime Valuation Fix Tests', () {
    test('isTodayValuation handles hyphenated and compact date formats', () {
      final model = FundUIModel(code: '510300', name: '300ETF', sector: 'ETF');
      final todayStr = DateTime.now().toIso8601String().substring(0, 10); // 2026-08-23
      final todayCompact = todayStr.replaceAll('-', ''); // 20260823

      model.gztime = '$todayStr 15:00:00 [场内实时]';
      expect(model.isTodayValuation, isTrue);

      model.gztime = '${todayCompact}150000 [场内实时]';
      expect(model.isTodayValuation, isTrue);

      model.gztime = '2020-01-01 15:00:00 [场内实时]';
      expect(model.isTodayValuation, isFalse);
    });

    test('todayProfitAmount handles exchange-traded calculations and edge cases', () {
      final model = FundUIModel(
        code: '510300',
        name: '300ETF',
        sector: 'ETF',
        fundType: FundType.etf,
        shares: 10000,
        costPrice: 3.50,
      );
      model.currentPrice = 3.60;
      model.gszzl = '2.86'; // +2.86%
      expect(model.holdingMarketValue, 36000.0);
      expect(model.floatingProfitAmount, closeTo(1000.0, 0.01));
      expect(model.floatingYieldRate, closeTo((0.10 / 3.50) * 100.0, 0.01));
      expect(model.todayProfitAmount, greaterThan(0.0));

      // 极端行情除零保护
      model.gszzl = '-100.0';
      expect(model.todayProfitAmount.isFinite, isTrue);
    });

    test('loadMyFunds preserves exchange-traded and calculated cache fields', () {
      final config = AppConfig();
      config.fundsInfo.clear();
      config.fundsInfo['510300'] = FundInfo(
        code: '510300',
        name: '300ETF',
        sector: 'ETF',
        fundType: FundType.etf,
        shares: 5000,
        costPrice: 4.00,
        isHeld: true,
      );

      final provider = FundProvider();
      provider.loadMyFunds();

      // 模拟行情更新
      final model = provider.myFunds['510300']!;
      model.currentPrice = 4.25;
      model.iopv = 4.24;
      model.discountRate = 0.24;
      model.turnover = 12500.0;
      model.volume = 30000.0;
      model.pePercentile = 45.0;

      // 再次调用 loadMyFunds (如修改置顶/特别关注后)
      provider.loadMyFunds();

      final reloadedModel = provider.myFunds['510300']!;
      expect(reloadedModel.currentPrice, 4.25);
      expect(reloadedModel.iopv, 4.24);
      expect(reloadedModel.discountRate, 0.24);
      expect(reloadedModel.turnover, 12500.0);
      expect(reloadedModel.volume, 30000.0);
      expect(reloadedModel.pePercentile, 45.0);
    });

    test('FundInfo.fromJson backward compatibility for legacy OTC holding without fund_type', () {
      final legacyJson = {
        'name': '招商中证白酒指数(LOF)A',
        'sector': '消费',
        'is_held': true,
        'amount': '15000.0',
        'yield_rate': '8.5',
        'is_pinned': false,
        'is_special': false,
      };

      final fund = FundInfo.fromJson('161725', legacyJson);
      // 应该平滑兼容识别为 OTC，保留金额与收益率
      expect(fund.fundType, FundType.otc);
      expect(fund.isHeld, isTrue);
      expect(fund.amount, 15000.0);
      expect(fund.yieldRate, 8.5);
    });

    test('batchRemoveHoldInfos and dirty cleaning resets shares and costPrice', () {
      final config = AppConfig();
      config.fundsInfo['510300'] = FundInfo(
        code: '510300',
        name: '300ETF',
        sector: 'ETF',
        fundType: FundType.etf,
        shares: 1000,
        costPrice: 3.5,
        isHeld: true,
      );

      config.batchRemoveHoldInfos(['510300']);
      final fund = config.fundsInfo['510300']!;
      expect(fund.isHeld, isFalse);
      expect(fund.shares, 0.0);
      expect(fund.costPrice, 0.0);
      expect(fund.amount, 0.0);
      expect(fund.yieldRate, 0.0);
    });

    test('AppConfig ETF commission settings default and update', () async {
      final config = AppConfig();
      expect(config.etfCommissionRate, 0.005); // 万0.5 (0.005%)
      expect(config.etfMinCommission, 0.4); // 0.4元起收

      await config.updateEtfCommission(rate: 0.003, minFee: 0.0);
      expect(config.etfCommissionRate, 0.003);
      expect(config.etfMinCommission, 0.0);

      // 恢复默认
      await config.updateEtfCommission(rate: 0.005, minFee: 0.4);
      expect(config.etfCommissionRate, 0.005);
      expect(config.etfMinCommission, 0.4);
    });

    test('BacktestEngine handles isExchangeTraded with 0 short hold penalty and commission', () {
      // 构造快速上涨满足目标止盈（3天内止盈）的数据
      final navs = [1.0, 0.95, 0.94, 1.05, 1.06, 1.07];
      final dates = [
        '2026-01-01',
        '2026-01-02',
        '2026-01-03',
        '2026-01-04',
        '2026-01-05',
        '2026-01-06'
      ];

      // 1. 场外模式：未满7天止盈需承担 1.5% 惩罚赎回费
      final otcRes = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 2,
        buyDropPct: 1.0,
        targetProfitPct: 3.0,
        isExchangeTraded: false,
      );

      // 2. 场内模式：免除 7 天 1.5% 惩罚赎回费，按佣金精准扣费
      final etfRes = BacktestEngine.runBacktest(
        allNavs: navs,
        allDates: dates,
        buyDays: 2,
        buyDropPct: 1.0,
        targetProfitPct: 3.0,
        isExchangeTraded: true,
        etfCommissionRate: 0.005,
        etfMinCommission: 0.4,
      );

      expect(etfRes.totalTrades, greaterThanOrEqualTo(1));
      // 场内标的收益不扣除 1.5% 惩罚赎回费，收益率显著高于场外
      if (otcRes.totalTrades > 0) {
        expect(etfRes.avgProfit, greaterThan(otcRes.avgProfit));
      }
    });
  });
}
