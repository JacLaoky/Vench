import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/screens/detail/trade_detail_screen.dart';
import 'package:flutter_application_1/widgets/tag_chip.dart';
import 'package:flutter_application_1/widgets/tag_editor_sheet.dart';

// ================= 🃏 独立的交易卡片组件 (防溢出 + 期权解析版) =================
class TradeCardWidget extends StatelessWidget {
  final dynamic trade;
  final VoidCallback? onTagsUpdated;
  const TradeCardWidget({super.key, required this.trade, this.onTagsUpdated});

  // 🌟 核心引擎：智能解析期权代码
  Map<String, String> _parseOptionTicker(String rawTicker) {
    String symbol = rawTicker;
    String optionInfo = '';

    // 使用正则提取：字母部分(正股) + 数字开头的部分(期权后缀)
    final match = RegExp(r'^([A-Za-z]+)(\d.*)$').firstMatch(rawTicker);
    if (match != null) {
      symbol = match.group(1)!;
      String rawDetails = match.group(2)!; // 如: 251219P270000

      // 尝试进一步翻译标准 OCC 期权格式 (年月日 + C/P + 行权价)
      final optMatch = RegExp(r'^(\d{6})([CP])(\d+)$').firstMatch(rawDetails);
      if (optMatch != null) {
        String date = optMatch.group(1)!;
        String type = optMatch.group(2)! == 'C' ? 'Call' : 'Put';
        // 期权的行权价通常要除以 1000
        double strike = double.parse(optMatch.group(3)!) / 1000;
        String strikeStr = strike.toStringAsFixed(strike.truncateToDouble() == strike ? 0 : 2);

        optionInfo = '$date $type \$$strikeStr'; // 生成类似 "251219 Put $270"
      } else {
        optionInfo = rawDetails; // 如果不是标准格式，原样分行显示防溢出
      }
    }
    return {'symbol': symbol, 'info': optionInfo};
  }

  void _showTagEditor(BuildContext context) {
    showTagEditor(context, trade, onTagsUpdated);
  }

  void _showSetStopDialog(BuildContext context, String positionId, String ticker, double? currentStop) {
    final ctrl = TextEditingController(text: currentStop?.toStringAsFixed(2) ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Set Stop Price', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'e.g. 780.00',
            hintStyle: TextStyle(color: AppColors.dim),
            prefixText: '\$ ',
            prefixStyle: TextStyle(color: AppColors.dim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.dim)),
          ),
          TextButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                await http.patch(
                  Uri.parse('$kBaseUrl/api/positions/$positionId/stop'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'stop_price': val, 'ticker': ticker}),
                );
                if (context.mounted) Navigator.pop(context);
                onTagsUpdated?.call();
              }
            },
            child: const Text('Save', style: TextStyle(color: AppColors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String day = trade['day'];
    final String month = trade['month'];
    final String rawTicker = trade['ticker'];
    final String tradeType = trade['trade_type'] ?? 'LONG';
    final double pnl = (trade['pnl'] as num).toDouble();
    final String pct = trade['pct'];
    final bool isProfit = trade['isProfit'];

    // Position / stop / R multiple
    final String? positionId = trade['position_id'] as String?;
    final double? stopPrice  = (trade['stop_price']  as num?)?.toDouble();
    final double entryPrice  = (trade['entry_price'] as num?)?.toDouble() ?? 0.0;

    // R = (exit_price − entry_price) / (entry_price − stop_price)
    // Pure per-share ratio — consistent regardless of how many shares are sold
    final double exitPrice = (trade['price'] as num?)?.toDouble() ?? 0.0;
    double? rMultiple;
    if (stopPrice != null && stopPrice > 0 && entryPrice > 0 && exitPrice > 0) {
      final riskPerShare = (entryPrice - stopPrice).abs();
      if (riskPerShare > 0.001) {
        rMultiple = (exitPrice - entryPrice) / (entryPrice - stopPrice);
      }
    }

    // Tags
    final rawTags = trade['tags'];
    final List<String> tags = rawTags is List ? List<String>.from(rawTags) : [];

    // 调用解析器
    final parsed = _parseOptionTicker(rawTicker);
    final String symbol = parsed['symbol']!;
    final String optionInfo = parsed['info']!;

    final colorText = isProfit ? AppColors.green : AppColors.red;
    final String initial = symbol.isNotEmpty ? symbol[0] : '?';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => TradeDetailScreen(trade: trade)),
        );
      },
      onLongPress: () => _showTagEditor(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          // Uniform border color — required when borderRadius is set
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        // ClipRRect so the inner coloured strip respects the card's rounded corners
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15.5),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left accent strip ──
                Container(
                  width: 3,
                  color: isProfit ? AppColors.green : AppColors.red,
                ),
                // ── Card content ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Column(
                              children: [
                                Text(day, style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                                Text(month, style: TextStyle(color: AppColors.dim, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(width: 16),

                            Expanded( // Expanded 保证中间这块区域无论文字多长都不会把右边的钱挤出屏幕
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFFFF7A00),
                                    child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), // intentional: white on orange avatar
                                  ),
                                  const SizedBox(width: 12),
                                  // 将这里改为 Expanded，防止长文字撑爆 Row
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 第一行：只显示 AAPL LONG
                                        Text('$symbol $tradeType',
                                          style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis, // 终极防御：如果还是太长就显示省略号
                                        ),

                                        // 🌟 第二行：如果有期权信息，用高亮蓝色显示在下方
                                        if (optionInfo.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                                            child: Text(optionInfo,
                                              style: const TextStyle(color: Color(0xFF4DA1FF), fontSize: 12, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),

                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.shield_outlined, color: Color(0xFF30D158), size: 14),
                                            const SizedBox(width: 4),
                                            Text('Verified', style: TextStyle(color: AppColors.text.withValues(alpha: 0.55), fontSize: 12)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  pnl == 0 ? '\$0.00' : '${pnl > 0 ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}',
                                  style: TextStyle(color: colorText, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                if (pnl != 0)
                                  Text(pct, style: TextStyle(color: colorText, fontSize: 12, fontWeight: FontWeight.bold)),
                                // R multiple badge
                                if (rMultiple != null) ...[
                                  const SizedBox(height: 4),
                                  _RBadge(r: rMultiple),
                                ],
                              ],
                            ),
                          ],
                        ),
                        // ── Tags row ──
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: tags.map((t) => TagChip(tag: t)).toList(),
                          ),
                        ],
                        // ── Stop price row ──
                        if (stopPrice != null || positionId != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.flag_outlined, size: 13, color: AppColors.dim),
                              const SizedBox(width: 4),
                              if (stopPrice != null)
                                Text(
                                  'Stop \$${stopPrice.toStringAsFixed(2)}',
                                  style: TextStyle(color: AppColors.dim, fontSize: 12),
                                )
                              else
                                Text('Stop not set', style: TextStyle(color: AppColors.dim, fontSize: 12)),
                              if (positionId != null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _showSetStopDialog(context, positionId, rawTicker, stopPrice),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.blue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      stopPrice != null ? 'Edit' : 'Set Stop',
                                      style: const TextStyle(color: AppColors.blue, fontSize: 11),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
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

// ── R multiple badge widget ───────────────────────────────────────────────────
class _RBadge extends StatelessWidget {
  final double r;
  const _RBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    final isPositive = r >= 0;
    final color = isPositive ? AppColors.green : AppColors.red;
    final sign = r > 0 ? '+' : '';
    final label = '$sign${r.toStringAsFixed(1)}R';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
