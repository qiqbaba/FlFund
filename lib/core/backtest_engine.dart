import 'dart:collection';
import 'dart:math' as math;

class BacktestResult {
  final double winRate;
  final double avgProfit;
  final int totalTrades;
  final bool isRobust;
  final List<Map<String, dynamic>> trades; // 用于在图表里画出买入卖出信号散点
  final double maxDrawdown;
  final double calmarRatio;
  final double annualizedReturn;
  final List<double> equityCurve;
  final double annualizedVolatility;
  final double sharpeRatio;
  final double sortinoRatio;
  final int maxDrawdownDuration;
  final double avgEfficiency;

  BacktestResult({
    required this.winRate,
    required this.avgProfit,
    required this.totalTrades,
    required this.isRobust,
    required this.trades,
    required this.maxDrawdown,
    required this.calmarRatio,
    required this.annualizedReturn,
    required this.equityCurve,
    required this.annualizedVolatility,
    required this.sharpeRatio,
    required this.sortinoRatio,
    required this.maxDrawdownDuration,
    required this.avgEfficiency,
  });
}

class BacktestEngine {
  // 高性能 RSI 计算 (Wilder's RSI 平滑平均法)
  static List<double> calculateRSI(List<double> prices, {int period = 14}) {
    final int n = prices.length;
    final rsi = List<double>.filled(n, 50.0);
    if (n <= period) return rsi;

    double avgGain = 0.0;
    double avgLoss = 0.0;

    for (int i = 1; i <= period; i++) {
      final double change = prices[i] - prices[i - 1];
      if (change > 0) {
        avgGain += change;
      } else {
        avgLoss -= change;
      }
    }
    avgGain /= period;
    avgLoss /= period;

    if (avgLoss == 0) {
      rsi[period] = 100.0;
    } else {
      rsi[period] = 100.0 - (100.0 / (1.0 + avgGain / avgLoss));
    }

    for (int i = period + 1; i < n; i++) {
      final double change = prices[i] - prices[i - 1];
      double gain = 0.0;
      double loss = 0.0;
      if (change > 0) {
        gain = change;
      } else {
        loss = -change;
      }

      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      if (avgLoss == 0) {
        rsi[i] = 100.0;
      } else {
        rsi[i] = 100.0 - (100.0 / (1.0 + avgGain / avgLoss));
      }
    }

    return rsi;
  }

  // 优化版：从原始列表的指定范围读取数据，避免创建 sublist + reversed.toList()
  // navList 是从新到旧（倒序），从 index 开始取 len 个元素，按从旧到新的顺序计算 RSI
  static List<double> calculateRSIFromRange(
      List<double> navList, int startIndex, int len,
      {int period = 14}) {
    if (len <= period) return [];

    // 从 navList 中按从旧到新的顺序读取（navList 是从新到旧，所以从 startIndex+len-1 往回读）
    final rsi = List<double>.filled(len, 50.0);

    double avgGain = 0.0;
    double avgLoss = 0.0;

    // 初始化：读取前 period+1 个价格（从旧到新）
    for (int i = 0; i <= period; i++) {
      final int idx = startIndex + len - 1 - i; // 从旧到新的索引
      if (i > 0) {
        final int prevIdx = startIndex + len - 1 - (i - 1);
        final double change = navList[idx] - navList[prevIdx];
        if (change > 0) {
          avgGain += change;
        } else {
          avgLoss -= change;
        }
      }
    }
    avgGain /= period;
    avgLoss /= period;

    if (avgLoss == 0) {
      rsi[period] = 100.0;
    } else {
      rsi[period] = 100.0 - (100.0 / (1.0 + avgGain / avgLoss));
    }

    for (int i = period + 1; i < len; i++) {
      final int idx = startIndex + len - 1 - i;
      final int prevIdx = startIndex + len - 1 - (i - 1);
      final double change = navList[idx] - navList[prevIdx];
      double gain = 0.0;
      double loss = 0.0;
      if (change > 0) {
        gain = change;
      } else {
        loss = -change;
      }

      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      if (avgLoss == 0) {
        rsi[i] = 100.0;
      } else {
        rsi[i] = 100.0 - (100.0 / (1.0 + avgGain / avgLoss));
      }
    }

    return rsi;
  }

