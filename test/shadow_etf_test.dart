// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/data_gateway.dart';

class RealNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  setUpAll(() {
    // 允许测试发起真实的 HTTP 网络请求
    HttpOverrides.global = RealNetworkHttpOverrides();
  });

  group('Shadow ETF Realtime Valuation Tests', () {
    final gateway = FundDataGateway();

    test('Single shadow ETF valuation fetch (050025 -> sh513100)', () async {
      // 050025 是易方达纳指100联接，它映射到 sh513100 (纳指ETF)
      final val = await gateway.fetchValuation('050025');
      expect(val, isNotNull);
      expect(val!['source'], equals('ShadowETF'));
      expect(val['is_shadow'], isTrue);
      
      final double? gsz = double.tryParse(val['gsz'] ?? '');
      final double? gszzl = double.tryParse(val['gszzl'] ?? '');
      expect(gsz, isNotNull);
      expect(gsz! > 0, isTrue);
      expect(gszzl, isNotNull);
      
      print('--- 050025 影子估值结果 ---');
      print('名称: ${val['name']}');
      print('估值: ${val['gsz']}');
      print('估值涨跌幅: ${val['gszzl']}%');
      print('昨日收盘: ${val['dwjz']}');
      print('更新时间: ${val['gztime']}');
    });

    test('Single shadow ETF valuation fetch (008282 -> sz159995)', () async {
      // 008282 是国泰半导体联接C，它映射到 sz159995 (芯片ETF)
      final val = await gateway.fetchValuation('008282');
      expect(val, isNotNull);
      expect(val!['source'], equals('ShadowETF'));
      expect(val['is_shadow'], isTrue);
      
      final double? gsz = double.tryParse(val['gsz'] ?? '');
      expect(gsz, isNotNull);
      expect(gsz! > 0, isTrue);

      print('--- 008282 芯片影子估值结果 ---');
      print('名称: ${val['name']}');
      print('估值: ${val['gsz']}');
      print('估值涨跌幅: ${val['gszzl']}%');
    });

    test('Batch shadow ETF valuation fetch (Mix of Shadow and Normal)', () async {
      // 050025, 008282, 012769 是影子，000001 (华夏成长) 是普通基金
      final codes = ['050025', '008282', '012769', '000001'];
      final results = await gateway.fetchValuationsSinaBatch(codes);
      
      expect(results, isNotEmpty);
      
      // 验证影子基金
      for (final code in ['050025', '008282', '012769']) {
        if (results.containsKey(code)) {
          final val = results[code]!;
          expect(val['source'], equals('ShadowETF'));
          expect(val['is_shadow'], isTrue);
          expect(double.tryParse(val['gsz'] ?? ''), isNotNull);
          print('批量影子 [$code] -> 估值: ${val['gsz']}, 涨跌幅: ${val['gszzl']}%');
        }
      }
      
      // 验证常规基金（注意：如果周末新浪接口未更新，可能是空，但如果有结果，它应该是常规的 SinaBatch）
      if (results.containsKey('000001')) {
        final val = results['000001']!;
        expect(val['source'], equals('SinaBatch'));
        expect(val['is_shadow'], isNull);
        print('批量常规 [000001] -> 估值: ${val['gsz']}, 涨跌幅: ${val['gszzl']}%');
      }
    });
  });
}
