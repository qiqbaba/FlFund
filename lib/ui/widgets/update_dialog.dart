import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../core/config.dart';
import '../../core/services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final bool isManualCheck;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    this.isManualCheck = false,
  });

  static Future<void> show(
    BuildContext context, {
    required UpdateInfo updateInfo,
    bool isManualCheck = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: !updateInfo.isForce,
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        isManualCheck: isManualCheck,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final info = widget.updateInfo;

    // 没有新版本时的界面展示（仅在手动触发检查时显示）
    if (!info.hasUpdate) {
      return ContentDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.completed_solid, size: 20),
            SizedBox(width: 8),
            Text('已是最新版本'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前软件版本：v${info.currentVersion} (Build ${info.currentBuildNumber})'),
            const SizedBox(height: 8),
            const Text('暂无新版本发布，您可以放心使用。', style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }

    // 有新版本时的下载/更新对话框
    return ContentDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.update_restore, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '发现新版本 v${info.latestVersion} (Build ${info.latestBuildNumber})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.resources.cardBackgroundFillColorSecondary,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.resources.dividerStrokeColorDefault),
              ),
              child: Row(
                children: [
                  Text('当前版本: v${info.currentVersion}'),
                  const Spacer(),
                  const Icon(FluentIcons.forward, size: 12),
                  const Spacer(),
                  Text(
                    '最新版本: v${info.latestVersion}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0078D4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('更新说明：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.resources.cardBackgroundFillColorDefault,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.resources.dividerStrokeColorDefault),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.releaseNotes,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ),
            if (info.fileSize != null && info.fileSize! > 0) ...[
              const SizedBox(height: 6),
              Text(
                '安装包大小: ${(info.fileSize! / (1024 * 1024)).toStringAsFixed(2)} MB',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              InfoBar(
                title: const Text('下载失败'),
                content: Text(_errorMessage!),
                severity: InfoBarSeverity.error,
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              ProgressBar(value: _downloadProgress * 100),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_statusText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: _isDownloading
          ? []
          : [
              if (!info.isForce) ...[
                Button(
                  child: const Text('稍后提醒'),
                  onPressed: () => Navigator.pop(context),
                ),
                Button(
                  child: const Text('跳过此版本'),
                  onPressed: () {
                    final appConfig = Provider.of<AppConfig>(context, listen: false);
                    appConfig.setIgnoredUpdateVersion(info.latestVersion);
                    Navigator.pop(context);
                  },
                ),
              ],
              FilledButton(
                child: Text(info.isForce ? '强制更新' : '立即更新'),
                onPressed: () async {
                  setState(() {
                    _isDownloading = true;
                    _errorMessage = null;
                    _statusText = '准备下载安装包...';
                    _downloadProgress = 0.0;
                  });

                  final success = await UpdateService.downloadAndInstall(
                    downloadUrl: info.downloadUrl,
                    onProgress: (received, total) {
                      if (mounted && total > 0) {
                        setState(() {
                          _downloadProgress = received / total;
                          _statusText =
                              '正在下载 (${(received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB)';
                        });
                      }
                    },
                    onError: (msg) {
                      if (mounted) {
                        setState(() {
                          _isDownloading = false;
                          _errorMessage = msg;
                        });
                      }
                    },
                  );

                  if (!success && mounted) {
                    setState(() {
                      _isDownloading = false;
                    });
                  }
                },
              ),
            ],
    );
  }
}