  // 高性能日线 MACD 计算 (DIF >= DEA 判定)
  static List<bool> calculateMACD(List<double> prices) {
    final int n = prices.length;
    final result = List<bool>.filled(n, true);
    if (n < 26) return result;

    double ema12 = prices[0];
    double ema26 = prices[0];
    double dea = 0.0;
    double prevHist = 0.0;

    for (int i = 0; i < n; i++) {
      final double price = prices[i];
      if (i > 0) {
        ema12 = ema12 * (11.0 / 13.0) + price * (2.0 / 13.0);
        ema26 = ema26 * (25.0 / 27.0) + price * (2.0 / 27.0);
      }
      final double dif = ema12 - ema26;
      if (i == 0) {
        dea = dif;
      } else {
        dea = dea * (8.0 / 10.0) + dif * (2.0 / 10.0);
      }
      final double hist = dif - dea;
      // 放宽：DIF>=DEA(多头) 或 MACD 柱状线较前值抬升(动量改善)，
      // 缓解 RSI 超卖与 MACD 多头过滤的互斥（超卖区常伴随 DIF<DEA）
      result[i] = (dif >= dea) || (i > 0 && hist > prevHist);
      prevHist = hist;
    }
    return result;
  }

  // 优化版：从原始列表的指定范围读取数据，避免创建 sublist + reversed.toList()
  // navList 是从新到旧（倒序），从 startIndex 开始取 len 个元素，按从旧到新的顺序计算 MACD
  static List<bool> calculateMACDFromRange(
      List<double> navList, int startIndex, int len) {
    if (len < 26) return [];

    final result = List<bool>.filled(len, true);

    // 第一个价格（最旧的）
    final int firstIdx = startIndex + len - 1;
    double ema12 = navList[firstIdx];
    double ema26 = navList[firstIdx];
    double dea = 0.0;
    double prevHist = 0.0;

    for (int i = 0; i < len; i++) {
      final int idx = startIndex + len - 1 - i; // 从旧到新的索引
      final double price = navList[idx];
      if (i > 0) {
        ema12 = ema12 * (11.0 / 13.0) + price * (2.0 / 13.0);
        ema26 = ema26 * (25.0 / 27.0) + price * (2.0 / 27.0);
      }
      final double dif = ema12 - ema26;
      if (i == 0) {
        dea = dif;
      } else {
        dea = dea * (8.0 / 10.0) + dif * (2.0 / 10.0);
      }
      final double hist = dif - dea;
      // 放宽：DIF>=DEA(多头) 或 MACD 柱状线较前值抬升(动量改善)，
      // 与回测保持一致，缓解 RSI 超卖与 MACD 多头过滤的互斥
      result[i] = (dif >= dea) || (i > 0 && hist > prevHist);
      prevHist = hist;
    }
    return result;
  }

  // 计算日历史净值序列（由远及近）中，指定位置往前的收益率标准差（波动率）
  static double _calculateVolatilityBacktest(
      int dayIdx, int days, List<double> allNavs) {
    int effectiveDays = days;
    if (dayIdx < effectiveDays + 1) {
      effectiveDays = dayIdx - 1;
    }
    if (effectiveDays < 3) return 0.01;

    final List<double> returns = [];
    double sum = 0.0;
    for (int k = dayIdx - effectiveDays + 1; k <= dayIdx; k++) {
      if (k > 0 && allNavs[k - 1] > 0.0) {
        final double r = (allNavs[k] - allNavs[k - 1]) / allNavs[k - 1];
        returns.add(r);
        sum += r;
      }
    }
    if (returns.length < 2) return 0.01;
    final double mean = sum / returns.length;
    double variance = 0.0;
    for (final r in returns) {
      variance += (r - mean) * (r - mean);
    }
    // 使用样本标准差 (n-1)，对波动率做无偏估计
    return math.sqrt(variance / (returns.length - 1));
  }

