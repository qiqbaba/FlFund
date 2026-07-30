import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Colors, Icons, Material, MaterialType, AdaptiveTextSelectionToolbar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../widgets/scaled_checkbox.dart';
import '../widgets/paste_helper.dart';
import '../../core/config.dart';
import '../../core/db_manager.dart';
import '../../core/fund_provider.dart';
import '../../core/supabase_manager.dart';
import '../../core/simulation_provider.dart';
import '../widgets/mobile_header.dart';
import '../../core/utils/number_formatter.dart';

enum PasswordStrength { weak, medium, strong }

class BackupTab extends StatefulWidget {
  const BackupTab({super.key});

  @override
  State<BackupTab> createState() => _BackupTabState();
}

class _BackupTabState extends State<BackupTab> {
  // 导出勾选项
  bool _expFundsList = true;
  bool _expHoldings = true;
  bool _expSpecials = true;
  bool _expStrategies = true;
  bool _expSettings = false; // 默认不勾选系统全局配置，防止覆盖密钥等敏感信息
  bool _enableExportEncrypt = false;
  final _exportPasswordController = TextEditingController();

  // 导入状态与解析数据
  String? _selectedImportPath;
  Map<String, dynamic>? _parsedBackupData;
  bool _isImporting = false;

  // 导入勾选项 (在选择备份文件并解析后启用)
  bool _impFundsList = false;
  bool _impHoldings = false;
  bool _impSpecials = false;
  bool _impStrategies = false;
  bool _impSettings = false;

  // 导入模式: true 合并导入, false 覆盖导入
  bool _isMergeMode = true;

  // 统计本地数据量
  int _localStrategyCount = 0;

  // 状态消息提示
  String? _infoBarTitle;
  String? _infoBarMessage;
  fluent.InfoBarSeverity _infoBarSeverity = fluent.InfoBarSeverity.info;

  // Supabase 控制器和状态
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRegisteringMode = false;
  bool _isAuthOperating = false;
  bool _isCloudSyncing = false;

  // 密码推荐与强度检测状态
  String _recommendedPassword = '';
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasDigitsOrSpecials = false;

