import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ================= 🧮 Calculator Screen =================
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        title: const Text('Calculator',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: AppColors.darkBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.dim,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'Scale In'),
                  Tab(text: 'Swing Trade'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _ScaleInTab(),
          _SwingTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Scale In (configurable ratio)
// ─────────────────────────────────────────────────────────────────────────────
class _ScaleInTab extends StatefulWidget {
  const _ScaleInTab();

  @override
  State<_ScaleInTab> createState() => _ScaleInTabState();
}

class _ScaleInTabState extends State<_ScaleInTab> {
  final _capCtrl = TextEditingController();
  final _pctCtrl = TextEditingController();
  final _p1Ctrl  = TextEditingController();
  final _p2Ctrl  = TextEditingController();
  final _p3Ctrl  = TextEditingController();
  final _r1Ctrl  = TextEditingController(text: '1');
  final _r2Ctrl  = TextEditingController(text: '2');
  final _r3Ctrl  = TextEditingController(text: '4');

  double? _capital, _pct, _p1, _p2, _p3;
  double _r1 = 1, _r2 = 2, _r3 = 4;

  @override
  void initState() {
    super.initState();
    _loadRatio();
  }

  Future<void> _loadRatio() async {
    final prefs = await SharedPreferences.getInstance();
    final r1 = prefs.getString('calc_r1');
    final r2 = prefs.getString('calc_r2');
    final r3 = prefs.getString('calc_r3');
    if (r1 != null) { _r1Ctrl.text = r1; }
    if (r2 != null) { _r2Ctrl.text = r2; }
    if (r3 != null) { _r3Ctrl.text = r3; }
    // Pre-fill capital from last fetched account total (saved by Portfolio)
    final acctTotal = prefs.getDouble('account_total_assets');
    if (acctTotal != null && acctTotal > 0 && _capCtrl.text.isEmpty) {
      _capCtrl.text = acctTotal.toStringAsFixed(0);
    }
    _parse();
  }

  @override
  void dispose() {
    for (final c in [
      _capCtrl, _pctCtrl, _p1Ctrl, _p2Ctrl, _p3Ctrl,
      _r1Ctrl, _r2Ctrl, _r3Ctrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _parse() {
    _capital = double.tryParse(_capCtrl.text);
    _pct     = double.tryParse(_pctCtrl.text);
    _p1      = double.tryParse(_p1Ctrl.text);
    _p2      = double.tryParse(_p2Ctrl.text);
    _p3      = double.tryParse(_p3Ctrl.text);
    _r1      = double.tryParse(_r1Ctrl.text) ?? 1;
    _r2      = double.tryParse(_r2Ctrl.text) ?? 2;
    _r3      = double.tryParse(_r3Ctrl.text) ?? 4;
    setState(() {});
    // Persist ratio whenever it changes
    SharedPreferences.getInstance().then((p) {
      p.setString('calc_r1', _r1Ctrl.text);
      p.setString('calc_r2', _r2Ctrl.text);
      p.setString('calc_r3', _r3Ctrl.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratioLabel =
        '${_r1.toStringAsFixed(_r1 % 1 == 0 ? 0 : 1)}'
        ':${_r2.toStringAsFixed(_r2 % 1 == 0 ? 0 : 1)}'
        ':${_r3.toStringAsFixed(_r3 % 1 == 0 ? 0 : 1)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(children: [
        // ── Info banner ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline,
                color: AppColors.blue, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Splits your budget $ratioLabel across three entries. '
                'Heavier allocation at lower prices.',
                style: TextStyle(
                    color: AppColors.dim, fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Input area ───────────────────────────────────────────────
        _CalcCard(children: [
          _CalcField(
              label: 'Capital (\$)',
              ctrl: _capCtrl,
              onChanged: (_) => _parse()),
          _CalcField(
              label: 'Target Size (%)',
              ctrl: _pctCtrl,
              onChanged: (_) => _parse(),
              hint: 'e.g. 10'),
          const SizedBox(height: 8),

          // ── Ratio row ─────────────────────────────────────────────
          Row(children: [
            Expanded(
              flex: 2,
              child: Text('Ratio',
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
            ),
            Expanded(
              flex: 3,
              child: Row(children: [
                Expanded(
                  child: _RatioBox(
                      label: 'R1',
                      ctrl: _r1Ctrl,
                      onChanged: (_) => _parse()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':',
                      style: TextStyle(color: AppColors.dim, fontSize: 16)),
                ),
                Expanded(
                  child: _RatioBox(
                      label: 'R2',
                      ctrl: _r2Ctrl,
                      onChanged: (_) => _parse()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(':',
                      style: TextStyle(color: AppColors.dim, fontSize: 16)),
                ),
                Expanded(
                  child: _RatioBox(
                      label: 'R3',
                      ctrl: _r3Ctrl,
                      onChanged: (_) => _parse()),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),

          Text('Entry Prices (\$)',
              style: TextStyle(color: AppColors.dim, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _PriceBox(
                    label: 'P1',
                    ctrl: _p1Ctrl,
                    onChanged: (_) => _parse())),
            const SizedBox(width: 8),
            Expanded(
                child: _PriceBox(
                    label: 'P2',
                    ctrl: _p2Ctrl,
                    onChanged: (_) => _parse())),
            const SizedBox(width: 8),
            Expanded(
                child: _PriceBox(
                    label: 'P3',
                    ctrl: _p3Ctrl,
                    onChanged: (_) => _parse())),
          ]),
        ]),

        const SizedBox(height: 16),

        // ── Results ──────────────────────────────────────────────────
        if (_capital != null && _pct != null)
          _ScaleInResult(
            capital: _capital!,
            pct: _pct!,
            p1: _p1,
            p2: _p2,
            p3: _p3,
            r1: _r1,
            r2: _r2,
            r3: _r3,
          )
        else
          _EmptyResult('Enter capital & target size to begin'),
      ]),
    );
  }
}

class _ScaleInResult extends StatelessWidget {
  final double capital, pct;
  final double? p1, p2, p3;
  final double r1, r2, r3;

  const _ScaleInResult({
    required this.capital,
    required this.pct,
    this.p1,
    this.p2,
    this.p3,
    required this.r1,
    required this.r2,
    required this.r3,
  });

  @override
  Widget build(BuildContext context) {
    final budget = capital * (pct / 100);
    final total = r1 + r2 + r3;
    final b1 = total > 0 ? budget * (r1 / total) : 0.0;
    final b2 = total > 0 ? budget * (r2 / total) : 0.0;
    final b3 = total > 0 ? budget * (r3 / total) : 0.0;

    final s1 = p1 != null && p1! > 0 ? (b1 / p1!).floor() : null;
    final s2 = p2 != null && p2! > 0 ? (b2 / p2!).floor() : null;
    final s3 = p3 != null && p3! > 0 ? (b3 / p3!).floor() : null;

    double totalCost = 0, totalShares = 0;
    if (s1 != null && p1 != null) {
      totalCost += s1 * p1!;
      totalShares += s1;
    }
    if (s2 != null && p2 != null) {
      totalCost += s2 * p2!;
      totalShares += s2;
    }
    if (s3 != null && p3 != null) {
      totalCost += s3 * p3!;
      totalShares += s3;
    }
    final avgCost = totalShares > 0 ? totalCost / totalShares : null;

    String fracLabel(double r) {
      if (total <= 0) return '—';
      final pct = (r / total * 100).round();
      return '$pct%';
    }

    return _CalcCard(children: [
      // Total budget
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Total Budget',
            style: TextStyle(color: AppColors.dim, fontSize: 13)),
        Text('\$${budget.toStringAsFixed(2)}',
            style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 16),

      // Three tranches
      ...[
        (1, r1, b1, s1, p1),
        (2, r2, b2, s2, p2),
        (3, r3, b3, s3, p3),
      ].map((row) {
        final (n, ratio, budget, shares, price) = row;
        final isReady = shares != null && price != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('$n',
                  style: const TextStyle(
                      color: AppColors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Tranche $n  (${fracLabel(ratio)})',
                      style: TextStyle(
                          color: AppColors.dim, fontSize: 12)),
                  Text('\$${budget.toStringAsFixed(0)} budget',
                      style: TextStyle(
                          color: AppColors.dimDark, fontSize: 11)),
                ])),
            if (isReady)
              GestureDetector(
                onTap: () => _copy(context,
                    '$shares shares @ \$${price.toStringAsFixed(2)}'),
                child: Row(children: [
                  Text('$shares',
                      style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Text('shares',
                      style: TextStyle(
                          color: AppColors.dim, fontSize: 12)),
                  const SizedBox(width: 4),
                  Icon(Icons.copy_outlined,
                      color: AppColors.dimDark, size: 13),
                ]),
              )
            else
              Text('—',
                  style: TextStyle(
                      color: AppColors.dimDark, fontSize: 16)),
          ]),
        );
      }),

      // Weighted avg cost
      if (avgCost != null) ...[
        const Divider(color: Color(0xFF222222), height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Avg Cost (if all filled)',
              style: TextStyle(color: AppColors.dim, fontSize: 12)),
          Text('\$${avgCost.toStringAsFixed(3)}',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total Shares',
              style: TextStyle(color: AppColors.dim, fontSize: 12)),
          Text('${totalShares.toInt()}',
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ]),
      ],
    ]);
  }

  void _copy(BuildContext ctx, String text) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text('Copied: $text'),
      backgroundColor: AppColors.surface2,
      duration: const Duration(seconds: 1),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Swing Trade
// ─────────────────────────────────────────────────────────────────────────────
class _SwingTab extends StatefulWidget {
  const _SwingTab();

  @override
  State<_SwingTab> createState() => _SwingTabState();
}

class _SwingTabState extends State<_SwingTab> {
  final _capCtrl  = TextEditingController();
  final _riskCtrl = TextEditingController(text: '0.5');
  final _entCtrl  = TextEditingController();
  final _stopCtrl = TextEditingController();

  bool _isLong = true;
  double? _capital, _riskPct, _entry, _stop;

  static const _riskPresets = [0.25, 0.5, 1.0, 2.0];

  @override
  void initState() {
    super.initState();
    _loadCapital();
  }

  Future<void> _loadCapital() async {
    final prefs = await SharedPreferences.getInstance();
    final acctTotal = prefs.getDouble('account_total_assets');
    if (acctTotal != null && acctTotal > 0 && _capCtrl.text.isEmpty) {
      _capCtrl.text = acctTotal.toStringAsFixed(0);
      _parse();
    }
  }

  @override
  void dispose() {
    for (final c in [_capCtrl, _riskCtrl, _entCtrl, _stopCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _parse() {
    _capital = double.tryParse(_capCtrl.text);
    _riskPct = double.tryParse(_riskCtrl.text);
    _entry   = double.tryParse(_entCtrl.text);
    _stop    = double.tryParse(_stopCtrl.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(children: [
        // ── Long / Short toggle ──────────────────────────────────────
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
                child: GestureDetector(
              onTap: () => setState(() => _isLong = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _isLong ? AppColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('Long',
                    style: TextStyle(
                      color: _isLong ? Colors.black : AppColors.dim,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    )),
              ),
            )),
            Expanded(
                child: GestureDetector(
              onTap: () => setState(() => _isLong = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: !_isLong ? AppColors.red : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('Short',
                    style: TextStyle(
                      color: !_isLong ? Colors.white : AppColors.dim,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    )),
              ),
            )),
          ]),
        ),
        const SizedBox(height: 16),

        // ── Input area ───────────────────────────────────────────────
        _CalcCard(children: [
          _CalcField(
              label: 'Capital (\$)',
              ctrl: _capCtrl,
              onChanged: (_) => _parse()),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 2,
              child: Text('Max Risk (%)',
                  style: TextStyle(color: AppColors.dim, fontSize: 13)),
            ),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _riskCtrl,
                onChanged: (_) => _parse(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: TextStyle(color: AppColors.text, fontSize: 15),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
              children: _riskPresets
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            _riskCtrl.text = r.toString();
                            _parse();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _riskPct == r
                                  ? AppColors.blue.withValues(alpha: 0.2)
                                  : AppColors.surface2,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _riskPct == r
                                    ? AppColors.blue
                                    : AppColors.border,
                              ),
                            ),
                            child: Text('$r%',
                                style: TextStyle(
                                  color: _riskPct == r
                                      ? AppColors.blue
                                      : AppColors.dim,
                                  fontSize: 12,
                                  fontWeight: _riskPct == r
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                )),
                          ),
                        ),
                      ))
                  .toList()),
          const SizedBox(height: 4),
          _CalcField(
              label: 'Entry Price (\$)',
              ctrl: _entCtrl,
              onChanged: (_) => _parse()),
          _CalcField(
              label: 'Stop Loss (\$)',
              ctrl: _stopCtrl,
              onChanged: (_) => _parse()),
        ]),
        const SizedBox(height: 16),

        // ── Results ──────────────────────────────────────────────────
        if (_capital != null &&
            _riskPct != null &&
            _entry != null &&
            _stop != null)
          _SwingResult(
            capital: _capital!,
            riskPct: _riskPct!,
            entry: _entry!,
            stop: _stop!,
            isLong: _isLong,
          )
        else
          _EmptyResult('Enter all fields to calculate position'),
      ]),
    );
  }
}

