// lib/utils.dart

class NumberFormatter {
  /// 将数字转换为 K, M 简写，三位数及以下保持不变
  static String format(dynamic value) {
    if (value == null) return "0";

    // 1. 处理输入，兼容 String 或 num 类型
    double numValue;
    if (value is String) {
      // 移除可能存在的 $ 或 , 符号再转换
      numValue = double.tryParse(value.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
    } else {
      numValue = value.toDouble();
    }

    bool isNegative = numValue < 0;
    double absValue = numValue.abs();
    String result;

    // 2. 核心转换逻辑
    if (absValue >= 1000000) {
      result = "${_cleanDecimal(absValue / 1000000)}M";
    } else if (absValue >= 1000) {
      result = "${_cleanDecimal(absValue / 1000)}k";
    } else {
      // 三位数以下：123.45 -> 123.5，如果是整数则直接显示
      result = _cleanDecimal(absValue);
    }

    return isNegative ? "-$result" : result;
  }

  // 内部辅助函数：美化小数点，如果是整数则去掉 .0
  static String _cleanDecimal(double val) {
    if (val % 1 == 0) {
      return val.toInt().toString();
    } else {
      // 保留一位小数
      return val.toStringAsFixed(1);
    }
  }
}