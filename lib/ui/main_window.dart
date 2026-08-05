import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' show Icons, Colors;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../core/fund_provider.dart';
import '../core/config.dart';
import '../core/services/update_service.dart';
import 'widgets/update_dialog.dart';
import 'tabs/holding_tab.dart';
import 'tabs/my_funds_tab.dart';
import 'tabs/special_attention_tab.dart';
import 'tabs/ranking_tab.dart';
import 'tabs/valuation_tab.dart';
import 'tabs/cycle_board_tab.dart';
import 'tabs/strategy_center_tab.dart';
import 'tabs/backup_tab.dart';
import 'tabs/simulation_tab.dart';

class MainWindow extends StatefulWidget {
  const MainWindow({super.key});

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  final GlobalKey<fluent.NavigationViewState> _navigationViewKey =
      GlobalKey<fluent.NavigationViewState>();
  final List<Widget> _tabs = [
    const HoldingTab(),
    const SpecialAttentionTab(),
    const MyFundsTab(),
    const RankingTab(),
    const ValuationTab(),
    const CycleBoardTab(),
    const StrategyCenterTab(),
    const SimulationTab(),
    const BackupTab(),
  ];

  DateTime? _lastPressedAt;
  late FundProvider _fundProvider;
  bool _wasRefreshing = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fundProvider = Provider.of<FundProvider>(context, listen: false);
    _fundProvider.addListener(_onFundProviderChanged);
    _fundProvider.onOpenDrawer = () {
      if (mounted) {
        _navigationViewKey.currentState?.isMinimalPaneOpen = true;
      }
    };
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    // 窗口加载出来后自动在后台触发静默刷新以同步实时估值数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fundProvider.refreshAll();
      // 后台预加载涨跌榜和估值雷达数据，用户点击对应 tab 时无需等待
      _fundProvider.fetchRankings();
      _fundProvider.fetchValuations();
      _checkAutoUpdate();
    });
    // 每隔 3 分钟在后台检查并自动刷新一次估值数据
    // 优化：降低频率以减少内存分配和 GC 压力
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      _fundProvider.refreshAll();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _fundProvider.removeListener(_onFundProviderChanged);
    _fundProvider.onOpenDrawer = null;
    super.dispose();
  }

  Future<void> _checkAutoUpdate() async {
    try {
      if (!mounted) return;
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      if (!appConfig.autoCheckUpdate) return;

      final updateInfo = await UpdateService.checkUpdate();
      if (updateInfo != null && updateInfo.hasUpdate && mounted) {
        if (!updateInfo.isForce &&
            appConfig.ignoredUpdateVersion == updateInfo.latestVersion) {
          return;
        }
        await UpdateDialog.show(context, updateInfo: updateInfo);
      }
    } catch (e) {
      debugPrint('启动自动检查更新失败: $e');
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // 避免干扰文本框的常规输入与快捷键操作
      final primaryFocus = FocusManager.instance.primaryFocus;
      final isTextFieldFocused = primaryFocus != null &&
          (primaryFocus.context?.widget is EditableText ||
              primaryFocus.debugLabel?.contains('EditableText') == true);
      if (isTextFieldFocused) {
        return false;
      }

      final isControlPressed = HardwareKeyboard.instance.isControlPressed;
      if (event.logicalKey == LogicalKeyboardKey.f5) {
        _fundProvider.refreshAll(isForce: true);
        return true;
      }
      if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyR) {
        _fundProvider.refreshAll(isForce: true);
        return true;
      }
      if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
        _fundProvider.triggerSearchFocus();
        return true;
      }
    }
    return false;
  }

  void _onFundProviderChanged() {
    if (!mounted) return;
    final isRefreshing = _fundProvider.isRefreshing;

    // 如果是从“正在刷新”变为“刷新完成”
    if (_wasRefreshing && !isRefreshing) {
      if (_fundProvider.refreshErrors.isNotEmpty) {
        fluent.displayInfoBar(
          context,
          builder: (context, close) {
            return fluent.InfoBar(
              title: const Text('数据刷新完成，但有部分异常'),
              content: Text(
                  '本次刷新有 ${_fundProvider.refreshErrors.length} 个基金暂无估值或抓取失败，已在标题栏标出，点击可查看详情。'),
              severity: fluent.InfoBarSeverity.warning,
              onClose: close,
              action: fluent.Button(
                child: const Text('查看详情'),
                onPressed: () {
                  close();
                  _showErrorDetailsDialog(context);
                },
              ),
            );
          },
          duration: const Duration(seconds: 6),
        );
      }
    }
    _wasRefreshing = isRefreshing;
  }

  void _showErrorDetailsDialog(BuildContext context) {
    fluent.showDialog(
      context: context,
      builder: (context) {
        return Consumer<FundProvider>(
          builder: (context, provider, _) {
            if (provider.refreshErrors.isEmpty) {
              return fluent.ContentDialog(
                title: const Text('提示'),
                content: const Text('已无未处理的异常信息。'),
                actions: [
                  fluent.Button(
                    child: const Text('关闭'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              );
            }
            return fluent.ContentDialog(
              title: const Text('基金估值抓取异常详情'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '在最近一次刷新中，以下基金在抓取时出现异常或暂无估值：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: fluent.FluentTheme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: fluent.FluentTheme.of(context)
                              .resources
                              .subtleFillColorSecondary,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: provider.refreshErrors.map((err) {
                          final isNoValuation = err.contains('暂无估值');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isNoValuation
                                      ? Icons.info_outline
                                      : Icons.error_outline,
                                  color: isNoValuation
                                      ? Colors.orange
                                      : Colors.red,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    err,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                fluent.Button(
                  child: const Text('复制全部错误'),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: provider.refreshErrors.join('\n')));
                    fluent.displayInfoBar(
                      context,
                      builder: (context, close) => fluent.InfoBar(
                        title: const Text('复制成功'),
                        content: const Text('异常日志已复制到剪贴板'),
                        severity: fluent.InfoBarSeverity.success,
                        onClose: close,
                      ),
                      duration: const Duration(seconds: 2),
                    );
                  },
                ),
                fluent.Button(
                  child: const Text('清除提醒'),
                  onPressed: () {
                    provider.clearRefreshErrors();
                    Navigator.pop(context);
                  },
                ),
                fluent.FilledButton(
                  child: const Text('重新刷新'),
                  onPressed: () {
                    Navigator.pop(context);
                    provider.refreshAll(isForce: true);
                  },
                ),
                fluent.Button(
                  child: const Text('关闭'),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fundProviderListenFalse =
        Provider.of<FundProvider>(context, listen: false);
    final currentTabIndex =
        context.select<FundProvider, int>((p) => p.currentTabIndex);
    final refreshErrorsCount =
        context.select<FundProvider, int>((p) => p.refreshErrors.length);
    final hasRefreshErrors = refreshErrorsCount > 0;
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final bool isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    Widget wrapSafeArea(Widget child) {
      if (isDesktop) return child;
      return SafeArea(
        top: false,
        child: child,
      );
    }

    // 定义所有的导航栏项目
    final List<fluent.NavigationPaneItem> paneItems = [
      fluent.PaneItem(
        icon: const Icon(Icons.account_balance_wallet_rounded,
            color: Color(0xFFFFB300)),
        title: const Text('持有基金'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.favorite_rounded, color: Colors.redAccent),
        title: const Text('特别关注'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const fluent.Icon(fluent.FluentIcons.view_dashboard),
        title: const Text('自选看板'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.trending_up_rounded, color: Color(0xFF00E676)),
        title: const Text('ETF涨跌榜'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.explore_outlined, color: Colors.blueAccent),
        title: const Text('估值雷达'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const fluent.Icon(fluent.FluentIcons.calendar),
        title: const Text('周期榜单'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.psychology_rounded, color: Colors.purpleAccent),
        title: const Text('策略中心'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.analytics_rounded, color: Colors.orangeAccent),
        title: const Text('模拟盘'),
        body: const SizedBox.shrink(),
      ),
      fluent.PaneItem(
        icon: const Icon(Icons.settings_backup_restore_rounded,
            color: Colors.blueGrey),
        title: const Text('数据管理'),
        body: const SizedBox.shrink(),
      ),
    ];

    // 获取当前的文字样式并利用 TextPainter 动态计算最长项的文字宽度
    final paneTheme = fluent.NavigationPaneTheme.of(context);
    final theme = fluent.FluentTheme.of(context);
    final textStyle = paneTheme.unselectedTextStyle?.resolve({}) ??
        theme.typography.body ??
        const TextStyle(fontSize: 14);

    double maxTextWidth = 0;
    for (final item in paneItems) {
      if (item is fluent.PaneItem && item.title is Text) {
        final textData = (item.title as Text).data ?? '';
        final textPainter = TextPainter(
          text: TextSpan(text: textData, style: textStyle),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        if (textPainter.width > maxTextWidth) {
          maxTextWidth = textPainter.width;
        }
      }
    }

    // 动态展开宽度：图标占据区域 (约 50) + 字符宽度 + 内边距与额外安全富余量
    final dynamicOpenWidth = maxTextWidth + 88.0;

    // 辅助构建 AppBar 标题（隔离桌面端 DragToMoveArea）
    final Widget titleWidget = Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: isSmallScreen ? 0.0 : 10.0),
        child: Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Text(
              'FlFund',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (hasRefreshErrors) ...[
              const SizedBox(width: 12),
              fluent.Tooltip(
                message: '有 $refreshErrorsCount 个基金抓取异常或暂无估值，点击查看详情',
                child: fluent.Button(
                  style: fluent.ButtonStyle(
                    backgroundColor:
                        fluent.WidgetStateProperty.resolveWith((states) {
                      if (states.contains(fluent.WidgetState.hovered)) {
                        return Colors.orange.withValues(alpha: 0.2);
                      }
                      return Colors.orange.withValues(alpha: 0.12);
                    }),
                    padding: fluent.WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    shape: fluent.WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                  onPressed: () => _showErrorDetailsDialog(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        '抓取异常 ($refreshErrorsCount)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false, // 拦截系统物理返回
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 若当前不在“持有基金” Tab (0)，则先切回 Tab 0
        if (currentTabIndex != 0) {
          fundProviderListenFalse.setCurrentTabIndex(0);
          return;
        }

        // 双击退出逻辑
        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          fluent.displayInfoBar(
            context,
            builder: (context, close) {
              return fluent.InfoBar(
                title: const Text('提示'),
                content: const Text('再按一次退出应用'),
                severity: fluent.InfoBarSeverity.info,
                onClose: close,
              );
            },
            duration: const Duration(seconds: 2),
          );
          return;
        }
        await SystemNavigator.pop();
      },
      child: fluent.NavigationView(
        key: _navigationViewKey,
        paneBodyBuilder: (item, body) {
          return ExcludeSemantics(
            child: _LazyIndexedStack(
              key: const ValueKey('main_lazy_indexed_stack'),
              index: currentTabIndex,
              children: _tabs.map((tab) => wrapSafeArea(tab)).toList(),
            ),
          );
        },
        titleBar: isSmallScreen
            ? null
            : SizedBox(
                height: isDesktop ? 32.0 : 50.0,
                child: Row(
                  children: [
                    Expanded(
                      child: isDesktop
                          ? DragToMoveArea(child: titleWidget)
                          : titleWidget,
                    ),
                    if (isDesktop)
                      SizedBox(
                        // WindowCaption 内部是 Row+Expanded 结构，必须给定有界宽度，
                        // 否则作为 Row 的非 flex 子项会收到无限宽约束而布局崩溃。
                        // 138 = 最小化/最大化/关闭三个按钮 (46 x 3)。
                        width: 138,
                        child: WindowCaption(
                          brightness: isDark
                              ? fluent.Brightness.dark
                              : fluent.Brightness.light,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                  ],
                ),
              ),
        pane: fluent.NavigationPane(
          selected: currentTabIndex,
          onChanged: (index) {
            fundProviderListenFalse.setCurrentTabIndex(index);
            if (isSmallScreen) {
              _navigationViewKey.currentState?.isMinimalPaneOpen = false;
            }
          },
          // 如果是小屏设备，切换到抽屉 (minimal) 模式，以节省空间；宽屏保持展开 (open) 模式
          displayMode: isSmallScreen
              ? fluent.PaneDisplayMode.minimal
              : fluent.PaneDisplayMode.expanded,
          size: fluent.NavigationPaneSize(
            openWidth: dynamicOpenWidth, // 使用动态计算的宽度
          ),
          items: paneItems,
        ),
      ),
    );
  }
}

/// 懒加载 IndexedStack：只有当 Tab 被首次切入访问时才进行实例化与挂载，
/// 挂载后常驻内存，切换 Tab 时保持页面状态（如搜索词、筛选勾选、排序、滚动位置等）不丢失。
class _LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late List<bool> _activated;

  @override
  void initState() {
    super.initState();
    _activated = List<bool>.filled(widget.children.length, false);
    _activateCurrent();
  }

  @override
  void didUpdateWidget(_LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activateCurrent();
  }

  void _activateCurrent() {
    if (widget.index >= 0 && widget.index < _activated.length) {
      if (!_activated[widget.index]) {
        _activated[widget.index] = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: List.generate(widget.children.length, (i) {
        if (_activated[i]) {
          return widget.children[i];
        } else {
          return const SizedBox.shrink();
        }
      }),
    );
  }
}

