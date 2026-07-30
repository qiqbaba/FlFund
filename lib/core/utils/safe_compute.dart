import 'package:flutter/foundation.dart';

/// 安全的 compute 包装器。
///
/// Release 模式下使用 [compute] 将耗时操作移入后台 Isolate；
/// Debug 模式下直接在主线程同步执行，避免 Windows 调试器附加时
/// Isolate 生成失败导致应用卡死。
Future<R> safeCompute<Q, R>(ComputeCallback<Q, R> callback, Q message) async {
  if (kDebugMode) {
    return callback(message);
  }
  return compute(callback, message);
}
