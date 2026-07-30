import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart'
    show Colors, Icons, RefreshIndicator, AlwaysScrollableScrollPhysics;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../core/fund_provider.dart';
import '../../core/config.dart';
import '../../core/utils/pinyin_search.dart';
import '../../core/utils/theme_colors.dart';
import '../widgets/mobile_header.dart';
import '../widgets/fund_chart_dialog.dart';
import '../widgets/copyable_text.dart';

class CycleItem {
  final String name;
  final String code; // 代表性基金代码
  final String description;

  CycleItem(
      {required this.name, required this.code, required this.description});
}

class CycleBoardTab extends StatelessWidget {
  const CycleBoardTab({super.key});

  static final List<CycleItem> cycleItems = [
    CycleItem(
        name: '🐷 畜牧养殖周期',
        code: '012725',
        description: '受猪肉价格影响大，通常有 3-4 年的强产能周期。'),
    CycleItem(
        name: '💾 半导体存储周期',
        code: '008282',
        description: '全球电子消费需求主导，硅片出货量与价格呈强周期性变化。'),
    CycleItem(
        name: '🔥 煤炭能源周期',
        code: '013275',
        description: '受火电及钢厂用煤供求限制，属于防守型周期资产。'),
    CycleItem(
        name: '🪙 有色稀金属周期',
        code: '016708',
        description: '铜、铝、稀土等工业基础原材料，受全球流动性与美元指数影响深远。'),
    CycleItem(
        name: '🍶 白酒大消费周期',
        code: '161725',
        description: '高端商务消费与节假日催化明显，高 ROE 周期性现金牛资产。'),
    CycleItem(
        name: '🏗️ 基础建设水泥周期',
        code: '017057',
        description: '受国内财政刺激和地方城建发债周期直接拉动。'),
    CycleItem(
        name: '📈 证券大金融周期',
        code: '161027',
        description: '俗称"牛市旗手"，受两市总成交量和市场流动性牛熊转换催化。'),
    CycleItem(
        name: '☀️ 新能源光伏周期',
        code: '014605',
        description: '受上游多晶硅料产能投放及光伏并网消纳率周期调节。'),
    CycleItem(
        name: '🛢️ 石油石化周期',
        code: '163208',
        description: '全球原油供需主导，OPEC+ 减产/增产周期，通常 7-10 年大周期。'),
    CycleItem(
        name: '🚢 航运海运周期',
        code: '160724',
        description: 'BDI 干散货运价指数驱动，全球贸易景气度的"温度计"，3-5 年一轮。'),
    CycleItem(
        name: '🏠 房地产周期',
        code: '160218',
        description: '18-25 年库兹涅茨长周期叠加 3-5 年政策短周期，中国经济的基石周期。'),
    CycleItem(
        name: '💊 医药生物周期',
        code: '161726',
        description: '集采政策周期 2-3 年 + 创新药研发管线周期，防御与成长双重属性。'),
    CycleItem(
        name: '📺 面板 LCD 周期',
        code: '007592',
        description: '液晶面板产能投放-过剩-涨价的经典循环，与半导体同属科技硬件周期。'),
  ];

