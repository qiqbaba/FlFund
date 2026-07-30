import 'dart:math';
import 'backtest_engine.dart';

class DataSplit {
  final List<double> inSampleNavs;
  final List<String> inSampleDates;
  final List<double> outSampleNavs;
  final List<String> outSampleDates;
  final bool hasOutSample;

  DataSplit({
    required this.inSampleNavs,
    required this.inSampleDates,
    required this.outSampleNavs,
    required this.outSampleDates,
    required this.hasOutSample,
  });
}

DataSplit _splitData(List<double> navs, List<String> dates) {
  final int n = navs.length;
  // 只有在数据长度 >= 100 天时才切分样本外，否则全部作为样本内
  if (n >= 100) {
    final int splitIdx = (n * 0.7).floor();
    return DataSplit(
      inSampleNavs: navs.sublist(0, splitIdx),
      inSampleDates: dates.sublist(0, splitIdx),
      outSampleNavs: navs.sublist(splitIdx),
      outSampleDates: dates.sublist(splitIdx),
      hasOutSample: true,
    );
  } else {
    return DataSplit(
      inSampleNavs: navs,
      inSampleDates: dates,
      outSampleNavs: [],
      outSampleDates: [],
      hasOutSample: false,
    );
  }
}

// 用于表示遗传算法的适应度（支持多维度优先比较）
class GAFitness implements Comparable<GAFitness> {
  final int isRobust; // 1: 足够稳健(交易数>=5且分布均匀), 0: 交易数<5且>0, -2: 交易数为0
  final double calmarScore; // 综合卡玛比率得分 (样本内 * 0.7 + 样本外 * 0.3)
  final double winRate; // 样本内胜率作为备用比对
  final int totalTrades;
  final double buyDrop;

  GAFitness({
    required this.isRobust,
    required this.calmarScore,
    required this.winRate,
    required this.totalTrades,
    required this.buyDrop,
  });

  @override
  int compareTo(GAFitness other) {
    // 1. 优先比较稳健性
    if (isRobust != other.isRobust) {
      return isRobust.compareTo(other.isRobust);
    }
    // 2. 其次比较综合得分：卡玛评分（带有 buyDrop 安全边际奖励）
    final double score = calmarScore >= 0
        ? calmarScore * (1.0 + buyDrop / 100.0)
        : calmarScore / (1.0 + buyDrop / 100.0);
    final double otherScore = other.calmarScore >= 0
        ? other.calmarScore * (1.0 + other.buyDrop / 100.0)
        : other.calmarScore / (1.0 + other.buyDrop / 100.0);
    if (score != otherScore) {
      return score.compareTo(otherScore);
    }
    // 3. 再次比较胜率
    if (winRate != other.winRate) {
      return winRate.compareTo(other.winRate);
    }
    // 4. 最后比较交易次数
    return totalTrades.compareTo(other.totalTrades);
  }

  bool get isValid => isRobust > -2;
}

// 染色体个体
class Individual {
  int buyDays;
  double buyDrop;
  double targetProfit;
  int maPeriod;
  double maEnvelopePct;
  GAFitness? fitness;
  double winRate = 0.0;
  double avgProfit = 0.0;
  int totalTrades = 0;

  Individual(this.buyDays, this.buyDrop, this.targetProfit, {this.maPeriod = 0, this.maEnvelopePct = 0.0});

  Individual clone() {
    return Individual(buyDays, buyDrop, targetProfit, maPeriod: maPeriod, maEnvelopePct: maEnvelopePct)
      ..fitness = fitness
      ..winRate = winRate
      ..avgProfit = avgProfit
      ..totalTrades = totalTrades;
  }
}

