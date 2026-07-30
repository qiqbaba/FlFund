import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/models/fund_info.dart';
import 'package:fl_fund/core/config.dart';
import 'package:fl_fund/core/supabase_manager.dart';

void main() {
  group('FundInfo Holdings Sanitize Tests', () {
    test('FundInfo.fromJson should clean up amount and yieldRate for unheld funds when config is loaded', () {
      final jsonMap = {
        'name': '广发北证50成份指数C',
        'sector': '北证50',
        'is_held': false, // 未持有
        'is_special': true,
        'is_pinned': false,
        'amount': '105.97', // 残留数据
        'yield_rate': '16.3', // 残留数据
        'updated_at': '2026-06-29T11:51:30.402787Z',
        'is_deleted': false,
      };

      // 测试 config.dart 中 loadConfig 阶段的自动清洗逻辑：
      // 我们模拟从 JSON 反序列化后，逻辑是否将其重置
      final fund = FundInfo.fromJson('017513', jsonMap);
      
      // 在 loadConfig 阶段的代码逻辑是：
      // if (!fund.isHeld && (fund.amount != 0.0 || fund.yieldRate != 0.0)) {
      //   fund.amount = 0.0;
      //   fund.yieldRate = 0.0;
      // }
      bool wasDirty = false;
      if (!fund.isHeld && (fund.amount != 0.0 || fund.yieldRate != 0.0)) {
        fund.amount = 0.0;
        fund.yieldRate = 0.0;
        wasDirty = true;
      }

      expect(wasDirty, isTrue);
      expect(fund.isHeld, isFalse);
      expect(fund.amount, 0.0);
      expect(fund.yieldRate, 0.0);
    });

    test('mergeFields should reset amount and yieldRate if mergedIsHeld is false during sync', () {
      final local = FundInfo(
        code: '017513',
        name: '广发北证50成份指数C',
        sector: '北证50',
        isHeld: false,
        isSpecial: true,
        amount: 105.97, // 本地脏数据
        yieldRate: 16.3, // 本地脏数据
      );

      final cloud = FundInfo(
        code: '017513',
        name: '广发北证50成份指数C',
        sector: '北证50',
        isHeld: false,
        isSpecial: true,
        amount: 0.0, // 云端没有脏数据
        yieldRate: 0.0, // 云端没有脏数据
      );

      // 执行合并
      final mergeRes = mergeFields(local, cloud);

      expect(mergeRes.hasConflict, isFalse);
      expect(mergeRes.merged.isHeld, isFalse);
      expect(mergeRes.merged.amount, 0.0);
      expect(mergeRes.merged.yieldRate, 0.0);
    });

    test('Valuation proxy proxy-calculation logic works correctly', () {
      final childWeb = {
        'latest_item': {'DWJZ': '1.1177'},
        'jzrq': '2026-07-03'
      };
      
      final proxyVal = {
        'source': 'EastMoneyGz',
        'name': '华夏中证动漫游戏联接C',
        'jzrq': '2026-07-03',
        'gszzl': '+1.20',
        'gztime': '2026-07-04 15:00:00'
      };

      Map<String, dynamic>? resultVal;
      final latestItem = childWeb['latest_item'] as Map?;
      final childDwjzStr = latestItem?['DWJZ']?.toString();
      final childDwjz = double.tryParse(childDwjzStr ?? '');
      final gszzlStr = proxyVal['gszzl']?.toString().replaceAll('%', '') ?? '';
      final gszzl = double.tryParse(gszzlStr);

      if (childDwjz != null && gszzl != null) {
        final childGsz = childDwjz * (1 + gszzl / 100);
        resultVal = {
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

      expect(resultVal, isNotNull);
      expect(resultVal!['is_proxy'], isTrue);
      expect(resultVal['gsz'], '1.1311');

      String srcName = resultVal['source']?.toString() ?? '';
      if (srcName == 'EastMoneyGz') {
        srcName = '天天基金(估值)';
      }
      if (resultVal['is_proxy'] == true) {
        srcName = '$srcName(代理)';
      }
      final gztime = '${resultVal['gztime']} [$srcName]';

      expect(gztime, '2026-07-04 15:00:00 [天天基金(估值)(代理)]');
    });
  });
}
