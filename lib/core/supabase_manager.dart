import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  factory SupabaseManager() => _instance;
  SupabaseManager._internal();

  SupabaseClient? _client;
  bool _initialized = false;
  String? _initializationError;

  bool get isInitialized => _initialized;
  String? get initializationError => _initializationError;

  SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase 尚未初始化。详细错误: ${_initializationError ?? "未知"}');
    }
    return _client!;
  }

  // 初始化 Supabase
  Future<bool> init({String? url, String? anonKey}) async {
    final targetUrl = url ?? AppConfig().supabaseUrl;
    final targetKey = anonKey ?? AppConfig().supabaseAnonKey;

    if (targetUrl.isEmpty || targetKey.isEmpty) {
      _initialized = false;
      _client = null;
      _initializationError = 'URL 或 AnonKey 为空';
      return false;
    }

    try {
      try {
        await Supabase.initialize(
          url: targetUrl,
          publishableKey: targetKey,
          authOptions: const FlutterAuthClientOptions(
            authFlowType: AuthFlowType.pkce,
          ),
        );
      } catch (e) {
        final errorStr = e.toString();
        if (!errorStr.contains('already initialized') && !errorStr.contains('has already been initialized')) {
          rethrow;
        }
      }
      _client = Supabase.instance.client;
      _initialized = true;
      _initializationError = null;
      debugPrint('Supabase 初始化成功');
      return true;
    } catch (e) {
      debugPrint('Supabase 初始化失败: $e');
      _initializationError = e.toString();
      _initialized = false;
      _client = null;
      return false;
    }
  }

  bool get isLoggedIn {
    if (!_initialized || _client == null) return false;
    try {
      return _client!.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  String? get currentUserEmail {
    if (!isLoggedIn) return null;
    return _client!.auth.currentUser?.email;
  }

  String? get currentUserId {
    if (!isLoggedIn) return null;
    return _client!.auth.currentUser?.id;
  }

  // 注册新账号
  Future<void> signUp(String email, String password) async {
    if (!_initialized) throw Exception('Supabase 尚未初始化，请先配置连接参数。详细错误: ${_initializationError ?? "未知"}');
    await client.auth.signUp(email: email, password: password);
  }

  // 账号密码登录
  Future<void> signIn(String email, String password) async {
    if (!_initialized) throw Exception('Supabase 尚未初始化，请先配置连接参数。详细错误: ${_initializationError ?? "未知"}');
    await client.auth.signInWithPassword(email: email, password: password);
  }

  // 发送重置密码邮件
  Future<void> resetPassword(String email) async {
    if (!_initialized) throw Exception('Supabase 尚未初始化，请先配置连接参数。详细错误: ${_initializationError ?? "未知"}');
    await client.auth.resetPasswordForEmail(email);
  }

  // 退出登录
  Future<void> signOut() async {
    if (!_initialized) return;
    await client.auth.signOut();
  }

  // 从云端拉取自选持仓数据并与本地双向合并 (四合一同冲突解决策略)
  Future<void> syncFromCloud({
    Future<Map<String, SyncConflictResolution>> Function(List<SyncConflict> conflicts)? onConflict,
  }) async {
    if (!isLoggedIn) return;

    final userId = currentUserId;
    if (userId == null) return;

    try {
      debugPrint('开始与 Supabase 同步合并数据...');
      
      // 1. 获取云端属于当前用户的所有基金记录
      final response = await client
          .from('user_funds')
          .select()
          .eq('user_id', userId);

      final List data = response as List;
      final Map<String, FundInfo> cloudFunds = {};

      for (final item in data) {
        final code = item['code']?.toString() ?? '';
        if (code.length == 6) {
          cloudFunds[code] = FundInfo(
            code: code,
            name: item['name'] ?? '',
            sector: item['sector'] ?? '',
            isHeld: item['is_held'] ?? false,
            isSpecial: item['is_special'] ?? false,
            isPinned: item['is_pinned'] ?? false,
            amount: double.tryParse(item['amount']?.toString() ?? '') ?? 0.0,
            yieldRate: double.tryParse(item['yield_rate']?.toString() ?? '') ?? 0.0,
            updatedAt: item['updated_at'] != null 
                ? DateTime.tryParse(item['updated_at'].toString()) ?? DateTime.now()
                : DateTime.now(),
          );
        }
      }

      final appConfig = AppConfig();
      final DateTime? lastSync = appConfig.lastSyncTime;
      
      // 我们收集所有操作：
      final List<FundInfo> localOnlyToUpload = []; // 需要推送到云端 (上传/更新)
      final List<String> cloudToDelete = [];        // 需要从云端物理删除
      final List<SyncConflict> conflictsList = [];  // 硬冲突的记录
      final Map<String, FundInfo> localToUpdate = {}; // 本地需更新/复活的列表
      final List<String> localToDelete = [];        // 本地物理删除 (含确认物理清除的墓碑)

      // 2. 处理本地墓碑 (deletedFunds)
      final tombstones = Map<String, FundInfo>.from(appConfig.deletedFunds);
      tombstones.forEach((code, tombstone) {
        if (cloudFunds.containsKey(code)) {
          final cloudFund = cloudFunds[code]!;
          if (tombstone.updatedAt.isAfter(cloudFund.updatedAt)) {
            // 本地删除更新。通知云端删除，且本地该墓碑可以被物理清除了
            cloudToDelete.add(code);
            localToDelete.add(code);
          } else {
            // 云端修改更晚，说明在另一端被复活或修改了。本地复活该基金并覆盖为云端数据
            final resolved = cloudFund;
            resolved.isDeleted = false;
            localToUpdate[code] = resolved;
            appConfig.deletedFunds.remove(code);
          }
        } else {
          // 云端已经没有这只基金了，本地可以直接物理清除墓碑
          localToDelete.add(code);
        }
      });

      // 3. 处理本地活跃基金 (fundsInfo)
      appConfig.fundsInfo.forEach((code, localFund) {
        if (!cloudFunds.containsKey(code)) {
          // 云端无此基金：
          if (lastSync == null) {
            // 首次同步：视为本地独有，加入上传
            localOnlyToUpload.add(localFund);
          } else if (localFund.updatedAt.isAfter(lastSync)) {
            // 在上次同步时间后本地新增的：上传
            localOnlyToUpload.add(localFund);
          } else {
            // 在上次同步时间前已经存在，现在云端无此记录：说明在另一端删除了。本地随之物理删除
            localToDelete.add(code);
          }
        }
      });

      // 4. 处理云端存在的基金记录并处理冲突
      cloudFunds.forEach((code, cloudFund) {
        if (appConfig.fundsInfo.containsKey(code)) {
          final localFund = appConfig.fundsInfo[code]!;
          
          // 对比两边是否有差异
          bool matches = localFund.name == cloudFund.name &&
              localFund.sector == cloudFund.sector &&
              localFund.isHeld == cloudFund.isHeld &&
              localFund.isSpecial == cloudFund.isSpecial &&
              localFund.isPinned == cloudFund.isPinned &&
              localFund.amount == cloudFund.amount &&
              localFund.yieldRate == cloudFund.yieldRate;

          if (!matches) {
            // 有差异，进行细粒度字段合并
            final mergeRes = mergeFields(localFund, cloudFund);
            if (mergeRes.hasConflict) {
              // 判定为同字段硬冲突，加入人工确认队列
              conflictsList.add(SyncConflict(code: code, local: localFund, cloud: cloudFund));
            } else {
              // 自动合并成功
              final merged = mergeRes.merged;
              // 判定修改的先后导向
              if (localFund.updatedAt.isAfter(cloudFund.updatedAt)) {
                // 本地较新，更新到本地并上传云端
                localToUpdate[code] = merged;
                localOnlyToUpload.add(merged);
              } else {
                // 云端较新，更新到本地。如果有融合本地偏离默认值的信息，也需回传云端
                localToUpdate[code] = merged;
                bool needsUploadBack = merged.isPinned != cloudFund.isPinned ||
                    merged.isSpecial != cloudFund.isSpecial ||
                    merged.isHeld != cloudFund.isHeld;
                if (needsUploadBack) {
                  localOnlyToUpload.add(merged);
                }
              }
            }
          }
        } else {
          // 云端有，本地无，且本地无该墓碑：拉取到本地
          if (!tombstones.containsKey(code)) {
            localToUpdate[code] = cloudFund;
          }
        }
      });

      // 5. 解决人工确认硬冲突
      if (conflictsList.isNotEmpty) {
        Map<String, SyncConflictResolution> resolutions = {};
        if (onConflict != null) {
          try {
            resolutions = await onConflict(conflictsList);
          } catch (e) {
            debugPrint('交互式解决冲突 Dialog 抛出异常，降级到 LWW 策略: $e');
          }
        }
        
        // 应用冲突解决结果 (若 onConflict 返回空或未提供，则用 LWW 策略兜底)
        for (final conflict in conflictsList) {
          final code = conflict.code;
          final res = resolutions[code];
          
          if (res == SyncConflictResolution.keepLocal) {
            // 保留本地：以本地数据为准，设置 updatedAt 为当前时间以保证其以后依然最新，并上传云端
            final resolved = conflict.local;
            resolved.updatedAt = DateTime.now();
            localToUpdate[code] = resolved;
            localOnlyToUpload.add(resolved);
            debugPrint('冲突解决 -> 保留本地: $code (${resolved.name})');
          } else if (res == SyncConflictResolution.keepCloud) {
            // 保留云端：用云端数据覆盖本地，updatedAt 使用云端时间
            final resolved = conflict.cloud;
            localToUpdate[code] = resolved;
            debugPrint('冲突解决 -> 保留云端: $code (${resolved.name})');
          } else {
            // LWW (Last-Write-Wins) 兜底
            if (conflict.local.updatedAt.isAfter(conflict.cloud.updatedAt)) {
              final resolved = conflict.local;
              resolved.updatedAt = DateTime.now();
              localToUpdate[code] = resolved;
              localOnlyToUpload.add(resolved);
              debugPrint('冲突解决 LWW -> 保留本地: $code (${resolved.name})');
            } else {
              final resolved = conflict.cloud;
              localToUpdate[code] = resolved;
              debugPrint('冲突解决 LWW -> 保留云端: $code (${resolved.name})');
            }
          }
        }
      }

      // 6. 执行各项删除与保存动作
      
      // 6.1 从云端物理删除
      if (cloudToDelete.isNotEmpty) {
        await client
            .from('user_funds')
            .delete()
            .eq('user_id', userId)
            .inFilter('code', cloudToDelete);
        debugPrint('成功物理删除云端冗余基金记录共 ${cloudToDelete.length} 个');
      }

      // 6.2 物理删除本地
      for (final code in localToDelete) {
        appConfig.fundsInfo.remove(code);
        appConfig.deletedFunds.remove(code);
        debugPrint('成功物理清除本地墓碑或被云端同步删除的自选记录: $code');
      }

      // 6.3 物理更新本地
      localToUpdate.forEach((code, fund) {
        appConfig.fundsInfo[code] = fund;
        debugPrint('本地同步应用更新/新增: $code (${fund.name})');
      });

      // 6.4 上传或更新云端
      if (localOnlyToUpload.isNotEmpty) {
        final List<Map<String, dynamic>> uploadData = localOnlyToUpload.map((fund) => {
          'user_id': userId,
          'code': fund.code,
          'name': fund.name,
          'sector': fund.sector,
          'is_held': fund.isHeld,
          'is_special': fund.isSpecial,
          'is_pinned': fund.isPinned,
          'amount': fund.amount,
          'yield_rate': fund.yieldRate,
          'updated_at': fund.updatedAt.toIso8601String(),
        }).toList();

        await client.from('user_funds').upsert(uploadData);
        debugPrint('成功上传/更新本地特有数据共 ${uploadData.length} 个至云端');
      }

      // 6.5 刷新同步状态并序列化
      appConfig.lastSyncTime = DateTime.now();
      await appConfig.saveConfig();
      debugPrint('云端双向同步完成，已更新 lastSyncTime。');

    } catch (e) {
      debugPrint('Supabase 差异同步中发生异常: $e');
      rethrow;
    }
  }

  // 单个基金新增或更新同步到云端
  Future<void> uploadFund(FundInfo fund) async {
    if (!isLoggedIn) return;
    try {
      final userId = currentUserId;
      if (userId == null) return;
      await client.from('user_funds').upsert({
        'user_id': userId,
        'code': fund.code,
        'name': fund.name,
        'sector': fund.sector,
        'is_held': fund.isHeld,
        'is_special': fund.isSpecial,
        'is_pinned': fund.isPinned,
        'amount': fund.amount,
        'yield_rate': fund.yieldRate,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('实时同步 -> 云端已保存基金: ${fund.code}');
    } catch (e) {
      debugPrint('实时同步 -> 保存到云端失败 (${fund.code}): $e');
    }
  }

  // 单个基金从云端删除
  Future<void> deleteFund(String code) async {
    if (!isLoggedIn) return;
    try {
      final userId = currentUserId;
      if (userId == null) return;
      await client
          .from('user_funds')
          .delete()
          .eq('user_id', userId)
          .eq('code', code);
      debugPrint('实时同步 -> 云端已删除基金: $code');
    } catch (e) {
      debugPrint('实时同步 -> 从云端删除失败 ($code): $e');
    }
  }

  // 批量基金同步到云端
  Future<void> uploadFunds(List<FundInfo> funds) async {
    if (!isLoggedIn) return;
    if (funds.isEmpty) return;
    try {
      final userId = currentUserId;
      if (userId == null) return;
      final data = funds.map((fund) => {
        'user_id': userId,
        'code': fund.code,
        'name': fund.name,
        'sector': fund.sector,
        'is_held': fund.isHeld,
        'is_special': fund.isSpecial,
        'is_pinned': fund.isPinned,
        'amount': fund.amount,
        'yield_rate': fund.yieldRate,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();
      await client.from('user_funds').upsert(data);
      debugPrint('实时同步 -> 云端批量保存基金数: ${funds.length}');
    } catch (e) {
      debugPrint('实时同步 -> 批量保存至云端失败: $e');
    }
  }

  // 批量基金从云端删除
  Future<void> deleteFunds(List<String> codes) async {
    if (!isLoggedIn) return;
    if (codes.isEmpty) return;
    try {
      final userId = currentUserId;
      if (userId == null) return;
      await client
          .from('user_funds')
          .delete()
          .eq('user_id', userId)
          .inFilter('code', codes);
      debugPrint('实时同步 -> 云端批量删除基金数: ${codes.length}');
    } catch (e) {
      debugPrint('实时同步 -> 批量删除云端数据失败: $e');
    }
  }
}

enum SyncConflictResolution {
  keepLocal,
  keepCloud,
}

class SyncConflict {
  final String code;
  final FundInfo local;
  final FundInfo cloud;

  SyncConflict({
    required this.code,
    required this.local,
    required this.cloud,
  });
}

class FieldMergeResult {
  final FundInfo merged;
  final bool hasConflict;

  FieldMergeResult({required this.merged, required this.hasConflict});
}

// 字段级合并与硬冲突判定
FieldMergeResult mergeFields(FundInfo local, FundInfo cloud) {
  bool hasConflict = false;

  // 1. name
  String mergedName = local.name;
  if (local.name != cloud.name) {
    if (local.name.isEmpty) {
      mergedName = cloud.name;
    } else if (cloud.name.isEmpty) {
      mergedName = local.name;
    } else {
      mergedName = local.updatedAt.isAfter(cloud.updatedAt) ? local.name : cloud.name;
    }
  }

  // 2. sector
  String mergedSector = local.sector;
  if (local.sector != cloud.sector) {
    if (local.sector == '其它' || local.sector.isEmpty) {
      mergedSector = cloud.sector;
    } else if (cloud.sector == '其它' || cloud.sector.isEmpty) {
      mergedSector = local.sector;
    } else {
      // 双方都设定了不同板块：硬冲突
      hasConflict = true;
    }
  }

  // 3. isHeld
  bool mergedIsHeld = local.isHeld;
  if (local.isHeld != cloud.isHeld) {
    mergedIsHeld = local.updatedAt.isAfter(cloud.updatedAt) ? local.isHeld : cloud.isHeld;
  }

  // 4. isSpecial
  bool mergedIsSpecial = local.isSpecial;
  if (local.isSpecial != cloud.isSpecial) {
    mergedIsSpecial = local.updatedAt.isAfter(cloud.updatedAt) ? local.isSpecial : cloud.isSpecial;
  }

  // 5. isPinned
  bool mergedIsPinned = local.isPinned;
  if (local.isPinned != cloud.isPinned) {
    mergedIsPinned = local.updatedAt.isAfter(cloud.updatedAt) ? local.isPinned : cloud.isPinned;
  }

  // 6. amount
  double mergedAmount = local.amount;
  if (local.amount != cloud.amount) {
    if (local.amount == 0.0) {
      mergedAmount = cloud.amount;
    } else if (cloud.amount == 0.0) {
      mergedAmount = local.amount;
    } else {
      // 双方都有持有金额且不一致：硬冲突
      hasConflict = true;
    }
  }

  // 7. yieldRate
  double mergedYieldRate = local.yieldRate;
  if (local.yieldRate != cloud.yieldRate) {
    if (local.yieldRate == 0.0) {
      mergedYieldRate = cloud.yieldRate;
    } else if (cloud.yieldRate == 0.0) {
      mergedYieldRate = local.yieldRate;
    } else {
      // 双方都有收益率且不相等：硬冲突
      hasConflict = true;
    }
  }

  final mergedFund = FundInfo(
    code: local.code,
    name: mergedName,
    sector: mergedSector,
    isHeld: mergedIsHeld,
    isSpecial: mergedIsSpecial,
    isPinned: mergedIsPinned,
    amount: mergedIsHeld ? mergedAmount : 0.0,
    yieldRate: mergedIsHeld ? mergedYieldRate : 0.0,
    updatedAt: local.updatedAt.isAfter(cloud.updatedAt) ? local.updatedAt : cloud.updatedAt,
  );

  return FieldMergeResult(merged: mergedFund, hasConflict: hasConflict);
}