bool _isStablePlateau(
  Individual ind,
  List<double> navs,
  List<String> dates,
  int holdMax,
  double baseCalmar,
  double minBuyDrop,
  double? trailingDropPct,
  int? sellX,
  double? sellPct,
  List<double>? precalculatedMa,
  int minBuyDays,
  int maxBuyDays,
  double slippagePct,
  double rsiFilterLimit,
  bool useMacdFilter, {
  Map<int, List<double>>? fullMaMap,
  List<double>? precalculatedVol10,
  List<double>? precalculatedVol60,
}) {
  if (baseCalmar <= 0) return true; // 如果原本就未盈利，无需进行高原验证

  // 扩充邻域扰动：同时对 buyDays、buyDrop、targetProfit 三个维度进行敏感性验证
  final neighbors = [
    Individual((ind.buyDays + 2).clamp(minBuyDays, maxBuyDays), ind.buyDrop, ind.targetProfit, maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
    Individual((ind.buyDays - 2).clamp(minBuyDays, maxBuyDays), ind.buyDrop, ind.targetProfit, maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
    Individual(ind.buyDays, (ind.buyDrop + 1.0).clamp(minBuyDrop, 25.0), ind.targetProfit, maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
    Individual(ind.buyDays, (ind.buyDrop - 1.0).clamp(minBuyDrop, 25.0), ind.targetProfit, maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
    // 修复：新增 targetProfit 维度扰动，止止利水准对 Calmar 比率同样敏感的参数被漏验
    Individual(ind.buyDays, ind.buyDrop, (ind.targetProfit + 1.0).clamp(0.5, 25.0), maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
    Individual(ind.buyDays, ind.buyDrop, (ind.targetProfit - 1.0).clamp(0.5, 25.0), maPeriod: ind.maPeriod, maEnvelopePct: ind.maEnvelopePct),
  ];

  double neighborCalmarSum = 0.0;
  int count = 0;
  final int totalNeighbors = neighbors.length;

  for (int i = 0; i < totalNeighbors; i++) {
    final n = neighbors[i];
    // 若扰动后的邻域个体参数未发生实际改变（如触及边界），直接复用基准 Calmar
    if (n.buyDays == ind.buyDays &&
        n.buyDrop == ind.buyDrop &&
        n.targetProfit == ind.targetProfit) {
      neighborCalmarSum += baseCalmar;
      count++;
      continue;
    }

    final res = BacktestEngine.runBacktest(
      allNavs: navs,
      allDates: dates,
      buyDays: n.buyDays,
      buyDropPct: n.buyDrop,
      targetProfitPct: n.targetProfit,
      holdMax: holdMax,
      maPeriod: n.maPeriod,
      maEnvelopePct: n.maEnvelopePct,
      trailingDropPct: trailingDropPct,
      sellX: sellX,
      sellPct: sellPct,
      precalculatedMa: fullMaMap != null ? fullMaMap[n.maPeriod] : precalculatedMa,
      precalculatedVol10: precalculatedVol10,
      precalculatedVol60: precalculatedVol60,
      slippagePct: slippagePct,
      rsiFilterLimit: rsiFilterLimit,
      useMacdFilter: useMacdFilter,
    );
    if (res.totalTrades > 0) {
      neighborCalmarSum += res.calmarRatio;
    } else {
      neighborCalmarSum += -1.0; // 零交易视为极差的表现
    }
    count++;

    // 提前剪枝：即使剩余未测试的邻域全部取得 Perfect 得分 (baseCalmar)，也无法达到 baseCalmar * 0.5 时，立即退出
    final double maxRemainingScore = (totalNeighbors - count) * baseCalmar;
    if ((neighborCalmarSum + maxRemainingScore) / totalNeighbors < baseCalmar * 0.5) {
      return false;
    }
  }

  final double avgNeighborCalmar = neighborCalmarSum / totalNeighbors;
  // 若扰动后的平均卡玛比率比最优解下降超过 50%，视为不稳定噪点
  if (avgNeighborCalmar < baseCalmar * 0.5) {
    return false;
  }
  return true;
}

class GAOptimizer {
  // 运行寻优主流程
  static Map<String, dynamic>? optimize({
    required List<double> allNavs,
    required List<String> allDates,
    void Function(int current, int total)? onProgress,
    bool useMaFilter = false,
    double? trailingDropPct,
    int? sellX,
    double? sellPct,
    double lowThreshold = 15.0,
    double highThreshold = 48.0,
    double rsiFilterLimit = 35.0,
    bool useMacdFilter = true,
  }) {
    if (allNavs.length < 20) return null;

    final dataSplit = _splitData(allNavs, allDates);
    final int splitIdx = (allNavs.length >= 100) ? (allNavs.length * 0.7).floor() : allNavs.length;

    // 0. 预先计算滚动波动率缓存与切片
    final List<double> fullVol10 = BacktestEngine.precalculateVolatility(allNavs, 10);
    final List<double> fullVol60 = BacktestEngine.precalculateVolatility(allNavs, 60);

    final List<double> inSampleVol10 = fullVol10.sublist(0, splitIdx);
    final List<double> inSampleVol60 = fullVol60.sublist(0, splitIdx);
    final List<double> outSampleVol10 = allNavs.length >= 100 ? fullVol10.sublist(splitIdx) : [];
    final List<double> outSampleVol60 = allNavs.length >= 100 ? fullVol60.sublist(splitIdx) : [];

    // 0.1 预计算多周期简单移动平均线缓存以提高效率
    final Map<int, List<double>> fullMaMap = {};
    final Map<int, List<double>> inSampleMaMap = {};
    final Map<int, List<double>> outSampleMaMap = {};
    
    for (final period in [20, 60, 120, 250]) {
      final ma = _precalculateMA(allNavs, period);
      fullMaMap[period] = ma;
      inSampleMaMap[period] = ma.sublist(0, splitIdx);
      if (allNavs.length >= 100) {
        outSampleMaMap[period] = ma.sublist(splitIdx);
      }
    }

    // 1. 计算历史最大回撤、最高净值与最低净值
    double maxNav = allNavs.first;
    double minNav = allNavs.first;
    double maxDd = 0.0;
    for (final nav in allNavs) {
      if (nav > maxNav) {
        maxNav = nav;
      }
      if (nav < minNav) {
        minNav = nav;
      }
      if (maxNav > 0) {
        final dd = (maxNav - nav) / maxNav;
        if (dd > maxDd) {
          maxDd = dd;
        }
      }
    }
    // 2. 动态计算最小买入下跌阈值：历史最大回撤的 20%，限制在 [0.5%, 5.0%]
    // 以此过滤并限制低买入下跌（如 0.69%）的低质量噪声买入策略
    final double minBuyDrop = (maxDd * 100.0 * 0.20).clamp(0.5, 5.0);

    // 2.1 统一时间窗口为最近 500 个交易日计算波动评分
    const int limit = 500;
    final List<double> navs = allNavs.length > limit
        ? allNavs.sublist(allNavs.length - limit)
        : allNavs;

    double volDaily = 0.0;
    final int totalDays = navs.length;
    if (totalDays > 1) {
      final List<double> dailyReturns = List<double>.filled(totalDays - 1, 0.0);
      double returnSum = 0.0;
      for (int t = 1; t < totalDays; t++) {
        final double prev = navs[t - 1];
        dailyReturns[t - 1] = prev > 0.0 ? (navs[t] - prev) / prev : 0.0;
        returnSum += dailyReturns[t - 1];
      }
      final double meanReturn = returnSum / (totalDays - 1);
      double sumOfSquares = 0.0;
      for (int t = 0; t < totalDays - 1; t++) {
        final double diff = dailyReturns[t] - meanReturn;
        sumOfSquares += diff * diff;
      }
      volDaily = sqrt(sumOfSquares / (totalDays - 1));
    }
    final double annVolatility = volDaily * sqrt(250.0);

    // 计算最近 250 天的最大回撤
    double maxDrawdown = 0.0;
    if (navs.isNotEmpty) {
      double peak = navs.first;
      for (final nav in navs) {
        if (nav > peak) {
          peak = nav;
        } else if (peak > 0.0) {
          final double drawdown = (peak - nav) / peak;
          if (drawdown > maxDrawdown) {
            maxDrawdown = drawdown;
          }
        }
      }
    }

    // 结合方案 2：计算波动综合得分 (年化波动基准 25%, 最大回撤基准 50%)
    // 不进行 clamp 限制，以与 recalibrateVolatilityThresholds 计算逻辑完全对齐
    final double sVol = (annVolatility / 0.25) * 100;
    final double sDrawdown = (maxDrawdown / 0.50) * 100;
    final double totalScore = sVol * 0.6 + sDrawdown * 0.4;

    // 结合方案 3：采用分位数分界线进行等级划分
    // - 低波动 (Low): totalScore < lowThreshold
    // - 中波动 (Medium): lowThreshold <= totalScore < highThreshold
    // - 高波动 (High): totalScore >= highThreshold
    // 若成立时间较短（如不足 250 个交易日，约 1 年），由于缺乏充足的数据样本，历史最大回撤和年化波动率极易失真。
    // 为了安全性原则（安全边际），避免高风险新基金被错误分类为“低波动基金”并赋予 120 天的超长持仓上限，
    // 强制判定其不为“低波动”（即在此过渡期内至少被评定为中波动或高波动）。
    final bool isTooShort = allNavs.length < 250;
    final bool isLowVol = !isTooShort && (totalScore < lowThreshold);
    final bool isHighVol = totalScore >= highThreshold;

    // 2.2 动态设置寻优和回测参数边界 (基于低、中、高波动等级)
    final int holdMax = isHighVol ? 30 : (isLowVol ? 120 : 75);
    final int minBuyDays = isHighVol ? 3 : (isLowVol ? 6 : 4);
    final int maxBuyDays = isHighVol ? 25 : (isLowVol ? 75 : 45);
    final double maxTargetProfit = isHighVol ? 25.0 : (isLowVol ? 8.0 : 18.0);
    final double slippagePct = isHighVol ? 0.6 : (isLowVol ? 0.2 : 0.4);

    const int popSize = 40;
    const int generations = 25;
    const double crossoverRate = 0.8;
    const double mutationRate = 0.2;
    const int elitismCount = 2;

    final random = Random();
    final Map<String, Map<String, dynamic>> memo = {};
    final List<int> maPeriodCandidates = [0, 20, 60, 120, 250];

    // 适应度评估函数
    void evaluate(Individual ind) {
      // 限制参数边界
      ind.buyDays = ind.buyDays.clamp(minBuyDays, maxBuyDays);
      ind.buyDrop = double.parse(ind.buyDrop.clamp(minBuyDrop, 25.0).toStringAsFixed(2));
      ind.targetProfit = double.parse(ind.targetProfit.clamp(0.5, maxTargetProfit).toStringAsFixed(2));

      final key = '${ind.buyDays}_${ind.buyDrop}_${ind.targetProfit}_${ind.maPeriod}_${ind.maEnvelopePct.toStringAsFixed(1)}';
      if (memo.containsKey(key)) {
        final cache = memo[key]!;
        ind.winRate = cache['win_rate'];
        ind.avgProfit = cache['avg_profit'];
        ind.totalTrades = cache['total_trades'];
        ind.fitness = cache['fitness'];
        return;
      }

      final inSampleRes = BacktestEngine.runBacktest(
        allNavs: dataSplit.inSampleNavs,
        allDates: dataSplit.inSampleDates,
        buyDays: ind.buyDays,
        buyDropPct: ind.buyDrop,
        targetProfitPct: ind.targetProfit,
        holdMax: holdMax,
        maPeriod: ind.maPeriod,
        maEnvelopePct: ind.maEnvelopePct,
        trailingDropPct: trailingDropPct,
        sellX: sellX,
        sellPct: sellPct,
        precalculatedMa: inSampleMaMap[ind.maPeriod],
        precalculatedVol10: inSampleVol10,
        precalculatedVol60: inSampleVol60,
        slippagePct: slippagePct,
        rsiFilterLimit: rsiFilterLimit,
        useMacdFilter: useMacdFilter,
        gridSpacingPct: (ind.buyDrop * 0.3).clamp(1.0, 5.0),
      );

      if (inSampleRes.totalTrades == 0) {
        ind.fitness = GAFitness(
          isRobust: -2,
          calmarScore: -9999.0,
          winRate: 0.0,
          totalTrades: 0,
          buyDrop: ind.buyDrop,
        );
        ind.winRate = 0.0;
        ind.avgProfit = 0.0;
        ind.totalTrades = 0;
      } else {
        double calmarScore = 0.0;
        int outTrades = 0;
        double avgEff = inSampleRes.avgEfficiency;

        // 整合 Calmar 评分与 Sortino 比率，作为更加科学的适应度分值 (各占一半)
        final double inScore = (inSampleRes.calmarRatio + inSampleRes.sortinoRatio) / 2.0;

        if (dataSplit.hasOutSample) {
          final outSampleRes = BacktestEngine.runBacktest(
            allNavs: dataSplit.outSampleNavs,
            allDates: dataSplit.outSampleDates,
            buyDays: ind.buyDays,
            buyDropPct: ind.buyDrop,
            targetProfitPct: ind.targetProfit,
            holdMax: holdMax,
            maPeriod: ind.maPeriod,
            maEnvelopePct: ind.maEnvelopePct,
            trailingDropPct: trailingDropPct,
            sellX: sellX,
            sellPct: sellPct,
            precalculatedMa: outSampleMaMap[ind.maPeriod],
            precalculatedVol10: outSampleVol10,
            precalculatedVol60: outSampleVol60,
            slippagePct: slippagePct,
            rsiFilterLimit: rsiFilterLimit,
            useMacdFilter: useMacdFilter,
            gridSpacingPct: (ind.buyDrop * 0.3).clamp(1.0, 5.0),
          );
          outTrades = outSampleRes.totalTrades;

          if (outSampleRes.totalTrades > 0) {
            final double outScore = (outSampleRes.calmarRatio + outSampleRes.sortinoRatio) / 2.0;
            calmarScore = inScore * 0.7 + outScore * 0.3;
            avgEff = inSampleRes.avgEfficiency * 0.7 + outSampleRes.avgEfficiency * 0.3;
            // 惩罚机制：如果样本外发生了亏损或样本外胜率相比样本内下降了 50% 以上
            if (outSampleRes.annualizedReturn < 0 || outSampleRes.winRate < inSampleRes.winRate * 0.5) {
              if (calmarScore >= 0) {
                calmarScore *= 0.2;
              } else {
                calmarScore /= 0.2;
              }
            }
          } else {
            // 样本外无交易降权
            if (inScore >= 0) {
              calmarScore = inScore * 0.5;
            } else {
              calmarScore = inScore / 0.5;
            }
          }
        } else {
          calmarScore = inScore;
        }

        // 将综合收益捕获效率乘入 calmarScore 中作为调节系数
        final double effMultiplier = 0.4 + 0.6 * (avgEff / 100.0);
        // 修复：统一改为乘法，保证正负分的惩罚力度对称一致
        calmarScore *= effMultiplier;

        // 鲁棒性判定：总交易数 >= 5。如果存在样本外，希望样本内外均有交易
        bool isRobust = (inSampleRes.totalTrades + outTrades) >= 5;
        if (dataSplit.hasOutSample && outTrades == 0) {
          isRobust = false;
        }

        ind.fitness = GAFitness(
          isRobust: isRobust ? 1 : 0,
          calmarScore: calmarScore,
          winRate: inSampleRes.winRate,
          totalTrades: inSampleRes.totalTrades + outTrades,
          buyDrop: ind.buyDrop,
        );

        ind.winRate = inSampleRes.winRate;
        ind.avgProfit = inSampleRes.avgProfit;
        ind.totalTrades = inSampleRes.totalTrades + outTrades;
      }

      memo[key] = {
        'win_rate': ind.winRate,
        'avg_profit': ind.avgProfit,
        'total_trades': ind.totalTrades,
        'fitness': ind.fitness,
      };
    }

    // 3. 初始化种群
    List<Individual> population = List.generate(popSize, (_) {
      final days = random.nextInt(maxBuyDays - minBuyDays + 1) + minBuyDays;
      final drop = random.nextDouble() * (25.0 - minBuyDrop) + minBuyDrop;
      final profit = random.nextDouble() * (maxTargetProfit - 0.5) + 0.5;
      
      int maPeriod = 0;
      double maEnvelopePct = 0.0;
      if (useMaFilter) {
        maPeriod = maPeriodCandidates[random.nextInt(maPeriodCandidates.length)];
        if (maPeriod > 0) {
          maEnvelopePct = random.nextInt(11).toDouble(); // 0.0 到 10.0
        }
      }
      return Individual(days, drop, profit, maPeriod: maPeriod, maEnvelopePct: maEnvelopePct);
    });

    Individual? bestOverall;
    int consecutiveNoImprovement = 0;
    double lastBestScore = -999999.0;

    // 4. 进化迭代
    for (int gen = 0; gen < generations; gen++) {
      // 评估所有个体
      for (final ind in population) {
        evaluate(ind);
      }

      // 按适应度降序排列
      population.sort((a, b) => b.fitness!.compareTo(a.fitness!));

      // 更新全局最优
      final currentBest = population.first;

      if (bestOverall != null) {
        final currentBestScore = currentBest.fitness!.calmarScore;
        if ((currentBestScore - lastBestScore).abs() < 1e-4) {
          consecutiveNoImprovement++;
        } else {
          consecutiveNoImprovement = 0;
        }
        lastBestScore = currentBestScore;
      } else {
        lastBestScore = currentBest.fitness!.calmarScore;
      }

      if (bestOverall == null || currentBest.fitness!.compareTo(bestOverall.fitness!) > 0) {
        bestOverall = currentBest.clone();
      }

      if (onProgress != null) {
        onProgress(gen + 1, generations);
      }

      // 如果连续 6 代最优解得分无明显提升，且已经探索了 10 代以上，则早停
      if (gen >= 10 && consecutiveNoImprovement >= 6) {
        break;
      }

      // 生成下一代
      final List<Individual> nextGen = [];

      // 精英保留
      for (int i = 0; i < elitismCount; i++) {
        nextGen.add(population[i].clone());
      }

      // 锦标赛选择（无放回抽样，防止同一个个体被重复抽中导致选择压力降低）
      Individual tournamentSelect() {
        final indices = List.generate(popSize, (i) => i)..shuffle(random);
        Individual best = population[indices[0]];
        if (population[indices[1]].fitness!.compareTo(best.fitness!) > 0) best = population[indices[1]];
        if (population[indices[2]].fitness!.compareTo(best.fitness!) > 0) best = population[indices[2]];
        return best;
      }

      while (nextGen.length < popSize) {
        final p1 = tournamentSelect();
        final p2 = tournamentSelect();

        Individual c1, c2;

        // 交叉
        if (random.nextDouble() < crossoverRate) {
          final c1Days = random.nextBool() ? p1.buyDays : p2.buyDays;
          final c2Days = random.nextBool() ? p1.buyDays : p2.buyDays;

          final gamma1 = random.nextDouble();
          final c1Drop = gamma1 * p1.buyDrop + (1 - gamma1) * p2.buyDrop;
          final c2Drop = (1 - gamma1) * p1.buyDrop + gamma1 * p2.buyDrop;

          final gamma2 = random.nextDouble();
          final c1Profit = gamma2 * p1.targetProfit + (1 - gamma2) * p2.targetProfit;
          final c2Profit = (1 - gamma2) * p1.targetProfit + gamma2 * p2.targetProfit;

          int c1MaPeriod = 0;
          int c2MaPeriod = 0;
          double c1MaEnvelope = 0.0;
          double c2MaEnvelope = 0.0;

          if (useMaFilter) {
            c1MaPeriod = random.nextBool() ? p1.maPeriod : p2.maPeriod;
            c2MaPeriod = random.nextBool() ? p1.maPeriod : p2.maPeriod;

            final gamma3 = random.nextDouble();
            c1MaEnvelope = c1MaPeriod > 0 ? (gamma3 * p1.maEnvelopePct + (1 - gamma3) * p2.maEnvelopePct).clamp(0.0, 10.0) : 0.0;
            c2MaEnvelope = c2MaPeriod > 0 ? ((1 - gamma3) * p1.maEnvelopePct + gamma3 * p2.maEnvelopePct).clamp(0.0, 10.0) : 0.0;
          }

          c1 = Individual(c1Days, c1Drop, c1Profit, maPeriod: c1MaPeriod, maEnvelopePct: double.parse(c1MaEnvelope.toStringAsFixed(1)));
          c2 = Individual(c2Days, c2Drop, c2Profit, maPeriod: c2MaPeriod, maEnvelopePct: double.parse(c2MaEnvelope.toStringAsFixed(1)));
        } else {
          c1 = p1.clone();
          c2 = p2.clone();
        }

        // 变异
        void mutate(Individual ind) {
          if (random.nextDouble() < mutationRate) {
            ind.buyDays += random.nextBool() ? (random.nextInt(4) + 1) : -(random.nextInt(4) + 1);
            ind.buyDays = ind.buyDays.clamp(minBuyDays, maxBuyDays);
          }
          if (random.nextDouble() < mutationRate) {
            ind.buyDrop += (random.nextDouble() - 0.5) * 5.0; // 调大变异步长以覆盖更宽的区间
            ind.buyDrop = double.parse(ind.buyDrop.clamp(minBuyDrop, 25.0).toStringAsFixed(2));
          }
          if (random.nextDouble() < mutationRate) {
            ind.targetProfit += (random.nextDouble() - 0.5) * 5.0;
            ind.targetProfit = double.parse(ind.targetProfit.clamp(0.5, maxTargetProfit).toStringAsFixed(2));
          }
          if (useMaFilter) {
            if (random.nextDouble() < mutationRate) {
              ind.maPeriod = maPeriodCandidates[random.nextInt(maPeriodCandidates.length)];
              if (ind.maPeriod == 0) {
                ind.maEnvelopePct = 0.0;
              }
            }
            if (ind.maPeriod > 0 && random.nextDouble() < mutationRate) {
              ind.maEnvelopePct += (random.nextDouble() - 0.5) * 4.0;
              ind.maEnvelopePct = double.parse(ind.maEnvelopePct.clamp(0.0, 10.0).toStringAsFixed(1));
            }
          }
        }

        mutate(c1);
        mutate(c2);

        nextGen.add(c1);
        if (nextGen.length < popSize) {
          nextGen.add(c2);
        }
      }

      population = nextGen;
    }

    // 5. 参数敏感性高原校验
    Individual finalBest = bestOverall ?? population.first;
    for (int i = 0; i < min(5, population.length); i++) {
      final cand = population[i];
      if (cand.fitness != null && cand.fitness!.isValid) {
        final fullRes = BacktestEngine.runBacktest(
          allNavs: allNavs,
          allDates: allDates,
          buyDays: cand.buyDays,
          buyDropPct: cand.buyDrop,
          targetProfitPct: cand.targetProfit,
          holdMax: holdMax,
          maPeriod: cand.maPeriod,
          maEnvelopePct: cand.maEnvelopePct,
          trailingDropPct: trailingDropPct,
          sellX: sellX,
          sellPct: sellPct,
          precalculatedMa: fullMaMap[cand.maPeriod],
          precalculatedVol10: fullVol10,
          precalculatedVol60: fullVol60,
          slippagePct: slippagePct,
          rsiFilterLimit: rsiFilterLimit,
          useMacdFilter: useMacdFilter,
        );
        if (_isStablePlateau(
          cand,
          allNavs,
          allDates,
          holdMax,
          fullRes.calmarRatio,
          minBuyDrop,
          trailingDropPct,
          sellX,
          sellPct,
          fullMaMap[cand.maPeriod],
          minBuyDays,
          maxBuyDays,
          slippagePct,
          rsiFilterLimit,
          useMacdFilter,
          fullMaMap: fullMaMap,
          precalculatedVol10: fullVol10,
          precalculatedVol60: fullVol60,
        )) {
          finalBest = cand;
          break;
        }
      }
    }

    // 全样本回测得出最终评估用于回传
    final finalRes = BacktestEngine.runBacktest(
      allNavs: allNavs,
      allDates: allDates,
      buyDays: finalBest.buyDays,
      buyDropPct: finalBest.buyDrop,
      targetProfitPct: finalBest.targetProfit,
      holdMax: holdMax,
      maPeriod: finalBest.maPeriod,
      maEnvelopePct: finalBest.maEnvelopePct,
      trailingDropPct: trailingDropPct,
      sellX: sellX,
      sellPct: sellPct,
      precalculatedMa: fullMaMap[finalBest.maPeriod],
      precalculatedVol10: fullVol10,
      precalculatedVol60: fullVol60,
      slippagePct: slippagePct,
      rsiFilterLimit: rsiFilterLimit,
      useMacdFilter: useMacdFilter,
    );

    if (finalRes.totalTrades > 0) {
      return {
        'buy_days': finalBest.buyDays,
        'buy_drop': finalBest.buyDrop,
        'target_profit': finalBest.targetProfit,
        'hold_min': 7,
        'hold_max': holdMax,
        'win_rate': finalRes.winRate,
        'total_trades': finalRes.totalTrades,
        'avg_profit': finalRes.avgProfit,
        'ma_period': finalBest.maPeriod,
        'ma_envelope_pct': finalBest.maEnvelopePct,
      };
    }

    return null;
  }

  static List<double> _precalculateMA(List<double> navs, int period) {
    if (period <= 0) return [];
    final List<double> ma = List<double>.filled(navs.length, 0.0);
    double sum = 0.0;
    for (int i = 0; i < navs.length; i++) {
      sum += navs[i];
      if (i >= period) {
        sum -= navs[i - period];
        ma[i] = sum / period;
      } else {
        ma[i] = sum / (i + 1);
      }
    }
    return ma;
  }
}

Map<String, dynamic> _calcSellStats(List<double> navs, List<String> dates, int sellX, double sellPct) {
  int totalSignals = 0;
  int successSignals = 0;
  for (int i = sellX; i < navs.length - 15; i++) {
    final double baseNav = navs[i - sellX];
    if (baseNav <= 0) continue;
    final double risePct = ((navs[i] - baseNav) / baseNav) * 100.0;
    if (risePct >= sellPct) {
      totalSignals++;
      bool hasDrop = false;
      bool hasMissedRally = false;
      final double signalNav = navs[i];
      for (int j = 1; j <= 15; j++) {
        final double followNav = navs[i + j];
        if (signalNav > 0) {
          final double pct = ((followNav - signalNav) / signalNav) * 100.0;
          if (pct >= 5.0) {
            hasMissedRally = true;
            break;
          }
          if (pct <= -2.5) {
            hasDrop = true;
            break;
          }
        }
      }
      if (hasDrop && !hasMissedRally) successSignals++;
      i += 14; // 去重（因循环头自带 i++，此处增加 14 使得下一轮迭代 i 实际递增 15）
    }
  }
  final double winRate = totalSignals > 0 ? (successSignals / totalSignals) * 100.0 : 0.0;
  return {'winRate': winRate, 'trades': totalSignals};
}

// 卖出信号参数寻优器 (基于穷举法计算在x天内涨p%后随后的10天内跌幅大于2%的概率)
class SellSignalOptimizer {
  static Map<String, dynamic>? optimize({
    required List<double> allNavs, // 从远到近排列
    required List<String> allDates, // 从远到近排列
  }) {
    if (allNavs.length < 30) return null;

    int bestX = -1;
    double bestPct = -1.0;
    double bestScore = -1.0;
    int bestTrades = 0;

    final dataSplit = _splitData(allNavs, allDates);

    // 穷举 sellX 从 3 到 20 天，sellPct 从 2.0 到 15.0%，步长 1.0%
    for (int sellX = 3; sellX <= 20; sellX++) {
      for (double sellPct = 2.0; sellPct <= 15.0; sellPct += 1.0) {
        final inStats = _calcSellStats(dataSplit.inSampleNavs, dataSplit.inSampleDates, sellX, sellPct);
        final int inTrades = inStats['trades'] as int;
        final double inWinRate = inStats['winRate'] as double;

        if (inTrades < 3) continue; // 样本内必须至少有 3 次触发以保证统计显著

        double score = 0.0;
        int outTrades = 0;

        if (dataSplit.hasOutSample) {
          final outStats = _calcSellStats(dataSplit.outSampleNavs, dataSplit.outSampleDates, sellX, sellPct);
          final double outWinRate = outStats['winRate'] as double;
          outTrades = outStats['trades'] as int;

          // 样本内外加权胜率。如果样本外完全没有交易，进行适当扣分
          score = inWinRate * 0.7 + outWinRate * 0.3;
          if (outTrades == 0) {
            score *= 0.5; // 惩罚样本外零交易的过拟合参数
          }
        } else {
          score = inWinRate;
        }

        final int totalTrades = inTrades + outTrades;

        // 优选胜率/得分更高的；如果相同，选交易次数更多的；如果还相同，选天数更小（更灵敏）的
        if (score > bestScore ||
            (score == bestScore && totalTrades > bestTrades) ||
            (score == bestScore && totalTrades == bestTrades && sellX < bestX)) {
          bestScore = score;
          bestTrades = totalTrades;
          bestX = sellX;
          bestPct = sellPct;
        }
      }
    }

    if (bestX != -1) {
      // 紧凑编码： sell_x = sellX * 1000 + sellPct.round()
      return {
        'sell_x': bestX * 1000 + bestPct.round(),
        'sell_win_rate': bestScore,
        'sell_trades': bestTrades,
      };
    }
    return null;
  }
}
