import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/utils.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/empty_state.dart';
import 'package:flutter_application_1/widgets/trade_card_widget.dart';
import 'package:flutter_application_1/screens/detail/all_trades_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';
import 'package:flutter_application_1/screens/sectors_screen.dart';
import 'package:flutter_application_1/screens/tag_stats_screen.dart';
import 'package:flutter_application_1/screens/market_breadth_screen.dart';
import 'package:flutter_application_1/screens/earnings_calendar_screen.dart';
import 'package:flutter_application_1/screens/holdings_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool isLoading = true;
  bool hasError = false;
  bool _isFirstLoad = true;
  String totalPnl = "\$0";
  String winRate = "0%";
  String avgGain = "0%";
  bool isProfit = true;

  // 🌟 1. 新增：当前选中的时间周期状态
  String selectedTimeframe = '1M';

  // 🌟 新增：四个图表所需的动态数据
  String currentPnlValue = "\$0";
  Color currentPnlColor = AppColors.green;
  String currentWinRateValue = "0%";
  String currentAvgGainUsdValue = "\$0";
  String currentAvgGainPctValue = "0.00%";

  // 🌟 新增：四个图表环形的 Split (Green, Red) 分割数据，默认是灰色/Lost
  List<double> winSplit = [0.001, 0.999];
  List<double> avgGainSplitUsd = [0.001, 0.999];
  List<double> avgGainSplitPct = [0.001, 0.999];

  // Profit Factor & Trade Count
  String profitFactorValue = "—";
  List<double> profitFactorSplit = [0.001, 0.999];
  String tradeCountValue = "0";

  // Donut 插槽配置：4 个槽位，每个槽位选 6 种 metric 之一
  List<String> selectedCharts = ['profit', 'win_pct', 'avg_gain_usd', 'avg_gain_pct'];

  final List<String> allTimeframes = ['1W', '1M', '3M', '1Y', 'YTD', 'AT'];
  List<String> activeTimeframes = ['1M', '3M', '1Y', 'AT']; // 默认显示的 4 个

  // ── Account balance ──────────────────────────────────────
  double? _acctTotal;
  double? _acctSecurities;

  List<dynamic> latestTradesData = [];
  List<dynamic> last7DaysData = [];
  double chartMaxY = 10.0; // 动态控制 Y 轴高度，防止柱子冲破天际
  List<dynamic> profitChartDataFull = [];

  String? touchedDate;
  String? touchedProfitValue;
  double? touchedProfitRaw;

  @override
  void initState() {
    super.initState();
    _loadPrefsAndFetch();
  }

  Future<void> _loadPrefsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTf = prefs.getString('portfolio_timeframe');
    final savedActive = prefs.getStringList('portfolio_active_timeframes');
    setState(() {
      if (savedTf != null) selectedTimeframe = savedTf;
      if (savedActive != null && savedActive.isNotEmpty) activeTimeframes = savedActive;
    });
    fetchTradingStats();
    _fetchAccount();
  }

  Future<void> _fetchAccount() async {
    try {
      final res = await http.get(Uri.parse('$kBaseUrl/api/account'));
      if (res.statusCode == 200) {
        final d = json.decode(res.body);
        if (d['status'] == 'success') {
          final total = (d['total_assets'] as num).toDouble();
          setState(() {
            _acctTotal      = total;
            _acctSecurities = (d['securities_assets'] as num).toDouble();
          });
          // Persist so Calculator can pre-fill Capital without its own API call
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('account_total_assets', total);
        }
      }
    } catch (_) {
      // Silently ignore — banner just won't show
    }
  }

  Future<void> fetchTradingStats() async {
    setState(() => hasError = false);
    final String snapshotTimeLabel = timeLabel;

    try {
      // 🌟 2. 关键改变：把选中的时间发给 Python 后端！(如 ?period=1M)
      // (虽然目前后端还没处理这个参数，但前端框架我们先搭好)
      final response = await http.get(Uri.parse('$kBaseUrl/api/stats?period=$selectedTimeframe'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'empty') {
          setState(() {
            isLoading = false;
            _isFirstLoad = false;
            // Reset every display variable so no stale data bleeds through
            totalPnl              = '\$0';
            winRate               = '0%';
            avgGain               = '0%';
            isProfit              = true;
            currentPnlValue       = '\$0';
            currentPnlColor       = AppColors.dim;
            currentWinRateValue   = '0%';
            currentAvgGainUsdValue = '\$0.00';
            currentAvgGainPctValue = '0.00%';
            profitFactorValue     = '—';
            tradeCountValue       = '0';
            // Safe [0,1] splits won't crash PieChart
            winSplit            = [0.001, 0.999];
            avgGainSplitUsd     = [0.001, 0.999];
            avgGainSplitPct     = [0.001, 0.999];
            profitFactorSplit   = [0.001, 0.999];
            latestTradesData    = [];
            last7DaysData       = [];
            profitChartDataFull = [];
          });
          return;
        }

        if (data['status'] == 'success') {
          final summary = data['summary'];
          final rawPnl = summary['total_pnl'] ?? 0.0;

          // 接收图表数据
          final fetchedChartData = data['last_7_chart'] ?? [];

          // 动态计算 Y 轴高度边界 (找出这 7 天里赚/亏最多的那天的绝对值)
          double maxY = 10.0;
          for (var day in fetchedChartData) {
            double pnlAbs = (day['pnl'] as num).toDouble().abs();
            if (pnlAbs > maxY) maxY = pnlAbs;
          }

          setState(() {
            isProfit = rawPnl >= 0;
            currentPnlColor = isProfit ? AppColors.green : AppColors.red;
            String formattedValue = NumberFormatter.format(rawPnl.abs());

            totalPnl = isProfit ? "\$$formattedValue" : "-\$$formattedValue";

            winRate = summary['win_rate']?.toString() ?? "0%";
            // 🌟 核心：将后端传来的四个图表数据注入状态
            currentPnlValue = totalPnl;
            currentWinRateValue = summary['win_rate']?.toString() ?? "0%";

            // 如果标的是亏损的，AvgGainUSD也强制标红
            currentAvgGainUsdValue = "\$${(summary['avg_gain_usd'] ?? 0.0).toStringAsFixed(2)}";
            currentAvgGainPctValue = summary['avg_gain_pct']?.toString() ?? "0.00%";

            // Splits: clamp away 0.0 — PieChart crashes on zero-value sections
            List<double> safeSplit(List raw) => raw
                .map((e) => ((e as num).toDouble()).clamp(0.001, double.infinity))
                .toList();

            winSplit        = safeSplit(summary['win_split']);
            avgGainSplitUsd = safeSplit(summary['avg_gain_split_usd']);
            avgGainSplitPct = safeSplit(summary['avg_gain_split_pct']);

            // Profit Factor & Trade Count
            profitFactorValue = summary['profit_factor']?.toString() ?? "—";
            profitFactorSplit = safeSplit(summary['profit_factor_split']);
            tradeCountValue = (summary['sell_count'] ?? 0).toString();

            // 如果没有笔数，把split全设成近似 [0, 1] (灰色) — 不用 0.0 避免 PieChart crash
            if (summary['trade_count'] == 0) {
              winSplit = [0.001, 0.999];
              avgGainSplitUsd = [0.001, 0.999];
              avgGainSplitPct = [0.001, 0.999];
              profitFactorSplit = [0.001, 0.999];
            }

            avgGain = currentAvgGainPctValue; // 替换成 Avg Gain

            // 更新图表变量
            latestTradesData = data['latest_trades'] ?? [];
            last7DaysData = fetchedChartData;
            chartMaxY = maxY * 1.2; // 顶部留出 20% 的视觉空间

            final rawChartData = summary['profit_chart'] as List? ?? [];
            profitChartDataFull = rawChartData.map((item) {
              if (item is Map) {
                return item; // 已经是新版字典，直接过
              } else {
                // ✅ Bug Fix: 使用请求发起时固定的 snapshotTimeLabel，而非 getter 实时值
                return {"date": snapshotTimeLabel, "value": (item as num).toDouble()};
              }
            }).toList();

            isLoading = false;
            _isFirstLoad = false;
          });
        }
      } else {
        // Non-200 response — don't leave isLoading stuck true
        setState(() { isLoading = false; _isFirstLoad = false; hasError = true; });
      }
    } catch (e) {
      debugPrint("网络请求失败: $e");
      setState(() {
        isLoading = false;
        _isFirstLoad = false;
        hasError = true;
      });
    }
  }

  Future<void> _triggerSync() async {
    setState(() => isLoading = true); // 开启转圈动画，锁住 UI

    try {
      // 🌟 调用你写好的 GET 接口
      var response = await http.get(Uri.parse('$kBaseUrl/api/sync'));

      // 无论状态码是 200 还是 500，你的 API 都返回了规范的 JSON
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['status'] == 'success') {
        // 成功提示
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: AppColors.green),
        );
        // 🌟 核心：API 同步完数据库后，自动重新请求大盘数据，瞬间刷新 UI！
        fetchTradingStats();
      } else {
        // 失败提示 (比如你的接口返回了 500)
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步异常: ${data['message']}'), backgroundColor: AppColors.red),
        );
        setState(() => isLoading = false);
      }
    } catch (e) {
      // 根本连不上后端时的兜底报错
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网络连接异常: $e'), backgroundColor: AppColors.red),
      );
      setState(() => isLoading = false);
    }
  }

  // 🌟 3. 动态获取卡片底部的小字标签
  String get timeLabel => timeLabelFor(selectedTimeframe);

  @override
  Widget build(BuildContext context) {
    final pnlColor = isProfit ? AppColors.green : AppColors.red;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: AppColors.text),
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('My Portfolio', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: AppColors.blue), // 科技蓝上传图标
            tooltip: 'Sync Trades',
            onPressed: _triggerSync,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isFirstLoad && isLoading
          ? _buildSkeleton()
          : hasError
              ? ErrorRetryWidget(
                  message: 'Could not reach the server.\nMake sure your backend is running.',
                  onRetry: fetchTradingStats,
                )
              : RefreshIndicator(
                  color: AppColors.blue,
                  backgroundColor: AppColors.card,
                  onRefresh: () async {
                    await fetchTradingStats();
                    _fetchAccount();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),

                          // ── Account balance banner ──
                          if (_acctTotal != null)
                            GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const HoldingsScreen()),
                              ),
                              child: _AccountBanner(
                                total: _acctTotal!,
                                securities: _acctSecurities ?? 0,
                              ),
                            ),
                          if (_acctTotal != null) const SizedBox(height: 16),

                          // 🌟 4. 还原为 Kinfo 极简的纯色巨型圆环
                          // 🌟 替换为四个可拨动的【无底色、动态数据】Donut Chart
                          SizedBox(
                            height: 320,
                            child: PageView(
                              controller: PageController(viewportFraction: 0.9),
                              children: selectedCharts.map(_buildDonutForMetric).toList(),
                            ),
                          ),
                          const SizedBox(height: 30),

                          // 5. Charts 选项卡栏
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text('CHARTS', style: TextStyle(color: AppColors.dim, fontSize: 12, letterSpacing: 1.2)),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _showChartSettings,
                                    child: Icon(Icons.settings_outlined, color: AppColors.dim.withValues(alpha: 0.7), size: 18),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  // 🌟 新增：带点击事件的齿轮图标
                                  GestureDetector(
                                    onTap: _showTimeframeSettings,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8.0, left: 8.0),
                                      child: Icon(Icons.settings_outlined, color: AppColors.dim, size: 18),
                                    ),
                                  ),
                                  // 🌟 动态渲染激活的时间胶囊
                                  ...activeTimeframes.map((tf) => _buildTimeTab(tf)),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 6. 数据指标卡片 (Win% 和 Avg Gain%)
                          Row(
                            children: [
                              Expanded(child: _buildStatCard('Profit', totalPnl, pnlColor)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildStatCard('Win %', winRate, AppColors.green)), // Kinfo 截图里是黄色
                              const SizedBox(width: 12),
                              Expanded(child: _buildStatCard('Avg Gain %', avgGain, pnlColor)),
                            ],
                          ),
                          const SizedBox(height: 30),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Latest Trades', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.text)),

                              // 🌟 激活 See all 点击事件
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const AllTradesScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('See all', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          _buildLatestTradesList(),

                          const SizedBox(height: 30),

                          Text('Last 7 days', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.text)),
                          const SizedBox(height: 16),
                          _buildLast7DaysChart(),
                          const SizedBox(height: 40),

                          _buildProfitLineChart(),
                          const SizedBox(height: 60), // 留出一点底部空白
                        ],
                      ),
                    ),  // Padding
                  ),    // SingleChildScrollView
                ),      // RefreshIndicator
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const ShimmerBox(height: 320, radius: 160),  // donut placeholder
            const SizedBox(height: 30),
            const ShimmerBox(height: 20),
            const SizedBox(height: 16),
            Row(children: const [
              Expanded(child: ShimmerBox(height: 70)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 70)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 70)),
            ]),
            const SizedBox(height: 30),
            const ShimmerBox(height: 24, width: 160, radius: 6),
            const SizedBox(height: 16),
            const ShimmerBox(height: 80),
            const SizedBox(height: 12),
            const ShimmerBox(height: 80),
            const SizedBox(height: 12),
            const ShimmerBox(height: 80),
            const SizedBox(height: 30),
            const ShimmerBox(height: 180),
            const SizedBox(height: 40),
            const ShimmerBox(height: 200),
          ],
        ),
      ),
    );
  }

  // 🌟 处理点击事件：点击后改变选中状态，并重新请求数据
  Widget _buildTimeTab(String text) {
    final isSelected = selectedTimeframe == text;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            selectedTimeframe = text;
            isLoading = true;
          });
          SharedPreferences.getInstance().then((p) => p.setString('portfolio_timeframe', text));
          fetchTradingStats();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.border : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? AppColors.text : AppColors.dim,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ================= 🎛️ 左侧齿轮弹窗：客制化 Donut Chart 槽位 =================
  void _showChartSettings() {
    const allMetrics = [
      {'key': 'profit',        'label': 'Profit',          'sub': 'Total P&L for the period'},
      {'key': 'win_pct',       'label': 'Win %',           'sub': 'Percentage of winning trades'},
      {'key': 'avg_gain_usd',  'label': 'Avg. Gain \$',    'sub': 'Average profit per winning trade'},
      {'key': 'avg_gain_pct',  'label': 'Avg. Gain %',     'sub': 'Average return on each trade'},
      {'key': 'profit_factor', 'label': 'Profit Factor',   'sub': 'Gross profit ÷ gross loss'},
      {'key': 'trades',        'label': 'Trades',          'sub': 'Total number of closed trades'},
    ];

    int activeSlot = 0; // 当前正在编辑的槽位

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 标题 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Row(
                  children: [
                    Text('Customize Charts',
                      style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Color(0xFF666666), size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 槽位选择 Tab ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: List.generate(4, (i) {
                    final active = activeSlot == i;
                    // 取当前槽位选中的 metric label 作为小字提示
                    final metricLabel = allMetrics
                        .firstWhere((m) => m['key'] == selectedCharts[i],
                            orElse: () => {'label': ''})['label']!;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => activeSlot = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.blue.withValues(alpha: 0.15)
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active
                                  ? AppColors.blue
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text('Chart ${i + 1}',
                                style: TextStyle(
                                  color: active ? AppColors.blue : const Color(0xFF666666),
                                  fontSize: 11,
                                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                )),
                              const SizedBox(height: 2),
                              Text(metricLabel,
                                style: const TextStyle(color: Color(0xFF444444), fontSize: 9),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 12),

              // ── 分割线 ──
              const Divider(color: Color(0xFF222222), height: 1),

              // ── 可滚动的 metric 列表 ──
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: allMetrics.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF1E1E1E), height: 1, indent: 20, endIndent: 20),
                  itemBuilder: (_, i) {
                    final m = allMetrics[i];
                    final isSelected = selectedCharts[activeSlot] == m['key'];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setModalState(() => selectedCharts[activeSlot] = m['key']!);
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            // 选中圆点
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.blue
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.blue
                                      : const Color(0xFF444444),
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            // 文字
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m['label']!,
                                  style: TextStyle(
                                    color: isSelected ? AppColors.text : AppColors.dim,
                                    fontSize: 15,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  )),
                                const SizedBox(height: 2),
                                Text(m['sub']!,
                                  style: TextStyle(color: AppColors.dimDark, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= 📋 侧边菜单 Drawer =================
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 头部标题 ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Tools',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  )),
            ),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),

            // ── 菜单项 ───────────────────────────────────────
            _drawerItem(
              icon: Icons.bar_chart_rounded,
              label: 'Sector Performance',
              subtitle: 'US sector ETF heatmap',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SectorsScreen()),
                );
              },
            ),
            _drawerItem(
              icon: Icons.local_offer_rounded,
              label: 'Tag Analytics',
              subtitle: 'Performance breakdown by tag',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TagStatsScreen()));
              },
            ),
            _drawerItem(
              icon: Icons.bar_chart_outlined,
              label: 'Market Breadth',
              subtitle: 'Indices, VIX & sector health',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketBreadthScreen()));
              },
            ),
            _drawerItem(
              icon: Icons.calendar_today_rounded,
              label: 'Earnings Calendar',
              subtitle: 'Upcoming earnings reports',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsCalendarScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.blue, size: 22),
      ),
      title: Text(label,
          style: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle,
          style: TextStyle(color: AppColors.dim, fontSize: 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.dim),
    );
  }

  // ================= ⚙️ 齿轮点击弹窗：客制化时间筛选器 =================
  void _showTimeframeSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card, // Kinfo 质感底色
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        // 使用 StatefulBuilder 让弹窗内部可以独立刷新状态
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 24.0, left: 20, right: 20, bottom: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text('Customize Timeframes', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // 最多选 4 个提示
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Select up to 4  (${activeTimeframes.length}/4)',
                      style: TextStyle(
                        color: activeTimeframes.length >= 4
                            ? AppColors.orange
                            : AppColors.dim,
                        fontSize: 13,
                      ),
                    ),
                  ),

                  // 循环生成多选框
                  ...allTimeframes.map((tf) {
                    final bool isSelected = activeTimeframes.contains(tf);
                    final bool isFull = activeTimeframes.length >= 4 && !isSelected;
                    return CheckboxListTile(
                      title: Text(
                        tf,
                        style: TextStyle(
                          color: isFull ? AppColors.dimDark : AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: isFull
                          ? Text('Max 4 selected',
                              style: TextStyle(color: AppColors.dimDark, fontSize: 11))
                          : null,
                      value: isSelected,
                      activeColor: AppColors.blue,
                      checkColor: Colors.black,
                      side: BorderSide(
                          color: isFull ? const Color(0xFF333333) : AppColors.dimDark),
                      onChanged: isFull
                          ? null // 已满 4 个时禁用未选中项
                          : (bool? val) {
                              if (val == true) {
                                activeTimeframes.add(tf);
                              } else {
                                // 保护机制：至少保留 1 个
                                if (activeTimeframes.length > 1) {
                                  activeTimeframes.remove(tf);
                                }
                              }
                              // 保证顺序
                              activeTimeframes.sort((a, b) =>
                                  allTimeframes.indexOf(a)
                                      .compareTo(allTimeframes.indexOf(b)));
                              SharedPreferences.getInstance().then((p) =>
                                  p.setStringList('portfolio_active_timeframes', activeTimeframes));
                              setModalState(() {});
                              setState(() {});
                            },
                    );
                  }),
                ],
                ),   // Column
              ),     // SingleChildScrollView
            );       // SafeArea
          }
        );
      },
    );
  }

  // 🌟 让卡片底部的 "1 Month" / "All Time" 小字跟着动态变化
  Widget _buildStatCard(String title, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: AppColors.dim, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(timeLabel, style: TextStyle(color: AppColors.dimDark, fontSize: 10)), // 动态小字
        ],
      ),
    );
  }

  // ================= 📊 构建 Last 7 Days 柱状图 =================
  Widget _buildLast7DaysChart() {
    if (last7DaysData.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 180,
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 10, right: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: chartMaxY,
          minY: -chartMaxY, // 上下对称，保证 0 轴绝对居中
          barTouchData: BarTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),

          // 渲染底部的星期 (Tue, Wed...)
          titlesData: FlTitlesData(
            show: true,
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  int index = value.toInt();
                  if (index < 0 || index >= last7DaysData.length) return const SizedBox();
                  String weekday = last7DaysData[index]['weekday'];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(weekday, style: TextStyle(color: AppColors.dim, fontSize: 12)),
                  );
                },
              ),
            ),
          ),

          // 根据真实的 PnL 生成柱子
          barGroups: List.generate(last7DaysData.length, (index) {
            final dayData = last7DaysData[index];
            final double pnl = (dayData['pnl'] as num).toDouble();
            final bool isProfit = dayData['isProfit'];

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: pnl,
                  color: isProfit ? AppColors.green : AppColors.red,
                  width: 14,
                  // 盈利柱圆角在顶，亏损柱圆角在底
                  borderRadius: isProfit
                    ? const BorderRadius.vertical(top: Radius.circular(4))
                    : const BorderRadius.vertical(bottom: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ================= 📈 动态交互渐变 Profit 曲线图表 =================
  Widget _buildProfitLineChart() {
    if (profitChartDataFull.isEmpty) return const SizedBox.shrink();

    // 解析出只包含数值的数组用于算图表高度
    List<FlSpot> spots = [];
    List<double> valuesOnly = [];
    for (int i = 0; i < profitChartDataFull.length; i++) {
      double val = (profitChartDataFull[i]['value'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), val));
      valuesOnly.add(val);
    }

    double minY = valuesOnly.reduce((a, b) => a < b ? a : b);
    double maxY = valuesOnly.reduce((a, b) => a > b ? a : b);
    double range = maxY - minY;
    if (range == 0) range = 10;
    double topY = maxY + range * 0.15;
    double botY = minY - range * 0.15;

    // 🌟 动态判定要显示的标题文字 (如果手指触摸了，就显示触摸点的数据，否则显示大盘原数据)
    final String displayDate = touchedDate ?? timeLabel;
    final String displayProfit = touchedProfitValue ?? currentPnlValue;
    // 动态决定数字颜色：原状态跟大盘走，触摸状态时 >0 绿，<0 红，=0 白
    Color profitColor = AppColors.text;
    if (touchedProfitRaw != null) {
      // 触摸时：大于 0 绿，小于 0 红
      profitColor = touchedProfitRaw! > 0 ? AppColors.green : (touchedProfitRaw! < 0 ? AppColors.red : AppColors.text);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Profit', style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  // 🌟 这里！如果有触摸，它会被替换成具体日期 (如 Mar 15, 2026)
                  Text(displayDate, style: TextStyle(color: AppColors.dim, fontSize: 13)),
                ],
              ),
              // 🌟 这里！如果有触摸，它会被替换成触摸点的精确累积盈亏
              Text(displayProfit, style: TextStyle(color: profitColor, fontSize: 26, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 160,
            width: double.infinity,
            child: LineChart(
              LineChartData(
                minX: 0, maxX: (spots.length - 1).toDouble(),
                minY: botY, maxY: topY,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),

                // 🌟 核心引擎：激活触摸互动！
                lineTouchData: LineTouchData(
                  enabled: true,
                  // 1. 定义触摸时那根性感的垂直追踪线和焦点圆圈
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        const FlLine(color: Colors.white38, strokeWidth: 1.5, dashArray: [4, 4]), // 垂直虚线
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                            radius: 5,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: AppColors.blue, // 外蓝内白的准星
                          ),
                        ),
                      );
                    }).toList();
                  },
                  // 2. 隐藏原生的悬浮气泡框 (因为我们要把字写在卡片顶部)
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => null).toList(),
                  ),
                  // 3. 侦测手指动作，实时更新坐标
                  touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                    if (!event.isInterestedForInteractions || touchResponse == null || touchResponse.lineBarSpots == null) {
                      // 手指离开屏幕，清除状态，恢复默认 UI
                      setState(() {
                        touchedDate = null;
                        touchedProfitValue = null;
                        touchedProfitRaw = null;
                      });
                      return;
                    }

                    // 手指正在拖动，获取数据点并更新顶部文字
                    final spot = touchResponse.lineBarSpots!.first;
                    final index = spot.spotIndex;
                    if (index >= 0 && index < profitChartDataFull.length) {
                      final dataPoint = profitChartDataFull[index];
                      final double pnl = (dataPoint['value'] as num).toDouble();
                      setState(() {
                        touchedDate = dataPoint['date'];
                        touchedProfitRaw = pnl;
                        // 调用你封装的 NumberFormatter 来格式化高亮金额
                        String formattedPnl = NumberFormatter.format(pnl.abs());
                        touchedProfitValue = pnl == 0 ? '\$0.00' : '${pnl > 0 ? '+' : '-'}\$$formattedPnl';
                      });
                    }
                  },
                ),

                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    gradient: const LinearGradient(
                      colors: [AppColors.red, AppColors.blue, AppColors.green],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.green.withValues(alpha: 0.18),
                          AppColors.blue.withValues(alpha: 0.06),
                          AppColors.red.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _showTimeframeSettings,
                child: Icon(Icons.settings_outlined, color: AppColors.dimDark, size: 16),
              ),
              const SizedBox(width: 4),
              ...activeTimeframes.map((tf) => _buildTimeTab(tf)),
            ],
          ),
        ],
      ),
    );
  }

  // ================= 📜 构建 Latest Trades 列表 =================
  Widget _buildLatestTradesList() {
    if (latestTradesData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: EmptyStateWidget(
          icon: Icons.swap_horiz_outlined,
          title: 'No trades yet',
          subtitle: 'Tap the sync button to import your trades.',
        ),
      );
    }

    return Column(
      children: latestTradesData.map((trade) => TradeCardWidget(trade: trade)).toList(),
    );
  }

  // ================= 🎛️ 根据 metric key 动态构建对应的 Donut Chart =================
  Widget _buildDonutForMetric(String key) {
    switch (key) {
      case 'profit':
        return _buildDonutChartCard(
          title: 'Profit', subtitle: timeLabel,
          value: currentPnlValue, valueColor: currentPnlColor,
          sections: [PieChartSectionData(value: 1.0, color: currentPnlColor, radius: 40, showTitle: false)],
        );
      case 'win_pct':
        return _buildDonutChartCard(
          title: 'Win %', subtitle: timeLabel,
          value: currentWinRateValue, valueColor: AppColors.text,
          sections: [
            PieChartSectionData(value: winSplit[0], color: AppColors.green, radius: 40, showTitle: false),
            PieChartSectionData(value: winSplit[1], color: AppColors.red, radius: 40, showTitle: false),
          ],
        );
      case 'avg_gain_usd':
        return _buildDonutChartCard(
          title: 'Avg. Gain \$', subtitle: timeLabel,
          value: currentAvgGainUsdValue, valueColor: AppColors.text,
          sections: [
            PieChartSectionData(value: avgGainSplitUsd[0], color: AppColors.green, radius: 40, showTitle: false),
            PieChartSectionData(value: avgGainSplitUsd[1], color: AppColors.red, radius: 40, showTitle: false),
          ],
        );
      case 'avg_gain_pct':
        return _buildDonutChartCard(
          title: 'Avg. Gain %', subtitle: timeLabel,
          value: currentAvgGainPctValue, valueColor: AppColors.text,
          sections: [
            PieChartSectionData(value: avgGainSplitPct[0], color: AppColors.green, radius: 40, showTitle: false),
            PieChartSectionData(value: avgGainSplitPct[1], color: AppColors.red, radius: 40, showTitle: false),
          ],
        );
      case 'profit_factor':
        return _buildDonutChartCard(
          title: 'Profit Factor', subtitle: timeLabel,
          value: profitFactorValue, valueColor: AppColors.text,
          sections: [
            PieChartSectionData(value: profitFactorSplit[0], color: AppColors.green, radius: 40, showTitle: false),
            PieChartSectionData(value: profitFactorSplit[1], color: AppColors.red, radius: 40, showTitle: false),
          ],
        );
      case 'trades':
        return _buildDonutChartCard(
          title: 'Trades', subtitle: timeLabel,
          value: tradeCountValue, valueColor: AppColors.text,
          sections: [
            PieChartSectionData(value: winSplit[0], color: AppColors.green, radius: 40, showTitle: false),
            PieChartSectionData(value: winSplit[1], color: AppColors.red, radius: 40, showTitle: false),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ================= 📊 构建无底色、动态数据的 Donut Chart卡片 =================
  // ✅ Bug Fix: 从类外游离的顶层函数移入 _PortfolioScreenState，
  //    使其成为合法的实例方法，可正确访问 State 字段与 context。
  Widget _buildDonutChartCard({
    required String title,
    required String subtitle,
    required String value,
    required Color valueColor,
    required List<PieChartSectionData> sections,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 100,
                startDegreeOffset: 270,
                sections: sections,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: AppColors.dim, fontSize: 13)),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account balance banner
// ─────────────────────────────────────────────────────────────────────────────
class _AccountBanner extends StatelessWidget {
  final double total, securities;
  const _AccountBanner({
    required this.total,
    required this.securities,
  });

  String _fmt(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000)    return '\$${(v / 1000).toStringAsFixed(1)}K';
    return '\$${v.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Total assets — main number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account Value',
                    style: TextStyle(color: AppColors.dim, fontSize: 11, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  _fmt(total),
                  style: TextStyle(
                    color: AppColors.text, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Divider
          Container(width: 0.5, height: 36, color: AppColors.border),
          const SizedBox(width: 16),
          // Invested amount
          _SubStat(label: 'Invested', value: _fmt(securities)),
        ],
      ),
    );
  }
}

class _SubStat extends StatelessWidget {
  final String label, value;
  const _SubStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.dim, fontSize: 11)),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