  // 滚动预计算历史所有位置的波动率以提高效率
  static List<double> precalculateVolatility(List<double> prices, int period) {
    final int n = prices.length;
    final result = List<double>.filled(n, 0.01);
    for (int i = 0; i < n; i++) {
      result[i] = _calculateVolatilityBacktest(i, period, prices);
    }
    return result;
  }

  // 回撤网格回测核心计算
  // allNavs 必须按照时间从远到近排列 (即列表第一个元素是最早日期，最后一个是最新日期)
  static BacktestResult runBacktest({
    required List<double> allNavs,
    required List<String> allDates,
    required int buyDays,
    required double buyDropPct,
    required double targetProfitPct,
    int holdMax = 90,
    bool useMaFilter = false,
    int maPeriod = 0,
    double maEnvelopePct = 0.0,
    double? trailingDropPct,
    double? trailingActivatePct,
    int? sellX,
    double? sellPct,
    List<double>? precalculatedMa,
    List<double>? precalculatedVol10,
    List<double>? precalculatedVol60,
    int maxConcurrentTrades = 5,
    double slippagePct = 0.0,
    double rsiFilterLimit = 0.0,
    bool useMacdFilter = false,
    double gridSpacingPct = 0.0,
    // T+n 赎回资金到账周期（0=当日可用，保持旧行为）
    int settlementDays = 0,
    // 单笔硬止损百分比（0=关闭）
    double stopLossPct = 0.0,
    // 组合级回撤熔断：权益回撤超过该阀值时暂停开新仓（0=关闭）
    double portfolioMaxDrawdownStop = 0.0,
    // 趋势 regime 过滤：>0 时在长期均线下行（确认下降趋势）时不接飞刀（0=关闭）
    int regimeMaPeriod = 0,
    // 估值百分位过滤序列与上限（历史序列不可得时为 null，保持 no-op）
    List<double>? pePercentileSeries,
    double pePercentileLimit = 0.0,
    List<double>? pbPercentileSeries,
    double pbPercentileLimit = 0.0,
    // 费率参数化：短持惩罚天数与惩罚费率（默认对齐 C 类 <7 天 1.5%），以及申购费
    int shortHoldDays = 7,
    double shortHoldPenaltyPct = 1.5,
    double purchaseFeePct = 0.0,
  }) {
    final int n = allNavs.length;
    if (n <= buyDays) {
      return BacktestResult(
        winRate: 0.0,
        avgProfit: 0.0,
        totalTrades: 0,
        isRobust: false,
        trades: [],
        maxDrawdown: 0.0,
        calmarRatio: 0.0,
        annualizedReturn: 0.0,
        equityCurve: List<double>.filled(n, 1.0),
        annualizedVolatility: 0.0,
        sharpeRatio: 0.0,
        sortinoRatio: 0.0,
        maxDrawdownDuration: 0,
        avgEfficiency: 0.0,
      );
    }

    final double buyDrop = buyDropPct / 100.0;
    final double targetProfit = targetProfitPct / 100.0;

    // 0. 获取或计算特定周期的简单移动平均线 (向后兼容：如果 useMaFilter 为真且 maPeriod 为0，默认为 120日均线)
    int effectiveMaPeriod = maPeriod;
    if (useMaFilter && effectiveMaPeriod == 0) {
      effectiveMaPeriod = 120;
    }

    final List<double> ma;
    if (effectiveMaPeriod > 0) {
      if (precalculatedMa != null && precalculatedMa.length == n) {
        ma = precalculatedMa;
      } else {
        ma = List<double>.filled(n, 0.0);
        double sum = 0.0;
        for (int i = 0; i < n; i++) {
          sum += allNavs[i];
          if (i >= effectiveMaPeriod) {
            sum -= allNavs[i - effectiveMaPeriod];
            ma[i] = sum / effectiveMaPeriod;
          } else {
            ma[i] = sum / (i + 1);
          }
        }
      }
    } else {
      ma = [];
    }

    // 0.2 趋势 regime 长期均线（用于判断长期上/下行，避免在单边下跌中持续接飞刀）
    final List<double> regimeMa;
    if (regimeMaPeriod > 0) {
      regimeMa = List<double>.filled(n, 0.0);
      double rsum = 0.0;
      for (int i = 0; i < n; i++) {
        rsum += allNavs[i];
        if (i >= regimeMaPeriod) {
          rsum -= allNavs[i - regimeMaPeriod];
          regimeMa[i] = rsum / regimeMaPeriod;
        } else {
          regimeMa[i] = rsum / (i + 1);
        }
      }
    } else {
      regimeMa = [];
    }
    // regime 斜率回看窗口
    final int regimeSlopeLookback =
        regimeMaPeriod > 0 ? math.min(20, regimeMaPeriod) : 0;

    // 1. 使用单调递减双端队列 O(n) 计算滑动窗口最大值
    // rollingMax[i] = i 及其之前 buyDays 个交易日内的最高单位净值
    final List<double> rollingMax = List<double>.filled(n, 0.0);
    final deque = Queue<int>(); // 存储索引，队首始终为窗口内最大值的位置
    for (int i = 0; i < n; i++) {
      // 移出超出窗口范围的队首
      while (deque.isNotEmpty && deque.first < i - buyDays + 1) {
        deque.removeFirst();
      }
      // 维护单调递减：从队尾移出所有小于当前值的索引
      while (deque.isNotEmpty && allNavs[deque.last] <= allNavs[i]) {
        deque.removeLast();
      }
      deque.addLast(i);
      rollingMax[i] = allNavs[deque.first];
    }

    // 2. 标记买入触发点 (修正边界处理，数据不足时不发生交易)
    final List<bool> triggerMask = List<bool>.filled(n, false);
    final int startIdx = math.max(buyDays, effectiveMaPeriod);

    // 技术指标预计算
    final List<double> rsi =
        (rsiFilterLimit > 0.0) ? calculateRSI(allNavs) : [];
    final List<bool> macdOk = useMacdFilter ? calculateMACD(allNavs) : [];

    for (int i = startIdx; i < n; i++) {
      // 过滤：RSI 条件判定
      if (rsiFilterLimit > 0.0 && rsi.length > i && rsi[i] >= rsiFilterLimit) {
        continue;
      }
      // 过滤：MACD 金叉翻红判定
      if (useMacdFilter && macdOk.length > i && !macdOk[i]) {
        continue;
      }
      // 过滤：趋势 regime 判定，长期均线下行（确认下降趋势）时不接飞刀
      if (regimeMaPeriod > 0 &&
          i >= regimeSlopeLookback &&
          regimeMa[i] < regimeMa[i - regimeSlopeLookback]) {
        continue;
      }
      // 过滤：估值百分位上限（历史序列可得时才生效，否则 no-op）
      if (pePercentileLimit > 0.0 &&
          pePercentileSeries != null &&
          pePercentileSeries.length > i &&
          pePercentileSeries[i] > pePercentileLimit) {
        continue;
      }
      if (pbPercentileLimit > 0.0 &&
          pbPercentileSeries != null &&
          pbPercentileSeries.length > i &&
          pbPercentileSeries[i] > pbPercentileLimit) {
        continue;
      }

      final double peak = rollingMax[i - 1]; // 过去 N 天的最高净值（不含当天）
      if (peak > 0.0) {
        final double drop = (allNavs[i] - peak) / peak;
        if (drop <= -buyDrop) {
          if (effectiveMaPeriod > 0) {
            // 1. 动态自适应均线周期计算
            int adaptiveMaPeriod = effectiveMaPeriod;
            if (i > 40) {
              final double volShort =
                  (precalculatedVol10 != null && precalculatedVol10.length > i)
                      ? precalculatedVol10[i]
                      : _calculateVolatilityBacktest(i, 10, allNavs);
              final double volLong =
                  (precalculatedVol60 != null && precalculatedVol60.length > i)
                      ? precalculatedVol60[i]
                      : _calculateVolatilityBacktest(i, 60, allNavs);
              if (volLong > 0.0) {
                double ratio = volShort / volLong;
                ratio = ratio.clamp(0.5, 2.0);
                adaptiveMaPeriod = (effectiveMaPeriod / ratio).round();
                final int minP = math.max(5, (effectiveMaPeriod / 3).round());
                final int maxP = (effectiveMaPeriod * 2).round();
                adaptiveMaPeriod = adaptiveMaPeriod.clamp(minP, maxP);
              }
            }

            // 计算第 i 天的自适应均线值（往前数 adaptiveMaPeriod 天，包含第 i 天）
            // 暖机期修正：自适应周期超过可用历史时，回退到已完整可用的基准周期，
            // 避免用不足窗口的偏差均线导致过滤失真
            int usableMaPeriod = adaptiveMaPeriod;
            if (i + 1 < adaptiveMaPeriod) {
              usableMaPeriod = effectiveMaPeriod;
            }
            double sum = 0.0;
            int count = 0;
            for (int k = i - usableMaPeriod + 1; k <= i; k++) {
              if (k >= 0) {
                sum += allNavs[k];
                count++;
              }
            }
            final double targetMa = count > 0 ? sum / count : allNavs[i];

            // 2. 均线过滤：双向偏离度控制，限制高于均线太多，防止高位接飞刀
            final double limitPriceLower =
                targetMa * (1.0 - maEnvelopePct / 100.0);
            final double upperEnvelope = math.max(2.0, maEnvelopePct);
            final double limitPriceUpper =
                targetMa * (1.0 + upperEnvelope / 100.0);
            if (allNavs[i] >= limitPriceLower &&
                allNavs[i] <= limitPriceUpper) {
              triggerMask[i] = true;
            }
          } else {
            triggerMask[i] = true;
          }
        }
      }
    }

    // 3. 交易回测逻辑（支持多仓位管理并行交易）
    final List<Map<String, dynamic>> trades = [];
    final List<double> equityCurve = List<double>.filled(n, 1.0);

    // 初始化多仓位槽位管理
    final List<_PositionSlot> slots = List.generate(
      maxConcurrentTrades,
      (_) => _PositionSlot(),
    );
    double cash = 1.0;
    double? lastBuyPrice;
    // T+n 在途赎回资金队列：到账日 -> 金额（settlementDays=0 时始终为空，保持旧行为）
    final Map<int, double> pendingCashByDay = {};
    // 组合级回撤熔断用的权益峰值
    double runningEquityPeak = 1.0;

    for (int i = 0; i < n; i++) {
      // 释放到期的在途赎回资金
      if (settlementDays > 0 && pendingCashByDay.isNotEmpty) {
        final List<int> matured =
            pendingCashByDay.keys.where((d) => d <= i).toList();
        for (final d in matured) {
          cash += pendingCashByDay.remove(d)!;
        }
      }

      // A. 处理平仓判断
      for (final slot in slots) {
        if (slot.isHolding) {
          final int holdDays = i - slot.buyIdx;
          final double currentNav = allNavs[i];
          if (currentNav > slot.maxHoldNav) {
            slot.maxHoldNav = currentNav;
          }

          final double profit = (currentNav - slot.buyNav) / slot.buyNav;

          // I. 追踪止盈平仓判断 (设定激活门槛，默认需要达到 trailingDropPct 的收益)
          bool isTrailingStopTriggered = false;
          if (trailingDropPct != null && slot.maxHoldNav > 0.0) {
            final double maxProfitSoFar =
                (slot.maxHoldNav - slot.buyNav) / slot.buyNav;
            final double activateThreshold =
                (trailingActivatePct ?? trailingDropPct) / 100.0;
            if (maxProfitSoFar >= activateThreshold) {
              final double dropFromPeak =
                  (currentNav - slot.maxHoldNav) / slot.maxHoldNav;
              if (dropFromPeak <= -trailingDropPct / 100.0) {
                isTrailingStopTriggered = true;
              }
            }
          }

          // II. 融合卖出信号平仓判断 (限制基准日最远只能回溯到买入日)
          bool isSellSignalTriggered = false;
          if (sellX != null && sellPct != null) {
            final int baseIdx = math.max(slot.buyIdx, i - sellX);
            final double baseNav = allNavs[baseIdx];
            if (baseNav > 0.0) {
              final double riseSinceX = (currentNav - baseNav) / baseNav;
              if (riseSinceX >= sellPct / 100.0) {
                isSellSignalTriggered = true;
              }
            }
          }

          // III. 固定目标止盈平仓判断 (持有期少于 shortHoldDays 天包含惩罚费率)
          final double shortHoldPenalty = shortHoldPenaltyPct / 100.0;
          final double requiredProfit = (holdDays < shortHoldDays)
              ? (targetProfit + shortHoldPenalty)
              : targetProfit;
          final bool isTargetProfitTriggered = profit >= requiredProfit;

          // IV. 到期平仓判断
          final bool isExpired = holdDays >= holdMax;

          // V. 单笔硬止损平仓判断（stopLossPct>0 时生效，默认关闭）
          final bool isStopLossTriggered =
              stopLossPct > 0.0 && profit <= -stopLossPct / 100.0;

          // 平仓决策
          final bool shouldSell = isTargetProfitTriggered ||
              isTrailingStopTriggered ||
              isSellSignalTriggered ||
              isStopLossTriggered ||
              isExpired ||
              (i == n - 1); // 最后一天强平

          if (shouldSell) {
            final double sellNav = currentNav;
            double finalProfit = (sellNav - slot.buyNav) / slot.buyNav;
            if (holdDays < shortHoldDays) {
              finalProfit -= shortHoldPenalty;
            }
            finalProfit -= slippagePct / 100.0;
            finalProfit -= purchaseFeePct / 100.0;

            final double returnCash = slot.buyBalance * (1.0 + finalProfit);
            if (settlementDays > 0) {
              // T+n 赎回：资金进入在途队列，到账日后方可再投资
              final int availDay = i + settlementDays;
              pendingCashByDay[availDay] =
                  (pendingCashByDay[availDay] ?? 0.0) + returnCash;
            } else {
              cash += returnCash;
            }
            slot.balance = 0.0;
            slot.isHolding = false;

            double maxFutureNav = slot.buyNav;
            final int endSearch = math.min(n, slot.buyIdx + holdMax);
            for (int k = slot.buyIdx; k < endSearch; k++) {
              if (allNavs[k] > maxFutureNav) {
                maxFutureNav = allNavs[k];
              }
            }
            final double maxPotential =
                (maxFutureNav - slot.buyNav) / slot.buyNav -
                    slippagePct / 100.0;

            trades.add({
              'success': finalProfit > 0.0,
              'profit': finalProfit,
              'buy_idx': slot.buyIdx,
              'buy_date': allDates[slot.buyIdx],
              'buy_nav': slot.buyNav,
              'sell_idx': i,
              'sell_date': allDates[i],
              'sell_nav': sellNav,
              'hold_days': holdDays == 0 ? 1 : holdDays,
              'max_potential': maxPotential,
            });
          }
        }
      }

      // B. 处理新开仓判断 (限制最后一天不开新仓)
      bool anyHolding = false;
      for (final slot in slots) {
        if (slot.isHolding) {
          anyHolding = true;
          break;
        }
      }
      if (!anyHolding) {
        lastBuyPrice = null;
      }

      // 组合级回撤熔断：当前权益自峰值回撤超过阈值时暂停开新仓（默认关闭）
      bool circuitBreakerActive = false;
      if (portfolioMaxDrawdownStop > 0.0 && runningEquityPeak > 0.0) {
        double provEquity = cash;
        for (final v in pendingCashByDay.values) {
          provEquity += v;
        }
        for (final s in slots) {
          if (s.isHolding) {
            provEquity += s.buyBalance * (allNavs[i] / s.buyNav);
          }
        }
        final double curDd =
            (runningEquityPeak - provEquity) / runningEquityPeak;
        if (curDd >= portfolioMaxDrawdownStop / 100.0) {
          circuitBreakerActive = true;
        }
      }

      if (triggerMask[i] && i < n - 1 && !circuitBreakerActive) {
        if (gridSpacingPct > 0.0 && lastBuyPrice != null) {
          final double dropFromLast =
              (allNavs[i] - lastBuyPrice) / lastBuyPrice;
          if (dropFromLast > -gridSpacingPct / 100.0) {
            continue; // 跌幅不够，跳过本次开仓
          }
        }

        _PositionSlot? freeSlot;
        for (final slot in slots) {
          if (!slot.isHolding) {
            freeSlot = slot;
            break;
          }
        }

        if (freeSlot != null) {
          // 计算静态总资产：现金 + 已持仓位的买入本金（排除浮动盈亏的干扰，避免高位重仓、低位轻仓的反向选择）
          double staticTotalEquity = cash;
          for (final s in slots) {
            if (s.isHolding) {
              staticTotalEquity += s.buyBalance;
            }
          }

          double allocate = staticTotalEquity / maxConcurrentTrades;

          // 尾余仓位保护：如果现金不足分配额度的 90%，为了防止仓位过小导致平摊风险失效，直接放弃本次开仓
          if (cash < allocate * 0.9) {
            allocate = 0.0;
          } else if (allocate > cash) {
            allocate = cash;
          }

          if (allocate > 0.000001) {
            cash -= allocate;
            freeSlot.isHolding = true;
            freeSlot.buyIdx = i;
            freeSlot.buyNav = allNavs[i];
            freeSlot.maxHoldNav = allNavs[i];
            freeSlot.buyBalance = allocate;

            // 更新最近开仓价
            lastBuyPrice = allNavs[i];
          }
        }
      }

      // C. 动态更新当前所有槽位市值和累计总资产
      double dailyTotalEquity = cash;
      for (final v in pendingCashByDay.values) {
        dailyTotalEquity += v; // 在途赎回资金仍计入组合权益
      }
      for (final slot in slots) {
        if (slot.isHolding) {
          slot.balance = slot.buyBalance * (allNavs[i] / slot.buyNav);
          dailyTotalEquity += slot.balance;
        } else {
          slot.balance = 0.0;
        }
      }
      equityCurve[i] = dailyTotalEquity;
      if (dailyTotalEquity > runningEquityPeak) {
        runningEquityPeak = dailyTotalEquity;
      }
    }

    final int totalTrades = trades.length;
    if (totalTrades == 0) {
      return BacktestResult(
        winRate: 0.0,
        avgProfit: 0.0,
        totalTrades: 0,
        isRobust: false,
        trades: [],
        maxDrawdown: 0.0,
        calmarRatio: 0.0,
        annualizedReturn: 0.0,
        equityCurve: List<double>.filled(n, 1.0),
        annualizedVolatility: 0.0,
        sharpeRatio: 0.0,
        sortinoRatio: 0.0,
        maxDrawdownDuration: 0,
        avgEfficiency: 0.0,
      );
    }

    int winCount = 0;
    double profitSum = 0.0;
    double efficiencySum = 0.0;
    int validEfficiencyCount = 0;

    for (final t in trades) {
      if (t['success'] == true) winCount++;
      profitSum += (t['profit'] as double);

      final double maxPot = t['max_potential'] as double;
      if (maxPot > 0.0) {
        final double act = t['profit'] as double;
        final double eff = (act / maxPot).clamp(0.0, 1.0);
        efficiencySum += eff;
        validEfficiencyCount++;
      }
    }

    final double winRate = (winCount / totalTrades) * 100.0;
    final double avgProfit = (profitSum / totalTrades) * 100.0;
    final double avgEfficiency = validEfficiencyCount > 0
        ? (efficiencySum / validEfficiencyCount) * 100.0
        : 0.0;
    final bool isRobust = totalTrades >= 5;

    // 计算最大回撤 (Max Drawdown)
    double maxEquity = 1.0;
    double maxDd = 0.0;
    for (int t = 0; t < n; t++) {
      final double eq = equityCurve[t];
      if (eq > maxEquity) {
        maxEquity = eq;
      } else if (maxEquity > 0) {
        final double dd = (maxEquity - eq) / maxEquity;
        if (dd > maxDd) {
          maxDd = dd;
        }
      }
    }

    // 计算年化收益率 (Annualized Return)
    final double finalEquity = equityCurve[n - 1];
    double annualizedReturn = 0.0;
    if (n > 0 && finalEquity > 0) {
      annualizedReturn = math.pow(finalEquity, 250.0 / n) - 1.0;
    } else if (finalEquity <= 0) {
      annualizedReturn = -0.9999;
    }

    // 计算卡玛比率 (Calmar Ratio)
    final double maxDrawdown = maxDd;
    final double calmarRatio = maxDrawdown > 0.0001
        ? annualizedReturn / maxDrawdown
        : annualizedReturn / 0.0001;

    // 计算波动率与风险评估指标 (夏普、索提诺、最大套牢期)
    double volDaily = 0.0;
    double downsideVolDaily = 0.0;
    if (n > 1) {
      final List<double> dailyReturns = List<double>.filled(n - 1, 0.0);
      double returnSum = 0.0;
      for (int t = 1; t < n; t++) {
        final double prev = equityCurve[t - 1];
        dailyReturns[t - 1] = prev > 0.0 ? (equityCurve[t] - prev) / prev : 0.0;
        returnSum += dailyReturns[t - 1];
      }
      final double meanReturn = returnSum / (n - 1);

      double sumOfSquares = 0.0;
      double sumOfDownsideSquares = 0.0;
      for (int t = 0; t < n - 1; t++) {
        final double diff = dailyReturns[t] - meanReturn;
        sumOfSquares += diff * diff;
        if (dailyReturns[t] < 0.0) {
          sumOfDownsideSquares += dailyReturns[t] * dailyReturns[t];
        }
      }
      volDaily = math.sqrt(sumOfSquares / (n - 1));
      downsideVolDaily = math.sqrt(sumOfDownsideSquares / (n - 1));
    }

    final double annualizedVolatility = volDaily * math.sqrt(250.0);
    final double downsideVolatility = downsideVolDaily * math.sqrt(250.0);

    // 假设无风险年化收益为 2% (0.02)
    final double sharpeRatio = annualizedVolatility > 0.0001
        ? (annualizedReturn - 0.02) / annualizedVolatility
        : 0.0;

    final double sortinoRatio = downsideVolatility > 0.0001
        ? (annualizedReturn - 0.02) / downsideVolatility
        : 0.0;

    // 计算最大回撤持续天数 (Max Drawdown Duration / 最大套牢期)
    int maxDdDuration = 0;
    double peak = equityCurve[0];
    int peakIdx = 0;
    for (int t = 0; t < n; t++) {
      if (equityCurve[t] >= peak) {
        peak = equityCurve[t];
        peakIdx = t;
      } else {
        final int duration = t - peakIdx;
        if (duration > maxDdDuration) {
          maxDdDuration = duration;
        }
      }
    }

    return BacktestResult(
      winRate: winRate,
      avgProfit: avgProfit,
      totalTrades: totalTrades,
      isRobust: isRobust,
      trades: trades,
      maxDrawdown: maxDrawdown,
      calmarRatio: calmarRatio,
      annualizedReturn: annualizedReturn,
      equityCurve: equityCurve,
      annualizedVolatility: annualizedVolatility,
      sharpeRatio: sharpeRatio,
      sortinoRatio: sortinoRatio,
      maxDrawdownDuration: maxDdDuration,
      avgEfficiency: avgEfficiency,
    );
  }
}

class _PositionSlot {
  bool isHolding = false;
  int buyIdx = 0;
  double buyNav = 0.0;
  double maxHoldNav = 0.0;
  double buyBalance = 0.0;
  double balance = 0.0;
}