class _SwingResult extends StatelessWidget {
  final double capital, riskPct, entry, stop;
  final bool isLong;

  const _SwingResult({
    required this.capital,
    required this.riskPct,
    required this.entry,
    required this.stop,
    required this.isLong,
  });

  @override
  Widget build(BuildContext context) {
    final maxRisk      = capital * (riskPct / 100);
    final riskPerShare = isLong ? (entry - stop) : (stop - entry);

    if (riskPerShare <= 0) {
      return _CalcCard(children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.red, size: 18),
          const SizedBox(width: 8),
          Text(
            isLong
                ? 'Stop loss must be below entry price'
                : 'Stop loss must be above entry price',
            style: const TextStyle(color: AppColors.red, fontSize: 13),
          ),
        ]),
      ]);
    }

    final shares    = (maxRisk / riskPerShare).floor();
    final totalCost = shares * entry;
    final costPct   = totalCost / capital * 100;

    const ratios = [1.0, 1.5, 2.0, 3.0, 4.0, 5.0];

    return Column(children: [
      // ── Position summary card ─────────────────────────────────────
      _CalcCard(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(isLong ? 'Buy' : 'Short',
              style: TextStyle(
                  color: isLong ? AppColors.green : AppColors.red,
                  fontSize: 13)),
          Text('$shares shares',
              style: TextStyle(
                  color: isLong ? AppColors.green : AppColors.red,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        _ResultRow('Total Cost',
            '\$${totalCost.toStringAsFixed(2)}  (${costPct.toStringAsFixed(1)}% of capital)'),
        _ResultRow('Max Risk',
            '\$${maxRisk.toStringAsFixed(2)}  (${riskPct}%)'),
        _ResultRow(
            'Risk per Share', '\$${riskPerShare.toStringAsFixed(3)}'),
        _ResultRow('Stop Loss', '\$${stop.toStringAsFixed(2)}'),
      ]),
      const SizedBox(height: 12),

      // ── R:R target grid ──────────────────────────────────────────
      _CalcCard(children: [
        Text('Take Profit Targets',
            style: TextStyle(
                color: AppColors.dim,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.15,
          ),
          itemCount: ratios.length,
          itemBuilder: (_, i) {
            final r      = ratios[i];
            final target = isLong
                ? entry + riskPerShare * r
                : entry - riskPerShare * r;
            final profit    = shares * riskPerShare * r;
            final isHighlight = r >= 2.0;
            return GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${r}R → \$${target.toStringAsFixed(2)}'
                      '  (+\$${profit.toStringAsFixed(2)})'),
                  backgroundColor: AppColors.surface2,
                  duration: const Duration(seconds: 1),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: isHighlight
                      ? AppColors.green.withValues(alpha: 0.08)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isHighlight
                        ? AppColors.green.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${r}R',
                        style: TextStyle(
                            color: isHighlight
                                ? AppColors.green
                                : AppColors.dim,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('\$${target.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('+\$${profit.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: AppColors.green, fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        ),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────
class _CalcCard extends StatelessWidget {
  final List<Widget> children;

  const _CalcCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      );
}

class _CalcField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;
  final String? hint;

  const _CalcField({
    required this.label,
    required this.ctrl,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.dim, fontSize: 13))),
          Expanded(
              flex: 3,
              child: TextField(
                controller: ctrl,
                onChanged: onChanged,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style:
                    TextStyle(color: AppColors.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      const TextStyle(color: Color(0xFF444444)),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              )),
        ]),
      );
}

class _PriceBox extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;

  const _PriceBox({
    required this.label,
    required this.ctrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(
                color: AppColors.dimDark, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: '—',
            hintStyle: const TextStyle(color: Color(0xFF444444)),
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          ),
        ),
      ]);
}

class _RatioBox extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;

  const _RatioBox({
    required this.label,
    required this.ctrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: TextStyle(
                color: AppColors.dimDark, fontSize: 11)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          ),
        ),
      ]);
}

class _ResultRow extends StatelessWidget {
  final String label, value;

  const _ResultRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.dim, fontSize: 13)),
              Text(value,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
      );
}

class _EmptyResult extends StatelessWidget {
  final String message;

  const _EmptyResult(this.message);

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.dimDark, fontSize: 14)),
      );
}