  void _onPasswordChanged() {
    final password = _passwordController.text;
    final hasMinLength = password.length >= 8 && password.length <= 20;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasDigitsOrSpecials = password.contains(RegExp(r'[0-9]')) ||
        password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));

    if (hasMinLength != _hasMinLength ||
        hasUppercase != _hasUppercase ||
        hasLowercase != _hasLowercase ||
        hasDigitsOrSpecials != _hasDigitsOrSpecials) {
      setState(() {
        _hasMinLength = hasMinLength;
        _hasUppercase = hasUppercase;
        _hasLowercase = hasLowercase;
        _hasDigitsOrSpecials = hasDigitsOrSpecials;
      });
    }
  }

  String _generateRecommendedPassword() {
    const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lowercase = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const specials = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    final rand = Random.secure();
    final chars = [
      uppercase[rand.nextInt(uppercase.length)],
      lowercase[rand.nextInt(lowercase.length)],
      digits[rand.nextInt(digits.length)],
      specials[rand.nextInt(specials.length)],
    ];

    const allPossible = '$uppercase$lowercase$digits$specials';
    for (int i = 0; i < 10; i++) {
      chars.add(allPossible[rand.nextInt(allPossible.length)]);
    }

    chars.shuffle(rand);
    return chars.join();
  }

  PasswordStrength _getPasswordStrength() {
    int score = 0;
    if (_hasMinLength) score++;
    if (_hasUppercase) score++;
    if (_hasLowercase) score++;
    if (_hasDigitsOrSpecials) score++;

    if (score <= 2) {
      return PasswordStrength.weak;
    } else if (score == 3) {
      return PasswordStrength.medium;
    } else {
      return PasswordStrength.strong;
    }
  }

  Widget _buildStrengthCriteria(String text, bool isMet, bool isDark) {
    const activeColor = Color(0xFF00E676);
    final inactiveColor = Colors.grey.withOpacity(0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 11,
          color: isMet ? activeColor : inactiveColor,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: isMet
                ? (isDark ? Colors.white.withOpacity(0.9) : Colors.black87)
                : inactiveColor,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLocalStrategyCount();
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _exportPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalStrategyCount() async {
    try {
      final strategies = await FundHistoryDB().getAllOptimalStrategies();
      if (mounted) {
        setState(() {
          _localStrategyCount = strategies.length;
        });
      }
    } catch (e) {
      debugPrint('加载本地策略统计失败: $e');
    }
  }

  void _showInfoBar(
      String title, String message, fluent.InfoBarSeverity severity) {
    setState(() {
      _infoBarTitle = title;
      _infoBarMessage = message;
      _infoBarSeverity = severity;
    });

    // 5秒后自动清除通知
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _infoBarMessage == message) {
        setState(() {
          _infoBarMessage = null;
        });
      }
    });
  }

  void _showDialogNotification(String title, String message,
      {bool isSuccess = false}) {
    fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: Row(
            children: [
              Icon(
                isSuccess
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text(
              message,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            fluent.FilledButton(
              child: const Text('确定'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForPassword(String title,
      {String? errorMessage}) async {
    final controller = TextEditingController();
    bool? ok = false;

    await fluent.showDialog(
      context: context,
      builder: (context) {
        return fluent.ContentDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(errorMessage,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              const Text('请输入用于解密备份文件的密码：'),
              const SizedBox(height: 8),
              fluent.TextBox(
                controller: controller,
                placeholder: '解密密码',
                obscureText: true,
                maxLines: 1,
              ),
            ],
          ),
          actions: [
            fluent.Button(
              child: const Text('取消'),
              onPressed: () {
                ok = false;
                Navigator.pop(context);
              },
            ),
            fluent.FilledButton(
              child: const Text('确定'),
              onPressed: () {
                ok = true;
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );

    return ok == true ? controller.text : null;
  }

  // 执行导出逻辑
  Future<void> _performExport(AppConfig appConfig) async {
    if (!_expFundsList &&
        !_expHoldings &&
        !_expSpecials &&
        !_expStrategies &&
        !_expSettings) {
      _showInfoBar('导出提示', '请至少勾选一项要导出的数据类别。', fluent.InfoBarSeverity.warning);
      return;
    }

    if (_enableExportEncrypt && _exportPasswordController.text.trim().isEmpty) {
      _showInfoBar('导出提示', '启用加密备份时，密码不能为空。', fluent.InfoBarSeverity.warning);
      return;
    }

    try {
      String? destPath;
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final defaultFileName = 'flfund_backup_$dateStr.json';

      if (!kIsWeb && Platform.isWindows) {
        destPath = await FilePicker.platform.saveFile(
          dialogTitle: '选择备份文件保存位置',
          fileName: defaultFileName,
        );
      } else {
        // 安卓端或其他平台：选择文件夹并在其下生成文件
        final selectedDir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存备份的文件夹',
        );
        if (selectedDir != null) {
          destPath = path.join(selectedDir, defaultFileName);
        }
      }

      if (destPath == null) {
        return; // 用户取消了保存
      }

      // 确保文件格式是 .json
      if (!destPath.toLowerCase().endsWith('.json')) {
        destPath = '$destPath.json';
      }

      final bool useEncrypt = _enableExportEncrypt;
      final String? password =
          useEncrypt ? _exportPasswordController.text.trim() : null;

      final success = await appConfig.exportSelectedData(
        destPath: destPath,
        includeFundsList: _expFundsList,
        includeHoldings: _expHoldings,
        includeSpecials: _expSpecials,
        includeStrategies: _expStrategies,
        includeSettings: _expSettings,
        password: password,
      );

      if (success) {
        if (!useEncrypt && _expSettings) {
          _showInfoBar('导出成功', '明文备份已导出。为保安全，API 密钥已被自动剔除。',
              fluent.InfoBarSeverity.success);
        } else {
          _showInfoBar(
              '导出成功', '数据已成功导出至：$destPath', fluent.InfoBarSeverity.success);
        }
      } else {
        _showInfoBar('导出失败', '写入文件时发生内部异常。', fluent.InfoBarSeverity.error);
      }
    } catch (e) {
      _showInfoBar('导出异常', '异常信息: $e', fluent.InfoBarSeverity.error);
    }
  }

  String? _importDecryptPassword;

  // 选择导入备份文件
  Future<void> _pickImportFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        if (!await file.exists()) {
          _showInfoBar('文件不存在', '选定的备份文件无法读取。', fluent.InfoBarSeverity.error);
          return;
        }

        final content = await file.readAsString(encoding: utf8);
        Map<String, dynamic> backupMap;
        try {
          backupMap = json.decode(content);
        } catch (_) {
          _showInfoBar(
              '格式错误', '该文件不是有效的 JSON 备份格式。', fluent.InfoBarSeverity.error);
          return;
        }

        String? tempPassword;
        // 如果是加密文件，索要密码解密
        if (backupMap['encrypted'] == true) {
          final encryptedData = backupMap['data']?.toString() ?? '';
          bool decryptSuccess = false;

          while (!decryptSuccess) {
            final input = await _promptForPassword(
              tempPassword == null ? '备份解密' : '密码错误',
              errorMessage: tempPassword == null ? null : '密码不正确，请重新输入。',
            );

            if (input == null) {
              return; // 用户取消
            }

            final decryptedText = SimpleCrypto.xorDecrypt(encryptedData, input);
            if (decryptedText != null) {
              try {
                backupMap = json.decode(decryptedText);
                tempPassword = input;
                decryptSuccess = true;
              } catch (_) {
                // 解密出来不是有效 JSON，说明密码还是不对
              }
            }
            if (!decryptSuccess) {
              tempPassword = input;
            }
          }
        }

        // 基本结构校验
        if (backupMap['version'] == null &&
            backupMap['funds_list'] == null &&
            backupMap['holdings'] == null &&
            backupMap['optimal_strategies'] == null) {
          _showInfoBar('校验失败', '未在此文件中解析到 FlFund 的备份数据结构。',
              fluent.InfoBarSeverity.warning);
          return;
        }

        setState(() {
          _selectedImportPath = filePath;
          _parsedBackupData = backupMap;
          _importDecryptPassword = tempPassword;

          // 根据备份文件中实际包含的数据项，动态重置勾选项
          _impFundsList = backupMap['funds_list'] != null;
          _impHoldings = backupMap['holdings'] != null;
          _impSpecials = backupMap['specials'] != null;
          _impStrategies = backupMap['optimal_strategies'] != null;
          _impSettings = backupMap['global_settings'] != null;
        });
      }
    } catch (e) {
      _showInfoBar('读取异常', '打开文件选择器失败: $e', fluent.InfoBarSeverity.error);
    }
  }

  // 执行导入逻辑
  Future<void> _performImport(
      AppConfig appConfig, FundProvider fundProvider) async {
    if (_selectedImportPath == null || _parsedBackupData == null) {
      _showInfoBar(
          '导入提示', '请先选择要导入的 JSON 备份文件。', fluent.InfoBarSeverity.warning);
      return;
    }

    if (!_impFundsList &&
        !_impHoldings &&
        !_impSpecials &&
        !_impStrategies &&
        !_impSettings) {
      _showInfoBar('导入提示', '请至少选择一项要恢复的数据类别。', fluent.InfoBarSeverity.warning);
      return;
    }

    // 若处于“覆盖导入”模式或包含“系统全局配置”，弹出二次确认
    bool confirm = true;
    if (!_isMergeMode || _impSettings) {
      final List<String> warnings = [];
      if (!_isMergeMode) {
        warnings.add('・ 覆盖导入会完全擦除当前设备上的对应数据类型，只保留备份文件的内容。');
      }
      if (_impSettings) {
        warnings.add('・ 恢复全局系统设置会覆盖当前的 API 密钥、接口地址以及界面显示规则。');
      }

      await fluent.showDialog<bool>(
        context: context,
        builder: (context) {
          return fluent.ContentDialog(
            title: const Text('数据恢复安全确认'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('您正在执行敏感的数据导入操作，请知悉以下潜在影响：',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...warnings.map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text(w,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12)),
                    )),
                const SizedBox(height: 12),
                const Text('确定要继续执行并覆盖/更新本地数据吗？'),
              ],
            ),
            actions: [
              fluent.Button(
                child: const Text('取消'),
                onPressed: () {
                  confirm = false;
                  Navigator.pop(context);
                },
              ),
              fluent.FilledButton(
                child: const Text('确定导入'),
                onPressed: () {
                  confirm = true;
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }

    if (!confirm) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final success = await appConfig.importSelectedData(
        _selectedImportPath!,
        includeFundsList: _impFundsList,
        includeHoldings: _impHoldings,
        includeSpecials: _impSpecials,
        includeStrategies: _impStrategies,
        includeSettings: _impSettings,
        isMerge: _isMergeMode,
        password: _importDecryptPassword,
      );

      if (success) {
        // 重新刷新 Provider 数据状态
        fundProvider.loadMyFunds();
        await _loadLocalStrategyCount();

        _showInfoBar('导入成功', '所选备份数据已成功载入并生效。', fluent.InfoBarSeverity.success);
        // 清理缓存解析状态
        setState(() {
          _selectedImportPath = null;
          _parsedBackupData = null;
          _importDecryptPassword = null;
        });
      } else {
        _showInfoBar('导入失败', '解析或覆写备份文件时发生内部异常。', fluent.InfoBarSeverity.error);
      }
    } catch (e) {
      _showInfoBar('导入异常', '异常信息: $e', fluent.InfoBarSeverity.error);
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  // 登录或注册
  Future<void> _handleAuth(
      AppConfig appConfig, FundProvider fundProvider, bool isSignUp) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showDialogNotification('输入警告', '邮箱和密码不能为空。');
      return;
    }

    if (isSignUp) {
      final strength = _getPasswordStrength();
      if (strength == PasswordStrength.weak) {
        _showDialogNotification(
            '密码强度不足', '密码必须长度在 8-20 位，且包含大写字母、小写字母以及数字/特殊字符中的至少 3 种。');
        return;
      }

      final confirmPassword = _confirmPasswordController.text.trim();
      if (password != confirmPassword) {
        _showDialogNotification('输入警告', '两次输入的密码不一致。');
        return;
      }
    } else {
      if (password.length < 6) {
        _showDialogNotification('输入警告', '密码长度不能少于 6 位。');
        return;
      }
    }

    setState(() {
      _isAuthOperating = true;
    });

    try {
      if (isSignUp) {
        await SupabaseManager().signUp(email, password);
        _showDialogNotification('注册成功',
            '账号注册成功！我们已向您的邮箱发送了确认激活邮件。请前往邮箱点击确认激活，激活成功后，请直接返回本软件输入账号密码进行登录。',
            isSuccess: true);
        setState(() {
          _isRegisteringMode = false;
          _recommendedPassword = '';
        });
      } else {
        await SupabaseManager().signIn(email, password);
        _showDialogNotification('登录成功', '成功登录云同步服务。', isSuccess: true);

        // 登录成功自动同步
        setState(() {
          _isCloudSyncing = true;
        });
        await appConfig.syncWithSupabase(
          onConflict: (conflicts) => showSyncConflictDialog(context, conflicts),
        );
        fundProvider.loadMyFunds();
        // 登录后切换模拟盘到当前用户数据
        SimulationProvider().reloadSimData();
        _showDialogNotification('同步成功', '已完成首次多端数据双向合并同步。', isSuccess: true);
      }
    } catch (e) {
      final msg = _parseSyncError(e);
      if (isSignUp) {
        _showDialogNotification('注册失败', msg);
      } else {
        _showDialogNotification('认证失败', msg);
      }
    } finally {
      setState(() {
        _isAuthOperating = false;
        _isCloudSyncing = false;
      });
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showDialogNotification('输入提示', '请先在上方输入框填写您的邮箱地址。');
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showDialogNotification('输入提示', '请输入有效的邮箱地址。');
      return;
    }

    setState(() {
      _isAuthOperating = true;
    });

    try {
      await SupabaseManager().resetPassword(email);
      _showDialogNotification('邮件已发送', '密码重置邮件已发送至 $email，请查收邮件并按照提示重置密码。',
          isSuccess: true);
    } catch (e) {
      _showDialogNotification('发送失败', _parseSyncError(e));
    } finally {
      setState(() {
        _isAuthOperating = false;
      });
    }
  }

  // 注销登录
  Future<void> _handleSignOut(
      AppConfig appConfig, FundProvider fundProvider) async {
    setState(() {
      _isAuthOperating = true;
    });
    try {
      await SupabaseManager().signOut();
      await appConfig.loadConfig(force: true); // 重新加载本地离线配置
      fundProvider.loadMyFunds();
      // 退出后切换模拟盘到本地共享数据
      SimulationProvider().reloadSimData();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _recommendedPassword = '';
      _isRegisteringMode = false;
      _showDialogNotification('退出成功', '已退出云登录状态，系统回到离线本地存储模式。',
          isSuccess: true);
    } catch (e) {
      _showDialogNotification('退出失败', _parseSyncError(e));
    } finally {
      setState(() {
        _isAuthOperating = false;
      });
    }
  }

  // 手动同步数据
  Future<void> _handleManualSync(
      AppConfig appConfig, FundProvider fundProvider) async {
    setState(() {
      _isCloudSyncing = true;
    });
    try {
      await appConfig.syncWithSupabase(
        onConflict: (conflicts) => showSyncConflictDialog(context, conflicts),
      );
      fundProvider.loadMyFunds();
      _showDialogNotification('同步完成', '云端与本地数据同步合并已全部完成。', isSuccess: true);
    } catch (e) {
      _showDialogNotification('同步失败', _parseSyncError(e));
    } finally {
      setState(() {
        _isCloudSyncing = false;
      });
    }
  }

  String _parseSyncError(dynamic error) {
    final str = error.toString();
    if (str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('NetworkIsUnreachable') ||
        str.contains('Connection failed')) {
      return '网络连接失败，请检查您的网络连接或代理设置。国内环境下连接 Supabase 可能需要开启加速或代理。';
    }
    if (str.contains('timeout') || str.contains('TimeoutException')) {
      return '网络请求超时，服务器未在响应时间内返回。请稍后重试。';
    }
    if (str.contains('Invalid login credentials') ||
        str.contains('invalid_credentials')) {
      return '邮箱或密码不正确，请重新检查后输入。';
    }
    if (str.contains('Email not confirmed') ||
        str.contains('email_not_confirmed')) {
      return '该邮箱尚未完成激活确认，请先前往您的邮箱查收并点击确认激活。';
    }
    if (str.contains('rate limit') || str.contains('too_many_requests')) {
      return '操作过于频繁，已被服务器限流。请稍后再试。';
    }
    if (str.contains('JWT') || str.contains('session')) {
      return '您的会话已过期，请尝试重新登录。';
    }
    return str;
  }

  // 辅助构建统计文本
  Widget _buildStatBadge(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final localFundsCount = appConfig.fundsInfo.length;
    final localHoldingsCount =
        appConfig.fundsInfo.values.where((f) => f.isHeld).length;
    final localSpecialsCount =
        appConfig.fundsInfo.values.where((f) => f.isSpecial).length;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    final Widget exportCard = fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.drive_folder_upload_rounded,
                  color: Colors.blueAccent, size: 22),
              SizedBox(width: 8),
              Text('选择性数据备份 (导出)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '将当前应用的数据有选择地打包保存至一个 JSON 文件中，便于离线备份或多端迁移。',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // 本地数据统计概览
          const Text('当前设备数据统计：',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatBadge('自选看板', '$localFundsCount 个', isDark),
              _buildStatBadge('持有基金', '$localHoldingsCount 个', isDark),
              _buildStatBadge('特别关注', '$localSpecialsCount 个', isDark),
              _buildStatBadge('寻优策略', '$_localStrategyCount 条', isDark),
            ],
          ),
          const SizedBox(height: 20),

          // 勾选项列表
          const Text('勾选需要导出的数据类别：',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          ScaledCheckbox(
            checked: _expFundsList,
            onChanged: (val) => setState(() => _expFundsList = val ?? false),
            content: const Text('自选基金看板列表 (含置顶状态)'),
          ),
          const SizedBox(height: 10),
          ScaledCheckbox(
            checked: _expHoldings,
            onChanged: (val) => setState(() => _expHoldings = val ?? false),
            content: const Text('持有基金信息 (持仓本金、收益率)'),
          ),
          const SizedBox(height: 10),
          ScaledCheckbox(
            checked: _expSpecials,
            onChanged: (val) => setState(() => _expSpecials = val ?? false),
            content: const Text('特别关注基金列表'),
          ),
          const SizedBox(height: 10),
          ScaledCheckbox(
            checked: _expStrategies,
            onChanged: (val) => setState(() => _expStrategies = val ?? false),
            content: const Text('最优回测策略参数 (已寻优出来的回测阈值记录)'),
          ),
          const SizedBox(height: 10),
          ScaledCheckbox(
            checked: _expSettings,
            onChanged: (val) => setState(() => _expSettings = val ?? false),
            content: const Row(
              children: [
                Text('系统全局参数设置'),
                SizedBox(width: 4),
                fluent.Tooltip(
                  message: '包含主题模式、Deepseek 密钥及自定义监控参数。恢复时会覆盖本地密钥！',
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 14),
                ),
              ],
            ),
          ),

          // 密码加密备份选项
          const SizedBox(height: 10),
          ScaledCheckbox(
            checked: _enableExportEncrypt,
            onChanged: (val) =>
                setState(() => _enableExportEncrypt = val ?? false),
            content: const Text('对备份文件进行密码加密（推荐）'),
          ),
          if (_enableExportEncrypt) ...[
            const SizedBox(height: 8),
            fluent.TextBox(
              controller: _exportPasswordController,
              placeholder: '输入加密备份的密码',
              obscureText: true,
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 24),

          // 导出按钮
          SizedBox(
            width: double.infinity,
            child: fluent.FilledButton(
              onPressed: () => _performExport(appConfig),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_alt_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('选择路径并导出备份',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget importCard = fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings_backup_restore_rounded,
                  color: Color(0xFF00E676), size: 22),
              SizedBox(width: 8),
              Text('选择性数据恢复 (导入)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '读取已导出的 JSON 备份文件，并根据勾选细项将其应用到当前系统中。',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_selectedImportPath == null) ...[
            // 未选择文件时的引导
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.02)
                    : Colors.black.withOpacity(0.01),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_open_outlined,
                      size: 36, color: Colors.grey.withOpacity(0.6)),
                  const SizedBox(height: 12),
                  fluent.Button(
                    onPressed: _pickImportFile,
                    child: const Text('选择备份文件 (.json)'),
                  ),
                ],
              ),
            ),
            if (!isSmallScreen) const SizedBox(height: 110), // 填充对齐高度
          ] else ...[
            // 已选择文件，解析数据统计与选项勾选
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path.basename(_selectedImportPath!),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                fluent.IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 14, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _selectedImportPath = null;
                      _parsedBackupData = null;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 备份文件数据量解析展示
            const Text('备份文件包含的数据统计：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatBadge(
                    '自选看板',
                    _parsedBackupData!['funds_list'] != null
                        ? '${(_parsedBackupData!['funds_list'] as List).length} 个'
                        : '无数据',
                    isDark),
                _buildStatBadge(
                    '持有基金',
                    _parsedBackupData!['holdings'] != null
                        ? '${(_parsedBackupData!['holdings'] as List).length} 个'
                        : '无数据',
                    isDark),
                _buildStatBadge(
                    '特别关注',
                    _parsedBackupData!['specials'] != null
                        ? '${(_parsedBackupData!['specials'] as List).length} 个'
                        : '无数据',
                    isDark),
                _buildStatBadge(
                    '寻优策略',
                    _parsedBackupData!['optimal_strategies'] != null
                        ? '${(_parsedBackupData!['optimal_strategies'] as Map).length} 条'
                        : '无数据',
                    isDark),
              ],
            ),
            const SizedBox(height: 16),

            // 数据项勾选恢复
            const Text('勾选需要导入的数据类别：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 10),
            ScaledCheckbox(
              checked: _impFundsList,
              onChanged: _parsedBackupData!['funds_list'] != null
                  ? (val) => setState(() => _impFundsList = val ?? false)
                  : null,
              content: Text(
                '自选基金看板列表',
                style: TextStyle(
                    color: _parsedBackupData!['funds_list'] == null
                        ? Colors.grey
                        : null),
              ),
            ),
            const SizedBox(height: 6),
            ScaledCheckbox(
              checked: _impHoldings,
              onChanged: _parsedBackupData!['holdings'] != null
                  ? (val) => setState(() => _impHoldings = val ?? false)
                  : null,
              content: Text(
                '持有基金信息 (本金、收益率)',
                style: TextStyle(
                    color: _parsedBackupData!['holdings'] == null
                        ? Colors.grey
                        : null),
              ),
            ),
            const SizedBox(height: 6),
            ScaledCheckbox(
              checked: _impSpecials,
              onChanged: _parsedBackupData!['specials'] != null
                  ? (val) => setState(() => _impSpecials = val ?? false)
                  : null,
              content: Text(
                '特别关注基金列表',
                style: TextStyle(
                    color: _parsedBackupData!['specials'] == null
                        ? Colors.grey
                        : null),
              ),
            ),
            const SizedBox(height: 6),
            ScaledCheckbox(
              checked: _impStrategies,
              onChanged: _parsedBackupData!['optimal_strategies'] != null
                  ? (val) => setState(() => _impStrategies = val ?? false)
                  : null,
              content: Text(
                '最优回测策略参数',
                style: TextStyle(
                    color: _parsedBackupData!['optimal_strategies'] == null
                        ? Colors.grey
                        : null),
              ),
            ),
            const SizedBox(height: 6),
            ScaledCheckbox(
              checked: _impSettings,
              onChanged: _parsedBackupData!['global_settings'] != null
                  ? (val) => setState(() => _impSettings = val ?? false)
                  : null,
              content: Row(
                children: [
                  Text(
                    '系统全局参数配置',
                    style: TextStyle(
                        color: _parsedBackupData!['global_settings'] == null
                            ? Colors.grey
                            : null),
                  ),
                  if (_parsedBackupData!['global_settings'] != null) ...[
                    const SizedBox(width: 4),
                    const fluent.Tooltip(
                      message: '恢复此项将覆盖您的 DeepSeek API Key 设置！',
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 14),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 导入合并/覆盖模式选择
            const Text('选择导入冲突处理规则：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            isSmallScreen
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      fluent.RadioButton(
                        checked: _isMergeMode,
                        onChanged: (val) {
                          if (val) setState(() => _isMergeMode = true);
                        },
                        content: const Text('合并导入 (保留本地已有基金，增量更新)',
                            style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(height: 8),
                      fluent.RadioButton(
                        checked: !_isMergeMode,
                        onChanged: (val) {
                          if (val) setState(() => _isMergeMode = false);
                        },
                        content: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('覆盖导入 (完全清空以备份文件为准)',
                                style: TextStyle(fontSize: 11)),
                            SizedBox(width: 4),
                            Icon(Icons.report_problem_rounded,
                                color: Colors.redAccent, size: 13),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      fluent.RadioButton(
                        checked: _isMergeMode,
                        onChanged: (val) {
                          if (val) setState(() => _isMergeMode = true);
                        },
                        content: const Text('合并导入 (保留本地已有基金，增量更新)'),
                      ),
                      const SizedBox(width: 20),
                      fluent.RadioButton(
                        checked: !_isMergeMode,
                        onChanged: (val) {
                          if (val) setState(() => _isMergeMode = false);
                        },
                        content: const Row(
                          children: [
                            Text('覆盖导入 (完全清空以备份文件为准)'),
                            SizedBox(width: 4),
                            Icon(Icons.report_problem_rounded,
                                color: Colors.redAccent, size: 13),
                          ],
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 20),

            // 导入提交按钮
            SizedBox(
              width: double.infinity,
              child: _isImporting
                  ? const fluent.ProgressBar()
                  : fluent.FilledButton(
                      onPressed: () => _performImport(appConfig, fundProvider),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.update_rounded, size: 16),
                            SizedBox(width: 6),
                            Text('执行所选数据导入',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );

    final Widget themeCard = fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_rounded, color: Colors.purpleAccent, size: 22),
              SizedBox(width: 8),
              Text('界面外观设置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '调整软件的显示主题模式，包括亮色主题、暗色主题或根据您的系统设置自动切换。',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _ThemeSelectCard(
                mode: 'Light',
                title: '浅色主题',
                icon: Icons.light_mode_rounded,
                bgStart: const Color(0xFFF0F4F8),
                bgEnd: const Color(0xFFE2E8F0),
                isSelected: appConfig.themeMode == 'Light',
                isDark: isDark,
                onTap: () => appConfig.toggleTheme('Light'),
              ),
              _ThemeSelectCard(
                mode: 'Dark',
                title: '深色主题',
                icon: Icons.dark_mode_rounded,
                bgStart: const Color(0xFF1B2A32),
                bgEnd: const Color(0xFF0F172A),
                isSelected: appConfig.themeMode == 'Dark',
                isDark: isDark,
                onTap: () => appConfig.toggleTheme('Dark'),
              ),
              _ThemeSelectCard(
                mode: 'System',
                title: '跟随系统',
                icon: Icons.settings_brightness_rounded,
                bgStart: const Color(0xFFF0F4F8),
                bgEnd: const Color(0xFFE2E8F0),
                isSelected: appConfig.themeMode == 'System' ||
                    (appConfig.themeMode != 'Light' &&
                        appConfig.themeMode != 'Dark'),
                isDark: isDark,
                onTap: () => appConfig.toggleTheme('System'),
              ),
            ],
          ),
        ],
      ),
    );

    final bottomPad = MediaQuery.of(context).padding.bottom;

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isSmallScreen) const MobileHeader(title: '数据管理'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24.0,
                  right: 24.0,
                  top: isSmallScreen ? 12.0 : 8.0,
                  bottom: isSmallScreen ? 24.0 + bottomPad : 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 信息反馈条
                    if (_infoBarMessage != null) ...[
                      fluent.InfoBar(
                        title: Text(_infoBarTitle ?? '提示'),
                        content: Text(_infoBarMessage!),
                        severity: _infoBarSeverity,
                        onClose: () {
                          setState(() {
                            _infoBarMessage = null;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 界面外观设置
                    themeCard,
                    const SizedBox(height: 20),

                    // 两个分栏卡片布局
                    isSmallScreen
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              exportCard,
                              const SizedBox(height: 20),
                              importCard,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: exportCard),
                              const SizedBox(width: 20),
                              Expanded(child: importCard),
                            ],
                          ),

                    const SizedBox(height: 20),

                    // 云端同步 Supabase 卡片
                    fluent.Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.cloud_sync_rounded,
                                  color: Colors.blueAccent, size: 22),
                              SizedBox(width: 8),
                              Expanded(
                                  child: Text('云端数据同步 (Supabase)',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '通过 Supabase 云服务安全托管您的持仓、自选看板、置顶及特别关注列表，方便实现多客户端数据实时同步。',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          if (!SupabaseManager().isLoggedIn) ...[
                            const Text('邮箱地址', style: TextStyle(fontSize: 11)),
                            const SizedBox(height: 6),
                            fluent.TextBox(
                              controller: _emailController,
                              placeholder: 'user@example.com',
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            ),
                            const SizedBox(height: 10),
                            if (_isRegisteringMode) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.vpn_key_rounded,
                                        size: 16, color: Colors.blueAccent),
                                    const SizedBox(width: 8),
                                    const Text('推荐密码：',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                    Expanded(
                                      child: Text(
                                        _recommendedPassword,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    fluent.Tooltip(
                                      message: '复制并填充',
                                      child: fluent.IconButton(
                                        icon: const Icon(Icons.copy_all_rounded,
                                            size: 16, color: Colors.blueAccent),
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(
                                              text: _recommendedPassword));
                                          setState(() {
                                            _passwordController.text =
                                                _recommendedPassword;
                                            _confirmPasswordController.text =
                                                _recommendedPassword;
                                          });
                                          _showInfoBar(
                                              '密码已填充',
                                              '推荐密码已成功复制到剪贴板并自动填入密码框。',
                                              fluent.InfoBarSeverity.success);
                                        },
                                      ),
                                    ),
                                    fluent.Tooltip(
                                      message: '换一个',
                                      child: fluent.IconButton(
                                        icon: const Icon(Icons.refresh_rounded,
                                            size: 16, color: Colors.grey),
                                        onPressed: () {
                                          setState(() {
                                            _recommendedPassword =
                                                _generateRecommendedPassword();
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_isRegisteringMode ? '注册密码' : '登录密码',
                                    style: const TextStyle(fontSize: 11)),
                                if (!_isRegisteringMode)
                                  fluent.HyperlinkButton(
                                    onPressed: _handleForgotPassword,
                                    child: const Text('忘记密码？',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onSecondaryTapDown: (details) {
                                PasteHelper.showPasteMenu(
                                    context,
                                    details.globalPosition,
                                    _passwordController);
                              },
                              onLongPressStart: (details) {
                                PasteHelper.showPasteMenu(
                                    context,
                                    details.globalPosition,
                                    _passwordController);
                              },
                              child: fluent.TextBox(
                                controller: _passwordController,
                                placeholder: _isRegisteringMode
                                    ? '请输入 8-20 位包含大小写字母、数字或符号的密码'
                                    : '密码不得少于 6 位',
                                obscureText: true,
                                enableInteractiveSelection: true,
                                suffix: PasteHelper.buildPasteSuffix(
                                    context: context,
                                    controller: _passwordController),
                                contextMenuBuilder:
                                    (context, editableTextState) {
                                  return Material(
                                    type: MaterialType.transparency,
                                    child: AdaptiveTextSelectionToolbar
                                        .buttonItems(
                                      anchors:
                                          editableTextState.contextMenuAnchors,
                                      buttonItems: [
                                        ContextMenuButtonItem(
                                          onPressed: () {
                                            editableTextState.pasteText(
                                                SelectionChangedCause.toolbar);
                                          },
                                          type: ContextMenuButtonType.paste,
                                          label: '粘贴',
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                            ),
                            if (_isRegisteringMode) ...[
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final strength = _getPasswordStrength();
                                  Color strengthColor;
                                  String strengthText;
                                  double progressValue;

                                  switch (strength) {
                                    case PasswordStrength.weak:
                                      strengthColor = Colors.redAccent;
                                      strengthText =
                                          _passwordController.text.isEmpty
                                              ? '待输入'
                                              : '弱 (不安全)';
                                      progressValue =
                                          _passwordController.text.isEmpty
                                              ? 0.0
                                              : 0.33;
                                      break;
                                    case PasswordStrength.medium:
                                      strengthColor = Colors.orangeAccent;
                                      strengthText = '中 (可使用)';
                                      progressValue = 0.66;
                                      break;
                                    case PasswordStrength.strong:
                                      strengthColor = const Color(0xFF00E676);
                                      strengthText = '强 (极安全)';
                                      progressValue = 1.0;
                                      break;
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('密码强度：',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey)),
                                          Text(
                                            strengthText,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _passwordController
                                                      .text.isEmpty
                                                  ? Colors.grey
                                                  : strengthColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: Container(
                                          height: 4,
                                          width: double.infinity,
                                          color: isDark
                                              ? Colors.white.withOpacity(0.1)
                                              : Colors.black.withOpacity(0.05),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: FractionallySizedBox(
                                              widthFactor: progressValue,
                                              child: Container(
                                                color: strengthColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          _buildStrengthCriteria('8-20 位字符',
                                              _hasMinLength, isDark),
                                          _buildStrengthCriteria(
                                              '大写字母', _hasUppercase, isDark),
                                          _buildStrengthCriteria(
                                              '小写字母', _hasLowercase, isDark),
                                          _buildStrengthCriteria('数字/符号',
                                              _hasDigitsOrSpecials, isDark),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              const Text('确认密码',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onSecondaryTapDown: (details) {
                                  PasteHelper.showPasteMenu(
                                      context,
                                      details.globalPosition,
                                      _confirmPasswordController);
                                },
                                onLongPressStart: (details) {
                                  PasteHelper.showPasteMenu(
                                      context,
                                      details.globalPosition,
                                      _confirmPasswordController);
                                },
                                child: fluent.TextBox(
                                  controller: _confirmPasswordController,
                                  placeholder: '请再次输入密码',
                                  obscureText: true,
                                  enableInteractiveSelection: true,
                                  suffix: PasteHelper.buildPasteSuffix(
                                      context: context,
                                      controller: _confirmPasswordController),
                                  contextMenuBuilder:
                                      (context, editableTextState) {
                                    return Material(
                                      type: MaterialType.transparency,
                                      child: AdaptiveTextSelectionToolbar
                                          .buttonItems(
                                        anchors: editableTextState
                                            .contextMenuAnchors,
                                        buttonItems: [
                                          ContextMenuButtonItem(
                                            onPressed: () {
                                              editableTextState.pasteText(
                                                  SelectionChangedCause
                                                      .toolbar);
                                            },
                                            type: ContextMenuButtonType.paste,
                                            label: '粘贴',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _isAuthOperating
                                ? const fluent.ProgressBar()
                                : Row(
                                    children: [
                                      if (!_isRegisteringMode) ...[
                                        Expanded(
                                          child: fluent.FilledButton(
                                            onPressed: () => _handleAuth(
                                                appConfig, fundProvider, false),
                                            child: const Text('登录云端账号'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        fluent.Button(
                                          onPressed: () {
                                            setState(() {
                                              _isRegisteringMode = true;
                                              _confirmPasswordController
                                                  .clear();
                                              if (_recommendedPassword
                                                  .isEmpty) {
                                                _recommendedPassword =
                                                    _generateRecommendedPassword();
                                              }
                                            });
                                          },
                                          child: const Text('去注册新账号'),
                                        ),
                                      ] else ...[
                                        Expanded(
                                          child: fluent.FilledButton(
                                            onPressed: () => _handleAuth(
                                                appConfig, fundProvider, true),
                                            child: const Text('立即注册'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        fluent.Button(
                                          onPressed: () {
                                            setState(() {
                                              _isRegisteringMode = false;
                                            });
                                          },
                                          child: const Text('返回登录'),
                                        ),
                                      ],
                                    ],
                                  ),
                          ] else ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF00E676).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: const Color(0xFF00E676)
                                        .withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.cloud_done_rounded,
                                      color: Color(0xFF00E676), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '当前已登录云端。同步账号: ${SupabaseManager().currentUserEmail}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _isCloudSyncing || _isAuthOperating
                                ? const fluent.ProgressBar()
                                : Row(
                                    children: [
                                      Expanded(
                                        child: fluent.FilledButton(
                                          onPressed: () => _handleManualSync(
                                              appConfig, fundProvider),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.sync_rounded,
                                                  size: 14),
                                              SizedBox(width: 6),
                                              Text('同步数据'),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: fluent.Button(
                                          onPressed: () => _handleSignOut(
                                              appConfig, fundProvider),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.logout_rounded,
                                                  size: 14),
                                              SizedBox(width: 6),
                                              Text('退出登录'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncConflictDialog extends StatefulWidget {
  final List<SyncConflict> conflicts;

  const SyncConflictDialog({super.key, required this.conflicts});

  @override
  State<SyncConflictDialog> createState() => _SyncConflictDialogState();
}

class _SyncConflictDialogState extends State<SyncConflictDialog> {
  final Map<String, SyncConflictResolution> _resolutions = {};

  @override
  void initState() {
    super.initState();
    for (final conflict in widget.conflicts) {
      _resolutions[conflict.code] = SyncConflictResolution.keepCloud;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    return fluent.ContentDialog(
      title: const Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: Colors.orange, size: 24),
          SizedBox(width: 8),
          Text('同步差异与冲突处理', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 550),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '检测到本地与云端的数据在相同字段存在不同的修改。请选择要保留的版本：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ...widget.conflicts.map((conflict) {
              final local = conflict.local;
              final cloud = conflict.cloud;
              final code = conflict.code;
              final currentRes = _resolutions[code];

              return fluent.Card(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${local.name} ($code)',
                          style: const TextStyle(
                              fontWeight: fluent.FontWeight.bold, fontSize: 13),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '数值差异',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // 本地版本
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _resolutions[code] =
                                    SyncConflictResolution.keepLocal;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: currentRes ==
                                        SyncConflictResolution.keepLocal
                                    ? const Color(0xFF00E676).withOpacity(0.08)
                                    : (isDark
                                        ? Colors.white.withOpacity(0.02)
                                        : Colors.black.withOpacity(0.01)),
                                border: Border.all(
                                  color: currentRes ==
                                          SyncConflictResolution.keepLocal
                                      ? const Color(0xFF00E676)
                                      : (isDark
                                          ? Colors.white10
                                          : Colors.black12),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      fluent.RadioButton(
                                        checked: currentRes ==
                                            SyncConflictResolution.keepLocal,
                                        onChanged: (val) {
                                          if (val) {
                                            setState(() {
                                              _resolutions[code] =
                                                  SyncConflictResolution
                                                      .keepLocal;
                                            });
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('保留本地',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('分类: ${local.sector}',
                                      style: const TextStyle(fontSize: 11)),
                                  Text(
                                      '持有: ${local.isHeld ? "是 (￥${local.amount.toThousand(precision: 1)})" : "否"}',
                                      style: const TextStyle(fontSize: 11)),
                                  if (local.isHeld)
                                    Text(
                                        '收益率: ${(local.yieldRate * 100).toThousand(precision: 2)}%',
                                        style: const TextStyle(fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '更新: ${local.updatedAt.toIso8601String().substring(5, 16).replaceFirst("T", " ")}',
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 云端版本
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _resolutions[code] =
                                    SyncConflictResolution.keepCloud;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: currentRes ==
                                        SyncConflictResolution.keepCloud
                                    ? const Color(0xFF00E676).withOpacity(0.08)
                                    : (isDark
                                        ? Colors.white.withOpacity(0.02)
                                        : Colors.black.withOpacity(0.01)),
                                border: Border.all(
                                  color: currentRes ==
                                          SyncConflictResolution.keepCloud
                                      ? const Color(0xFF00E676)
                                      : (isDark
                                          ? Colors.white10
                                          : Colors.black12),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      fluent.RadioButton(
                                        checked: currentRes ==
                                            SyncConflictResolution.keepCloud,
                                        onChanged: (val) {
                                          if (val) {
                                            setState(() {
                                              _resolutions[code] =
                                                  SyncConflictResolution
                                                      .keepCloud;
                                            });
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('保留云端',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('分类: ${cloud.sector}',
                                      style: const TextStyle(fontSize: 11)),
                                  Text(
                                      '持有: ${cloud.isHeld ? "是 (￥${cloud.amount.toThousand(precision: 1)})" : "否"}',
                                      style: const TextStyle(fontSize: 11)),
                                  if (cloud.isHeld)
                                    Text(
                                        '收益率: ${(cloud.yieldRate * 100).toThousand(precision: 2)}%',
                                        style: const TextStyle(fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '更新: ${cloud.updatedAt.toIso8601String().substring(5, 16).replaceFirst("T", " ")}',
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        fluent.Button(
          child: const Text('全部选本地'),
          onPressed: () {
            setState(() {
              for (final conflict in widget.conflicts) {
                _resolutions[conflict.code] = SyncConflictResolution.keepLocal;
              }
            });
          },
        ),
        fluent.Button(
          child: const Text('全部选云端'),
          onPressed: () {
            setState(() {
              for (final conflict in widget.conflicts) {
                _resolutions[conflict.code] = SyncConflictResolution.keepCloud;
              }
            });
          },
        ),
        fluent.FilledButton(
          child: const Text('应用冲突合并'),
          onPressed: () {
            Navigator.pop(context, _resolutions);
          },
        ),
      ],
    );
  }
}

Future<Map<String, SyncConflictResolution>> showSyncConflictDialog(
  BuildContext context,
  List<SyncConflict> conflicts,
) async {
  final result = await fluent.showDialog<Map<String, SyncConflictResolution>>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SyncConflictDialog(conflicts: conflicts),
  );
  return result ??
      conflicts.fold<Map<String, SyncConflictResolution>>({}, (map, c) {
        map[c.code] = SyncConflictResolution.keepCloud;
        return map;
      });
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ThemeSelectCard extends StatefulWidget {
  final String mode;
  final String title;
  final IconData icon;
  final Color bgStart;
  final Color bgEnd;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeSelectCard({
    required this.mode,
    required this.title,
    required this.icon,
    required this.bgStart,
    required this.bgEnd,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_ThemeSelectCard> createState() => _ThemeSelectCardState();
}

class _ThemeSelectCardState extends State<_ThemeSelectCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = fluent.FluentTheme.of(context).accentColor;
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 140,
          height: 90,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? activeColor
                  : (_isHovered
                      ? (widget.isDark ? Colors.white30 : Colors.black38)
                      : (widget.isDark ? Colors.white10 : Colors.black12)),
              width: widget.isSelected ? 2.0 : 1.0,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : (_isHovered
                    ? [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(widget.isDark ? 0.3 : 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : []),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // 背景预览
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.bgStart, widget.bgEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // 如果是跟随系统，画一个斜切，表现一半白一半黑
                if (widget.mode == 'System')
                  Positioned.fill(
                    child: ClipPath(
                      clipper: _DiagonalClipper(),
                      child: Container(
                        color: const Color(0xFF1B2A32),
                      ),
                    ),
                  ),
                // 内部小窗口/布局模拟线，使其看起来更像一个主题预览
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.mode == 'Light'
                          ? Colors.black.withOpacity(0.05)
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.mode == 'Light'
                                ? Colors.black26
                                : Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 20,
                          height: 3,
                          decoration: BoxDecoration(
                            color: widget.mode == 'Light'
                                ? Colors.black26
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 28,
                  left: 10,
                  width: 50,
                  height: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.mode == 'Light'
                          ? Colors.black.withOpacity(0.04)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  top: 28,
                  left: 66,
                  width: 54,
                  height: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.mode == 'Light'
                          ? Colors.black.withOpacity(0.04)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // 底部文字和图标
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 28,
                  child: Container(
                    color: widget.mode == 'Light'
                        ? Colors.white.withOpacity(0.9)
                        : Colors.black.withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.icon,
                              size: 12,
                              color: widget.isSelected
                                  ? activeColor
                                  : (widget.isDark
                                      ? Colors.white60
                                      : Colors.black54),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: widget.isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: widget.isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (widget.isSelected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 12,
                            color: activeColor,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
