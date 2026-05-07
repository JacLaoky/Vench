import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/shimmer_box.dart';
import 'package:flutter_application_1/widgets/error_retry_widget.dart';

class EarningsCalendarScreen extends StatefulWidget {
  const EarningsCalendarScreen({super.key});

  @override
  State<EarningsCalendarScreen> createState() => _EarningsCalendarScreenState();
}

class _EarningsCalendarScreenState extends State<EarningsCalendarScreen> {
  bool _loading = true;
  bool _error   = false;

  List<dynamic> _data = []; // list of {date, day_label, events: [{ticker, time}]}

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error   = false;
    });
    try {
      final res = await http.get(
        Uri.parse('$kBaseUrl/api/earnings_calendar'),
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body['status'] == 'success') {
          setState(() {
            _data    = body['data'] as List;
            _loading = false;
          });
          return;
        }
      }
      setState(() { _loading = false; _error = true; });
    } catch (_) {
      setState(() { _loading = false; _error = true; });
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
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Earnings Calendar',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildSkeleton();
    if (_error) {
      return ErrorRetryWidget(
        message: 'Could not load earnings data.\nMake sure your backend is running.',
        onRetry: _fetch,
      );
    }

    return RefreshIndicator(
      color: AppColors.blue,
      backgroundColor: AppColors.card,
      onRefresh: _fetch,
      child: _data.isEmpty
          ? Center(
              child: Text(
                'No upcoming earnings',
                style: TextStyle(color: AppColors.dim, fontSize: 15),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: _data.length,
              itemBuilder: (_, i) {
                final group  = _data[i];
                final label  = group['day_label'] as String;
                final events = group['events'] as List;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: AppColors.dim,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ...events.map((ev) => _EarningsRow(
                          ticker: ev['ticker'] as String,
                          time:   ev['time'] as String,
                        )),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const ShimmerBox(height: 11, width: 100, radius: 4),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
          const SizedBox(height: 16),
          const ShimmerBox(height: 11, width: 100, radius: 4),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
          const SizedBox(height: 16),
          const ShimmerBox(height: 11, width: 100, radius: 4),
          const SizedBox(height: 8),
          const ShimmerBox(height: 52),
        ],
      ),
    );
  }
}

// ── Individual Earnings Row ───────────────────────────────────────────────────

class _EarningsRow extends StatelessWidget {
  final String ticker;
  final String time;

  const _EarningsRow({required this.ticker, required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ticker,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _TimeBadge(time: time),
        ],
      ),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  final String time;
  const _TimeBadge({required this.time});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;

    switch (time) {
      case 'BMO':
        bgColor   = AppColors.blue.withValues(alpha: 0.18);
        textColor = AppColors.blue;
      case 'AMC':
        bgColor   = const Color(0xFF9C27B0).withValues(alpha: 0.18);
        textColor = const Color(0xFF9C27B0);
      default:
        bgColor   = AppColors.border.withValues(alpha: 0.5);
        textColor = AppColors.dim;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        time,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