  @override
  Widget build(BuildContext context) {
    final fundProvider = Provider.of<FundProvider>(context);
    final appConfig = Provider.of<AppConfig>(context);
    final isDark =
        fluent.FluentTheme.of(context).brightness == fluent.Brightness.dark;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 640;

    return fluent.ScaffoldPage(
      padding: fluent.EdgeInsets.zero,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSmallScreen) const MobileHeader(title: '周期榜单'),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: isSmallScreen ? 0.0 : 16.0,
                  bottom: 16.0),
              child: RefreshIndicator(
                onRefresh: () async {
                  await appConfig.syncWithSupabase();
                  await fundProvider.refreshAll(isForce: true);
                },
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: cycleItems.length,
                  itemBuilder: (context, index) {
                    final item = cycleItems[index];

                    // 抓取该代表性基金的全量历史百分位
                    double pct = 50.0; // 默认置于均衡期
                    final bool isAdded =
                        fundProvider.myFunds.containsKey(item.code);
                    final model = fundProvider.myFunds[item.code] ??
                        fundProvider.cycleFunds[item.code];

                    if (model != null && model.allHistoryPct != null) {
                      pct = model.allHistoryPct!;
                    }

                    // 行业周期定位算法（用于下方进度条着色）
                    Color stageColor = ThemeColors.getBalanceColor(isDark);

                    // 优先使用去趋势百分位消除长期上涨偏倚，若无则退化为全量百分位
                    final double effectivePct =
                        (model?.detrendedPct ?? model?.allHistoryPct) ?? pct;

                    if (effectivePct < 20.0) {
                      stageColor = ThemeColors.getDepressionColor(isDark);
                    } else if (effectivePct < 50.0) {
                      stageColor = ThemeColors.getRecoveryColor(isDark);
                    } else if (effectivePct < 80.0) {
                      stageColor = ThemeColors.getProsperityColor(isDark);
                    } else {
                      stageColor = ThemeColors.getBubbleColor(isDark);
                    }

                    // 获取实时变动率
                    double change = 0.0;
                    Color changeColor =
                        isDark ? Colors.white70 : Colors.black87;
                    if (isAdded && model != null) {
                      change = double.tryParse(model.gszzl) ?? 0.0;
                      changeColor = change > 0
                          ? ThemeColors.getRedText(isDark)
                          : (change < 0
                              ? ThemeColors.getGreenText(isDark)
                              : Colors.grey);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 板块名称
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 6),
                          Text(
                            item.description,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          // 代表基金的实时信息面板
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.02)
                                  : Colors.black.withOpacity(0.015),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.04)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 第一行：基金名称（完整显示）
                                Row(
                                  children: [
                                    const Text('代表基金: ',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12)),
                                    Expanded(
                                      child: CopyableText(
                                        (isAdded && model != null)
                                            ? model.name
                                            : PinyinSearch()
                                                .getNameByCode(item.code),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                // 第二行：描述文字 + 右侧按钮（向下对齐）
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (isAdded && model != null)
                                            ? '昨日净值: ${model.dwjz} 元 | 实时估值: ${model.gsz} 元'
                                            : '关注该基金后将自动启用周期精准偏离度监控',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 10),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (isAdded && model != null) ...[
                                          Text(
                                            '${change.toThousand(precision: 2, showSign: true)}%',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: changeColor),
                                          ),
                                          const SizedBox(width: 8),
                                          fluent.IconButton(
                                            icon: const Icon(
                                                Icons.psychology_rounded,
                                                size: 16,
                                                color: Colors.purpleAccent),
                                            onPressed: () {
                                              fundProvider
                                                  .switchToBacktest(item.code);
                                            },
                                          ),
                                          const SizedBox(width: 4),
                                          fluent.IconButton(
                                            icon: const Icon(
                                                Icons.show_chart_rounded,
                                                size: 16,
                                                color: Colors.blueAccent),
                                            onPressed: () {
                                              fluent.showDialog(
                                                context: context,
                                                builder: (context) =>
                                                    FundChartDialog(
                                                  fundCode: model.code,
                                                  fundName: model.name,
                                                  navs: model.navs,
                                                  dates: model.dates,
                                                  todayEstimateNav: double.tryParse(model.gsz),
                                                  todayEstimatePct: double.tryParse(model.gszzl),
                                                  todayEstimateTime: model.gztime,
                                                ),
                                              );
                                            },
                                          ),
                                        ] else ...[
                                          fluent.Button(
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.add_rounded,
                                                    size: 12,
                                                    color: Colors.blue),
                                                SizedBox(width: 4),
                                                Text('关注监控',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.blue)),
                                              ],
                                            ),
                                            onPressed: () {
                                              final name = PinyinSearch()
                                                  .getNameByCode(item.code);
                                              appConfig.addFund(
                                                  item.code,
                                                  name != item.code
                                                      ? name
                                                      : '强周期代表基金',
                                                  '强周期监控');
                                              fundProvider.loadMyFunds();
                                              fundProvider.refreshAll();
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // 数据指标：去趋势百分位 + 趋势方向
                          Row(
                            children: [
                              const Icon(Icons.info_outline_rounded,
                                  color: Colors.blue, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '去趋势百分位: ${effectivePct.toThousand(precision: 1)}% | 趋势: ${_trendLabel(model)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          // 多周期百分位小字
                          if (model?.year1Pct != null ||
                              model?.year3Pct != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 20),
                              child: Text(
                                '近1年: ${model?.year1Pct?.toThousand(precision: 0) ?? "--"}% | '
                                '近3年: ${model?.year3Pct?.toThousand(precision: 0) ?? "--"}% | '
                                'Z值: ${model?.zScore?.toThousand(precision: 1) ?? "--"}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 10),
                              ),
                            ),
                          const SizedBox(height: 12),
                          // 位置刻度条
                          Row(
                            children: [
                              const Text('萧条',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: fluent.Tooltip(
                                  message: model != null
                                      ? '估值来源: ${model.source.isNotEmpty ? model.source : "天天基金"}\n计算基准: ${model.detrendedPct != null ? "去趋势百分位" : "全量历史百分位"}\n历史样本: ${model.dates.length}个交易日'
                                      : '数据来源: 天天基金\n计算基准: 默认全量历史百分位\n提示: 关注该基金后可加载完整历史数据',
                                  useMousePosition: true,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: fluent.ProgressBar(
                                      value: effectivePct,
                                      backgroundColor: isDark
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.black.withOpacity(0.08),
                                      activeColor: stageColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('过热',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _trendLabel(FundUIModel? model) {
    if (model == null) return '--';
    switch (model.trendDirection) {
      case TrendDirection.rising:
        return '↑ 上升';
      case TrendDirection.falling:
        return '↓ 下降';
      default:
        return '→ 震荡';
    }
  }
}
