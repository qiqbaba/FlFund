import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/db_manager.dart';
import '../../core/utils/pinyin_search.dart';
import '../../core/fund_provider.dart';
import 'package:provider/provider.dart';

import '../../core/supabase_manager.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onInitComplete;

  const SplashScreen({super.key, required this.onInitComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.15;
  String _statusText = '正在并行建立数据库与预解析字典...';

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    try {
      // 1. 并发执行数据库安全链接建立、配置读取与全市场基金字典预解析
      setState(() {
        _progress = 0.35;
        _statusText = '正在并行初始化核心引擎与基金字典...';
      });

      await Future.wait([
        FundHistoryDB().init(),
        AppConfig().loadConfig(),
        PinyinSearch().init(),
      ]);

      // 2. 如果已登录 Supabase，将云端同步作为后台静默任务运行，不阻塞首屏显示
      if (SupabaseManager().isLoggedIn) {
        unawaited(() async {
          try {
            await AppConfig().syncWithSupabase();
          } catch (e) {
            debugPrint('启动时后台云同步失败: $e');
          }
        }());
      }

      // 3. 快速装载自选 UI 数据
      setState(() {
        _progress = 0.95;
        _statusText = '初始化完成，准备进入主看板...';
      });
      if (mounted) {
        Provider.of<FundProvider>(context, listen: false).loadMyFunds();
      }

      // 4. 立即进入主看板（无需人工硬等待）
      widget.onInitComplete();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = '初始化失败，请重启应用: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final isDark = (() {
      if (appConfig.themeMode == 'Dark') return true;
      if (appConfig.themeMode == 'Light') return false;
      // 默认为系统主题
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    })();

    // 定义浅色和深色下的配色方案
    final bgGradientColors = isDark
        ? const [Color(0xFF0A161B), Color(0xFF1B2A32)]
        : const [Color(0xFFE0F2F1), Color(0xFFF9FBFB)];

    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.85);

    final cardBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final cardShadowColor = isDark
        ? Colors.black.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.06);

    final titleColor = isDark ? Colors.white : const Color(0xFF0A161B);

    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF0A161B).withValues(alpha: 0.65);

    final progressBgColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    final statusTextColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF0A161B).withValues(alpha: 0.55);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgGradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: cardShadowColor,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标志与标题
                const Icon(
                  Icons.analytics_rounded,
                  size: 64,
                  color: Color(0xFF009688),
                ),
                const SizedBox(height: 20),
                Text(
                  'FlFund',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '场外基金量化监控与参数寻优系统',
                  style: TextStyle(
                    fontSize: 14,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 40),
                // 进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: progressBgColor,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF009688)),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 15),
                // 状态提示
                Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
