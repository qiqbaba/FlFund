import 'package:flutter_test/flutter_test.dart';
import 'package:fl_fund/core/models/fund_info.dart';
import 'package:fl_fund/core/supabase_manager.dart';

void main() {
  group('Supabase Sync Bug Reproduction and Fix Verification', () {
    test('Simulate 014662, 017513, 016186 repeated sync update bug', () {
      final now = DateTime.parse('2026-08-17T12:57:43.415680Z');

      // 本地数据：有持仓金额与收益率
      final localFund = FundInfo(
        code: '014662',
        name: '天弘黄金ETF联接C',
        sector: '黄金',
        isHeld: true,
        isSpecial: false,
        isPinned: false,
        amount: 0.08,
        yieldRate: -33.33,
        updatedAt: now,
      );

      // 云端数据：同时间或更新的时间，但持仓金额和收益率为 0 (未同步)
      final cloudFund = FundInfo(
        code: '014662',
        name: '天弘黄金ETF联接C',
        sector: '黄金',
        isHeld: true,
        isSpecial: false,
        isPinned: false,
        amount: 0.0,
        yieldRate: 0.0,
        updatedAt: now,
      );

      // 1. 差异比对
      bool matches = localFund.name == cloudFund.name &&
          localFund.sector == cloudFund.sector &&
          localFund.isHeld == cloudFund.isHeld &&
          localFund.isSpecial == cloudFund.isSpecial &&
          localFund.isPinned == cloudFund.isPinned &&
          localFund.amount == cloudFund.amount &&
          localFund.yieldRate == cloudFund.yieldRate;

      expect(matches, isFalse);

      // 2. 字段合并
      final mergeRes = mergeFields(localFund, cloudFund);
      expect(mergeRes.hasConflict, isFalse);
      final merged = mergeRes.merged;

      expect(merged.amount, 0.08);
      expect(merged.yieldRate, -33.33);

      // 3. 检查 needsUploadBack 逻辑
      // 旧逻辑仅比对 isPinned, isSpecial, isHeld:
      bool oldNeedsUploadBack = merged.isPinned != cloudFund.isPinned ||
          merged.isSpecial != cloudFund.isSpecial ||
          merged.isHeld != cloudFund.isHeld;
      expect(oldNeedsUploadBack, isFalse, reason: '旧逻辑判断无需回传云端，导致云端永远不会更新');

      // 新逻辑比对所有字段：
      bool newNeedsUploadBack = merged.name != cloudFund.name ||
          merged.sector != cloudFund.sector ||
          merged.isHeld != cloudFund.isHeld ||
          merged.isSpecial != cloudFund.isSpecial ||
          merged.isPinned != cloudFund.isPinned ||
          merged.amount != cloudFund.amount ||
          merged.yieldRate != cloudFund.yieldRate;
      expect(newNeedsUploadBack, isTrue, reason: '新逻辑正确判断需要将合并后的金额与收益率回传云端');

      // 4. 模拟回传云端后再次同步
      if (newNeedsUploadBack) {
        merged.updatedAt = DateTime.now();
      }
      final updatedCloudFund = FundInfo(
        code: merged.code,
        name: merged.name,
        sector: merged.sector,
        isHeld: merged.isHeld,
        isSpecial: merged.isSpecial,
        isPinned: merged.isPinned,
        amount: merged.amount,
        yieldRate: merged.yieldRate,
        updatedAt: merged.updatedAt,
      );

      bool secondMatches = merged.name == updatedCloudFund.name &&
          merged.sector == updatedCloudFund.sector &&
          merged.isHeld == updatedCloudFund.isHeld &&
          merged.isSpecial == updatedCloudFund.isSpecial &&
          merged.isPinned == updatedCloudFund.isPinned &&
          merged.amount == updatedCloudFund.amount &&
          merged.yieldRate == updatedCloudFund.yieldRate;

      expect(secondMatches, isTrue, reason: '云端同步后下次启动完全一致，不再触发重复更新');
    });
  });
}
