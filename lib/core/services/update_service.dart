import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:open_filex/open_filex.dart';

class UpdateInfo {
  final String currentVersion;
  final int currentBuildNumber;
  final String latestVersion;
  final int latestBuildNumber;
  final String releaseNotes;
  final String releaseDate;
  final String downloadUrl;
  final String? sha256;
  final int? fileSize;
  final bool isForce;
  final bool hasUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.releaseNotes,
    required this.releaseDate,
    required this.downloadUrl,
    this.sha256,
    this.fileSize,
    required this.isForce,
    required this.hasUpdate,
  });
}

class UpdateService {
  /// 远程版本控制 JSON 数据源 URL 列表（支持主源与备用 CDN 镜像源）
  static const List<String> updateUrls = [
    'https://cdn.jsdelivr.net/gh/qiqbaba/FlFund@main/version.json',
    'https://fastly.jsdelivr.net/gh/qiqbaba/FlFund@main/version.json',
    'https://raw.githubusercontent.com/qiqbaba/FlFund/main/version.json',
    'https://ghproxy.net/https://raw.githubusercontent.com/qiqbaba/FlFund/main/version.json',
  ];

  /// 检查软件是否有更新
  static Future<UpdateInfo?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionStr = packageInfo.version;
      final currentBuildStr = packageInfo.buildNumber;
      final currentBuildInt = int.tryParse(currentBuildStr) ?? 0;

      Version currentVersion;
      try {
        currentVersion = Version.parse(currentVersionStr);
      } catch (_) {
        currentVersion = Version(1, 0, 0);
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      Map<String, dynamic>? data;
      for (final url in updateUrls) {
        try {
          final response = await dio.get(url);
          if (response.statusCode == 200 && response.data != null) {
            if (response.data is Map<String, dynamic>) {
              data = response.data as Map<String, dynamic>;
            } else if (response.data is Map) {
              data = Map<String, dynamic>.from(response.data as Map);
            } else if (response.data is String) {
              final rawStr = (response.data as String).trim();
              if (rawStr.isNotEmpty) {
                final decoded = jsonDecode(rawStr);
                if (decoded is Map<String, dynamic>) {
                  data = decoded;
                } else if (decoded is Map) {
                  data = Map<String, dynamic>.from(decoded);
                }
              }
            }
            if (data != null && data.containsKey('version')) {
              break;
            }
          }
        } catch (e) {
          debugPrint('尝试请求更新源 $url 失败: $e');
        }
      }

      if (data == null) {
        return null;
      }

      final latestVersionStr = data['version']?.toString() ?? currentVersionStr;
      final latestBuildInt = (data['buildNumber'] is num)
          ? (data['buildNumber'] as num).toInt()
          : int.tryParse(data['buildNumber']?.toString() ?? '0') ?? 0;

      Version latestVersion;
      try {
        latestVersion = Version.parse(latestVersionStr);
      } catch (_) {
        latestVersion = currentVersion;
      }

      final hasNewSemver = latestVersion > currentVersion;
      final hasNewBuild = (latestVersion == currentVersion) && (latestBuildInt > currentBuildInt);
      final hasUpdate = hasNewSemver || hasNewBuild;

      final minSupportedStr = data['minSupportedVersion']?.toString();
      bool isForce = false;
      if (minSupportedStr != null && minSupportedStr.isNotEmpty) {
        try {
          final minVersion = Version.parse(minSupportedStr);
          isForce = currentVersion < minVersion;
        } catch (_) {}
      }

      final platformKey = Platform.isWindows ? 'windows' : 'android';
      final platforms = data['platforms'] as Map<String, dynamic>? ?? {};
      final platformData = platforms[platformKey] as Map<String, dynamic>? ?? {};

      final downloadUrl = platformData['url']?.toString() ??
          data['downloadUrl']?.toString() ??
          '';

      return UpdateInfo(
        currentVersion: currentVersionStr,
        currentBuildNumber: currentBuildInt,
        latestVersion: latestVersionStr,
        latestBuildNumber: latestBuildInt,
        releaseNotes: data['releaseNotes']?.toString() ?? '修复已知问题，提升性能体验。',
        releaseDate: data['releaseDate']?.toString() ?? '',
        downloadUrl: downloadUrl,
        sha256: platformData['sha256']?.toString(),
        fileSize: platformData['fileSize'] is num ? (platformData['fileSize'] as num).toInt() : null,
        isForce: isForce,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('检查更新异常: $e');
      return null;
    }
  }

  /// 下载更新安装包并触发安装
  static Future<bool> downloadAndInstall({
    required String downloadUrl,
    required Function(int received, int total) onProgress,
    required Function(String errorMsg) onError,
  }) async {
    try {
      if (downloadUrl.isEmpty) {
        onError('更新下载地址为空');
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = downloadUrl.split('/').last.split('?').first;
      final savePath = '${tempDir.path}${Platform.pathSeparator}$fileName';

      final dio = Dio();
      await dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: onProgress,
      );

      final file = File(savePath);
      if (!await file.exists()) {
        onError('下载安装包文件不存在');
        return false;
      }

      if (Platform.isWindows) {
        if (savePath.endsWith('.exe')) {
          await Process.start(savePath, [], mode: ProcessStartMode.detached);
          exit(0);
        } else {
          final result = await OpenFilex.open(savePath);
          if (result.type != ResultType.done) {
            onError('打开更新文件失败: ${result.message}');
            return false;
          }
        }
      } else if (Platform.isAndroid) {
        final result = await OpenFilex.open(savePath);
        if (result.type != ResultType.done) {
          onError('启动 APK 安装失败: ${result.message}');
          return false;
        }
      } else {
        await OpenFilex.open(savePath);
      }
      return true;
    } catch (e) {
      onError('下载/安装过程发生异常: $e');
      return false;
    }
  }
}
