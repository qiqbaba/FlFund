import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config.dart';
import 'core/fund_provider.dart';
import 'core/simulation_provider.dart';
import 'core/db_manager.dart';
import 'core/utils/win_clipboard_paste_fix.dart';
import 'ui/widgets/splash_screen.dart';
import 'ui/main_window.dart';

/// 全局 HTTP 代理覆盖
/// 从 Dart 运行时层面拦截所有 HttpClient 的创建，
/// 对国内 AI 服务域名强制直连（DIRECT），彻底解决 Windows 系统
/// 残留代理配置（注册表/环境变量）导致的 errno 10054 连接重置问题。
class _DirectConnectHttpOverrides extends HttpOverrides {
  static const _directDomains = [
    'bigmodel.cn',
    'xiaomimimo.com',
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      for (final domain in _directDomains) {
        if (host == domain || host.endsWith('.$domain')) {
          debugPrint('[HttpOverrides] 域名 $host 匹配直连规则 -> DIRECT');
          return 'DIRECT';
        }
      }
      final envProxy = HttpClient.findProxyFromEnvironment(uri);
      if (envProxy != 'DIRECT') {
        debugPrint('[HttpOverrides] 域名 $host 使用系统代理: $envProxy');
      }
      return envProxy;
    };
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 修复 Windows 11 剪贴板历史（Win+V）点击条目无法粘贴到输入框的问题
  if (!kIsWeb && Platform.isWindows) {
    WinClipboardPasteFix.instance.install();
  }

  // 全局强制国内 AI 域名直连，防止系统残留代理干扰
  if (!kIsWeb) {
    HttpOverrides.global = _DirectConnectHttpOverrides();
  }

  // 提前加载配置，以便在应用启动的第一时间获取正确的皮肤主题，避免启动闪烁
  await AppConfig().loadConfig();

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    debugPrint("=== 开始初始化 windowManager ===");
    try {
      await windowManager.ensureInitialized();
      debugPrint("=== windowManager 初始化成功 ===");

      WindowOptions windowOptions = const WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
      );

      debugPrint("=== 注册 waitUntilReadyToShow 回调 ===");
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        debugPrint("=== windowManager 准备就绪，开始显示窗口 ===");
        await windowManager.show();
        await windowManager.focus();
        debugPrint("=== windowManager 主窗口已显示并聚焦 ===");
      });

      // 异步兜底逻辑：防止某些环境下 waitUntilReadyToShow 回调不被触发
      Future.delayed(const Duration(milliseconds: 600), () async {
        try {
          final isVisible = await windowManager.isVisible();
          debugPrint("=== [兜底检测] 窗口当前可见状态: $isVisible ===");
          if (!isVisible) {
            debugPrint("=== [兜底检测] 触发强制显示窗口 ===");
            await windowManager.show();
            await windowManager.focus();
            debugPrint("=== [兜底检测] 强制显示窗口成功 ===");
          }
        } catch (e) {
          debugPrint("=== [兜底检测] 获取窗口状态或强制显示失败: $e ===");
        }
      });
    } catch (e) {
      debugPrint("=== windowManager 初始化发生异常: $e ===");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppConfig()),
        ChangeNotifierProvider(create: (_) => FundProvider()),
        ChangeNotifierProvider(
            create: (_) => SimulationProvider()..loadSimData()),
      ],
      child: const FundApp(),
    ),
  );
}

class FundApp extends StatefulWidget {
  const FundApp({super.key});

  @override
  State<FundApp> createState() => _FundAppState();
}

class _FundAppState extends State<FundApp> {
  bool _isInitComplete = false;

  @override
  void dispose() {
    FundHistoryDB().close();
    super.dispose();
  }

  @override
  Widget build(fluent.BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    // 用 Map 映射代替 if-else 链，更简洁且易于扩展
    final themeMode = const {
          'Dark': fluent.ThemeMode.dark,
          'Light': fluent.ThemeMode.light,
        }[appConfig.themeMode] ??
        fluent.ThemeMode.system;

    return fluent.FluentApp(
      title: 'FlFund',
      themeMode: themeMode,
      // 浅色主题配色
      theme: fluent.FluentThemeData(
        brightness: fluent.Brightness.light,
        fontFamily: 'Segoe UI',
        accentColor: fluent.AccentColor.swatch(const {
          'darkest': Color(0xFF004D40),
          'darker': Color(0xFF00796B),
          'dark': Color(0xFF00897B),
          'normal': Color(0xFF009688),
          'light': Color(0xFF26A69A),
          'lighter': Color(0xFF4DB6AC),
          'lightest': Color(0xFFB2DFDB),
        }),
        scaffoldBackgroundColor: const Color(0xFFF9FBFB),
        navigationPaneTheme: fluent.NavigationPaneThemeData(
          unselectedTextStyle: fluent.WidgetStateProperty.resolveWith((states) {
            return const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.normal,
              height: 1.25,
              letterSpacing: 0.2,
              color: Colors.black87,
              fontFamilyFallback: [
                'Microsoft YaHei',
                'PingFang SC',
                'SimHei',
                'sans-serif',
              ],
            );
          }),
          selectedTextStyle: fluent.WidgetStateProperty.resolveWith((states) {
            return const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0.2,
              color: Colors.black,
              fontFamilyFallback: [
                'Microsoft YaHei',
                'PingFang SC',
                'SimHei',
                'sans-serif',
              ],
            );
          }),
          unselectedIconColor: fluent.WidgetStateProperty.all(Colors.black87),
        ),
      ),
      // 深色主题配色
      darkTheme: fluent.FluentThemeData(
        brightness: fluent.Brightness.dark,
        fontFamily: 'Segoe UI',
        accentColor: fluent.AccentColor.swatch(const {
          'darkest': Color(0xFFB2DFDB),
          'darker': Color(0xFF80CBC4),
          'dark': Color(0xFF4DB6AC),
          'normal': Color(0xFF009688),
          'light': Color(0xFF00897B),
          'lighter': Color(0xFF00796B),
          'lightest': Color(0xFF004D40),
        }),
        scaffoldBackgroundColor: const Color(0xFF1B2A32),
        navigationPaneTheme: fluent.NavigationPaneThemeData(
          unselectedTextStyle: fluent.WidgetStateProperty.resolveWith((states) {
            return const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.normal,
              height: 1.25,
              letterSpacing: 0.2,
              color: Color(0xDDFFFFFF),
              fontFamilyFallback: [
                'Microsoft YaHei',
                'PingFang SC',
                'SimHei',
                'sans-serif',
              ],
            );
          }),
          selectedTextStyle: fluent.WidgetStateProperty.resolveWith((states) {
            return const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
              letterSpacing: 0.2,
              color: Colors.white,
              fontFamilyFallback: [
                'Microsoft YaHei',
                'PingFang SC',
                'SimHei',
                'sans-serif',
              ],
            );
          }),
          unselectedIconColor: fluent.WidgetStateProperty.all(const Color(0xDDFFFFFF)),
        ),
      ),
      home: _isInitComplete
          ? const MainWindow()
          : SplashScreen(
              onInitComplete: () {
                setState(() {
                  _isInitComplete = true;
                });
              },
            ),
    );
  }
}
