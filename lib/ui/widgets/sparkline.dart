import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  final List<double> data;
  final Color lineColor;
  final double strokeWidth;

  const Sparkline({
    super.key,
    required this.data,
    this.lineColor = const Color(0xFF0097E6),
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(
        child: Text(
          '-',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }

    // 如果只有 1 个数据点，无法绘制折线，直接画个点
    if (data.length < 2) {
      return Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFF0097E6),
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    // 优化：直接传入原始数据和采样参数给 Painter，避免在 build 中创建临时列表
    // navList 是从新到旧（倒序），Painter 内部按从旧到新的方向绘制
    return SizedBox(
      height: 30,
      child: CustomPaint(
        painter: _SparklinePainter(data, lineColor, strokeWidth),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data; // 原始数据（从新到旧）
  final Color lineColor;
  final double strokeWidth;

  _SparklinePainter(this.data, this.lineColor, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // 优化：直接对原始数据采样，不创建反转列表
    // 采样最多 60 个点，从旧到新（即从 data 末尾到开头）
    const int maxPoints = 60;
    final int n = data.length;
    final int sampleCount = n > maxPoints ? maxPoints : n;
    final double step = (n - 1) / (sampleCount - 1);

    // 直接计算采样点的值（从旧到新 = 从 data 末尾到开头）
    double maxVal = -double.infinity;
    double minVal = double.infinity;

    for (int i = 0; i < sampleCount; i++) {
      final int idx = n - 1 - (i * step).floor();
      final double val = data[idx];
      if (val > maxVal) maxVal = val;
      if (val < minVal) minVal = val;
    }

    final double range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    final double widthStep = size.width / (sampleCount - 1);
    final path = Path();

    for (int i = 0; i < sampleCount; i++) {
      final int idx = n - 1 - (i * step).floor();
      final double val = data[idx];
      final double x = i * widthStep;
      final double y =
          2 + (size.height - 4) - ((val - minVal) / range * (size.height - 4));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // 绘制起点（绿色，最旧）和终点（红色，最新）
    final startPaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..style = PaintingStyle.fill;
    final endPaint = Paint()
      ..color = const Color(0xFFC62828)
      ..style = PaintingStyle.fill;

    // 起点：最旧的数据（data 最后一个）
    const double firstX = 0;
    final double firstVal = data[n - 1];
    final double firstY = 2 +
        (size.height - 4) -
        ((firstVal - minVal) / range * (size.height - 4));
    canvas.drawCircle(Offset(firstX, firstY), 1.5, startPaint);

    // 终点：最新的数据（data 第一个）
    final double lastX = size.width;
    final double lastVal = data[0];
    final double lastY = 2 +
        (size.height - 4) -
        ((lastVal - minVal) / range * (size.height - 4));
    canvas.drawCircle(Offset(lastX, lastY), 1.5, endPaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.data.length != data.length) return true;
    // 只比较前几个和最后几个点，避免全量比较
    final int checkCount = data.length > 10 ? 10 : data.length;
    for (int i = 0; i < checkCount; i++) {
      if (oldDelegate.data[i] != data[i]) return true;
    }
    for (int i = data.length - checkCount; i < data.length; i++) {
      if (oldDelegate.data[i] != data[i]) return true;
    }
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
