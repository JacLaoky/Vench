import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/constants.dart';
import 'package:flutter_application_1/widgets/tag_chip.dart';

// Predefined tag suggestions
const kTagSuggestions = [
  'Breakout', 'Breakdown', 'Trend Follow', 'Reversal',
  'Earnings', 'Support', 'Resistance', 'Gap Fill',
  'FOMO', 'Revenge', 'Oversize', 'Perfect Entry',
  'Early Exit', 'Late Entry', 'News Play', 'Scalp',
];

Future<void> showTagEditor(
  BuildContext context,
  dynamic trade,
  VoidCallback? onUpdated,
) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TagEditorSheet(trade: trade, onUpdated: onUpdated),
  );
}

class _TagEditorSheet extends StatefulWidget {
  final dynamic trade;
  final VoidCallback? onUpdated;
  const _TagEditorSheet({required this.trade, this.onUpdated});

  @override
  State<_TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<_TagEditorSheet> {
  late List<String> _tags;
  bool _saving = false;
  final _ctrl = TextEditingController();
  final _stopCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final raw = widget.trade['tags'];
    _tags = raw is List ? List<String>.from(raw) : [];
    // Pre-populate stop price if it exists
    final existingStop = (widget.trade['stop_price'] as num?)?.toDouble();
    if (existingStop != null) {
      _stopCtrl.text = existingStop.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _stopCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id = widget.trade['trade_id']?.toString() ?? widget.trade['id']?.toString() ?? '';
      await http.patch(
        Uri.parse('$kBaseUrl/api/trades/$id/tags'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tags': _tags}),
      );

      // Save stop price if a position_id exists and stop price was entered
      final positionId = widget.trade['position_id'] as String?;
      final stopVal = double.tryParse(_stopCtrl.text);
      if (positionId != null && stopVal != null && stopVal > 0) {
        final ticker = widget.trade['ticker']?.toString() ?? '';
        await http.patch(
          Uri.parse('$kBaseUrl/api/positions/$positionId/stop'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'stop_price': stopVal, 'ticker': ticker}),
        );
      }

      widget.onUpdated?.call();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _saving = false);
    }
  }

  void _addTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    setState(() => _tags.add(t));
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Edit Tags',
              style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),

          // Current tags
          if (_tags.isNotEmpty) ...[
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _tags.map((t) => TagChip(
                tag: t,
                selected: true,
                onRemove: () => setState(() => _tags.remove(t)),
              )).toList(),
            ),
            const SizedBox(height: 14),
          ],

          // Custom input
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Add custom tag...',
                  hintStyle: TextStyle(color: AppColors.dim),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
                onSubmitted: _addTag,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _addTag(_ctrl.text),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_rounded, color: AppColors.blue, size: 20),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // Suggestions
          Text('Suggestions', style: TextStyle(color: AppColors.dim, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: kTagSuggestions
                .where((t) => !_tags.contains(t))
                .map((t) => TagChip(
                  tag: t,
                  onTap: () => _addTag(t),
                ))
                .toList(),
          ),
          const SizedBox(height: 20),

          // Stop Price section (only shown when a position_id is available)
          if (widget.trade['position_id'] != null) ...[
            Text('Stop Price', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _stopCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. 780.00',
                hintStyle: TextStyle(color: AppColors.dim),
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: AppColors.dim),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
