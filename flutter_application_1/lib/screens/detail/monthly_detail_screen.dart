import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/trade_card_widget.dart';

// ================= 📊 月度深度复盘详情页 =================
class MonthlyDetailScreen extends StatefulWidget {
  final String monthYear;

  const MonthlyDetailScreen({super.key, required this.monthYear});

  @override
  State<MonthlyDetailScreen> createState() => _MonthlyDetailScreenState();
}

class _MonthlyDetailScreenState extends State<MonthlyDetailScreen> {
  int _selectedTab = 0;
  bool isLoading = true;
  Map<String, dynamic>? statsData;
  List<dynamic> monthlyTrades = [];

  @override
  void initState() {
    super.initState();
    fetchMonthlyDetails();
  }

  Future<void> fetchMonthlyDetails() async {
    try {
      final response = await http.get(Uri.parse(
          '$kBaseUrl/api/monthly_details?month=${widget.monthYear}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            statsData = data['data'];
            monthlyTrades = data['trades'] ?? [];
            isLoading = false;
          });
        } else {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: AppColors.text),
            onPressed: () => Navigator.pop(context)),
        title: Text(widget.monthYear,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildTopToggle(),
          const SizedBox(height: 20),
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.green))
                : _selectedTab == 0
                    ? _buildStatsView()
                    : _buildTradesView(),
          )
        ],
      ),
    );
  }

  Widget _buildTopToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      height: 40,
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: Container(
                decoration: BoxDecoration(
                    color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text('Stats',
                    style: TextStyle(
                        color: _selectedTab == 0 ? AppColors.darkBg : AppColors.dim,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 1),
              child: Container(
                decoration: BoxDecoration(
                    color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: Text('Trades',
                    style: TextStyle(
                        color: _selectedTab == 1 ? AppColors.darkBg : AppColors.dim,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsView() {
    if (statsData == null) {
      return const Center(
          child: Text('No trades this month.',
              style: TextStyle(color: Color(0xFF666666))));
    }

    final gl = statsData!['gain_loss'];
    final ls = statsData!['long_short'];
    final tm = statsData!['timing'];
    final bw = statsData!['best_worst'];
    final List<dynamic> symByTrades = statsData!['symbols_by_trades'] ?? [];
    final List<dynamic> symByAmount = statsData!['symbols_by_amount'] ?? [];

    final longAll = int.tryParse(ls['long']['all'] ?? '0') ?? 0;
    final shortAll = int.tryParse(ls['short']['all'] ?? '0') ?? 0;
    final total = longAll + shortAll;
    final longFrac = total > 0 ? longAll / total : 0.5;
    final shortFrac = total > 0 ? shortAll / total : 0.5;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _msCard(
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.blue,
            title: 'Gain / Loss',
            child: Column(children: [
              _msTblHeader(),
              _msRow('Total', gl['total']['all'], gl['total']['won'],
                  gl['total']['lost'],
                  colored: true),
              _msRow('Avg \$', gl['avg_usd']['all'], gl['avg_usd']['won'],
                  gl['avg_usd']['lost'],
                  colored: true),
              _msRow('Avg %', gl['avg_pct']['all'], gl['avg_pct']['won'],
                  gl['avg_pct']['lost'],
                  colored: true),
              _msRow('Trades', gl['trades']['all'], gl['trades']['won'],
                  gl['trades']['lost']),
              const Divider(color: Color(0xFF252830), height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Win Rate',
                    style: TextStyle(color: AppColors.dim, fontSize: 13)),
                Text(gl['win_rate'],
                    style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          _msCard(
            icon: Icons.compare_arrows_rounded,
            iconColor: AppColors.orange,
            title: 'Long / Short',
            child: Column(children: [
              _msTblHeader(),
              _msRow('Long Trades', ls['long']['all'], ls['long']['won'],
                  ls['long']['lost']),
              _msRow('Short Trades', ls['short']['all'], ls['short']['won'],
                  ls['short']['lost']),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(children: [
                  Flexible(
                      flex: (longFrac * 1000).round(),
                      child:
                          Container(height: 8, color: AppColors.blue)),
                  const SizedBox(width: 2),
                  Flexible(
                      flex: (shortFrac * 1000).round(),
                      child:
                          Container(height: 8, color: AppColors.orange)),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _msLegend(AppColors.blue,
                    'Long  ${(longFrac * 100).toStringAsFixed(0)}%'),
                const SizedBox(width: 16),
                _msLegend(AppColors.orange,
                    'Short  ${(shortFrac * 100).toStringAsFixed(0)}%'),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          _msCard(
            icon: Icons.timer_outlined,
            iconColor: AppColors.purple,
            title: 'Timing',
            child: Column(children: [
              _msTblHeader(),
              _msRow('Hold Time', tm['holding']['all'], tm['holding']['won'],
                  tm['holding']['lost']),
              _msRow('Avg Entry Hr', tm['entry_hour']['all'],
                  tm['entry_hour']['won'], tm['entry_hour']['lost']),
            ]),
          ),
          const SizedBox(height: 14),
          _msCard(
            icon: Icons.emoji_events_outlined,
            iconColor: AppColors.yellow,
            title: 'Best / Worst',
            child: Column(children: [
              _msBwHeader(),
              _msBwRow('Largest \$', bw['largest_usd']['won'],
                  bw['largest_usd']['lost']),
              _msBwRow('Largest %', bw['largest_pct']['won'],
                  bw['largest_pct']['lost']),
            ]),
          ),
          const SizedBox(height: 14),
          if (symByTrades.isNotEmpty) ...[
            _msCard(
              icon: Icons.stacked_bar_chart_rounded,
              iconColor: AppColors.green,
              title: 'Trades by Symbol',
              child: Column(children: [
                _msTblHeader(),
                ...symByTrades.map((s) => _msRow(s['symbol'],
                    s['trades']['all'], s['trades']['won'], s['trades']['lost'])),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          if (symByAmount.isNotEmpty)
            _msCard(
              icon: Icons.attach_money_rounded,
              iconColor: AppColors.green,
              title: 'P&L by Symbol',
              child: Column(
                children: symByAmount.map((s) {
                  final raw = (s['pnl_raw'] as num?)?.toDouble() ?? 0.0;
                  final isP = s['isProfit'] as bool? ?? raw >= 0;
                  final clr = isP ? AppColors.green : AppColors.red;
                  final sign = isP ? '+' : '-';
                  final pnlStr2 = sign + r'$' + raw.abs().toStringAsFixed(2);
                  return _msSymbolRow(
                    s['symbol'] as String,
                    pnlStr2,
                    clr,
                    s['trades']['all'] + ' trades',
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _msCard(
      {required IconData icon,
      required Color iconColor,
      required String title,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2028)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  Widget _msTblHeader() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: const [
          Expanded(flex: 4, child: SizedBox()),
          Expanded(
              flex: 3,
              child: Text('All',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 11,
                      letterSpacing: 0.4))),
          Expanded(
              flex: 3,
              child: Text('Won',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppColors.green,
                      fontSize: 11,
                      letterSpacing: 0.4))),
          Expanded(
              flex: 3,
              child: Text('Lost',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppColors.red,
                      fontSize: 11,
                      letterSpacing: 0.4))),
        ]),
      );

  Widget _msRow(String label, String all, String won, String lost,
      {bool colored = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(children: [
        Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(color: AppColors.dim, fontSize: 13))),
        Expanded(
            flex: 3,
            child: Text(all,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
        Expanded(
            flex: 3,
            child: Text(won,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: colored ? AppColors.green : AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
        Expanded(
            flex: 3,
            child: Text(lost,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: colored ? AppColors.red : AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _msBwHeader() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: const [
          Expanded(flex: 4, child: SizedBox()),
          Expanded(
              flex: 3,
              child: Text('Best',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppColors.green,
                      fontSize: 11,
                      letterSpacing: 0.4))),
          Expanded(
              flex: 3,
              child: Text('Worst',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: AppColors.red,
                      fontSize: 11,
                      letterSpacing: 0.4))),
        ]),
      );

  Widget _msBwRow(String label, String best, String worst) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(children: [
          Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(color: AppColors.dim, fontSize: 13))),
          Expanded(
              flex: 3,
              child: Text(best,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
          Expanded(
              flex: 3,
              child: Text(worst,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _msLegend(Color color, String text) =>
      Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: AppColors.dim, fontSize: 11)),
      ]);

  Widget _msSymbolRow(
      String symbol, String pnlStr, Color pnlColor, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(9)),
          alignment: Alignment.center,
          child: Text(symbol.isNotEmpty ? symbol[0] : '?',
              style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(symbol,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style:
                      TextStyle(color: AppColors.dim, fontSize: 11)),
            ])),
        Text(pnlStr,
            style: TextStyle(
                color: pnlColor, fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildTradesView() {
    if (monthlyTrades.isEmpty) {
      return const Center(
        child: Text('No trades found for this month.',
            style: TextStyle(color: Color(0xFF666666))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: monthlyTrades.length,
      itemBuilder: (context, index) =>
          TradeCardWidget(trade: monthlyTrades[index]),
    );
  }
}
