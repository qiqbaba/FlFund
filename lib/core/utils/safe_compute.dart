import 'package:flutter/foundation.dart';

/// 安全的 compute 包装器。
/// 优先使用 [compute] 将耗时操作移入后台 Isolate 执行，避免主 UI 线程卡顿与渲染阻塞；
/// 若 Isolate 执行发生异常，则自动回退至主线程执行。
Future<R> safeCompute<Q, R>(ComputeCallback<Q, R> callback, Q message) async {
  try {
    return await compute(callback, message);
  } catch (e) {
    debugPrint('Isolate compute error, falling back to main thread: $e');
    return callback(message);
  }
}
