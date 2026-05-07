import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_1/constants.dart';

// ================= 交易详情页 (备注 + 截图版) =================
// pubspec.yaml 需添加: image_picker: ^1.1.2
class TradeDetailScreen extends StatefulWidget {
  final dynamic trade;
  const TradeDetailScreen({super.key, required this.trade});

  @override
  State<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

class _TradeDetailScreenState extends State<TradeDetailScreen> {
  // ── 备注状态 ──────────────────────────────────────────────
  String _note = '';
  List<String> _imagePaths = [];
  bool _isSavingNote  = false;

  @override
  void initState() {
    super.initState();
    // 用后端已返回的初始值填充（减少一次网络请求）
    _note        = widget.trade['note']        as String? ?? '';
    _imagePaths  = List<String>.from(widget.trade['image_paths'] as List? ?? []);
  }

  // ── 保存备注 ──────────────────────────────────────────────
  Future<void> _saveNote(String newNote) async {
    final tradeId = widget.trade['trade_id'] as String? ?? '';
    if (tradeId.isEmpty) return;
    setState(() => _isSavingNote = true);
    try {
      await http.post(
        Uri.parse('$kBaseUrl/api/notes/$tradeId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'note': newNote}),
      );
      setState(() => _note = newNote);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: AppColors.red),
      );
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  // ── 上传截图 ──────────────────────────────────────────────
  Future<void> _pickAndUploadImage() async {
    final tradeId = widget.trade['trade_id'] as String? ?? '';
    if (tradeId.isEmpty) return;

    // 让用户选择来源
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Add Screenshot', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF4DA1FF)),
            title: Text('Photo Library', style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4DA1FF)),
            title: Text('Camera', style: TextStyle(color: AppColors.text)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    try {
      final request = http.MultipartRequest(
        'POST', Uri.parse('$kBaseUrl/api/upload_image/$tradeId'),
      );
      request.files.add(await http.MultipartFile.fromPath('image', picked.path));
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _imagePaths.add(data['filename'] as String));
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  // ── 删除截图 ──────────────────────────────────────────────
  Future<void> _deleteImage(String filename) async {
    final tradeId = widget.trade['trade_id'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete screenshot?', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF453A))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await http.delete(Uri.parse('$kBaseUrl/api/delete_image/$tradeId/$filename'));
      setState(() => _imagePaths.remove(filename));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: AppColors.red),
      );
    }
  }

  // ── 编辑备注底部弹窗 ──────────────────────────────────────
  void _showNoteEditor() {
    final controller = TextEditingController(text: _note);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 24, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Trade Notes', style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _saveNote(controller.text.trim());
              },
              child: _isSavingNote
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4DA1FF)))
                : const Text('Save', style: TextStyle(color: Color(0xFF4DA1FF), fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 8,
            autofocus: true,
            style: TextStyle(color: AppColors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'What happened in this trade? Entry reason, mistakes, lessons...',
              hintStyle: const TextStyle(color: Color(0xFF555555)),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 全屏预览截图 ───────────────────────────────────────────
  void _showFullScreenImage(String filename) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          backgroundColor: AppColors.darkBg,
          leading: IconButton(
            icon: Icon(Icons.close, color: AppColors.text),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFFF453A)),
              onPressed: () async {
                Navigator.pop(context);
                await _deleteImage(filename);
              },
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(
              '$kBaseUrl/api/images/$filename',
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator(color: Color(0xFF4DA1FF))),
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Color(0xFF888888), size: 64),
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final String rawTicker = widget.trade['ticker'];
    String optionInfo = '';
    final match = RegExp(r'^([A-Za-z]+)(\d.*)$').firstMatch(rawTicker);
    if (match != null) {
      final optMatch = RegExp(r'^(\d{6})([CP])(\d+)$').firstMatch(match.group(2)!);
      if (optMatch != null) {
        double strike = double.parse(optMatch.group(3)!) / 1000;
        optionInfo = '${optMatch.group(1)} ${optMatch.group(2) == 'C' ? 'Call' : 'Put'} \$${strike.toStringAsFixed(strike.truncateToDouble() == strike ? 0 : 2)}';
      } else {
        optionInfo = match.group(2)!;
      }
    }
    final String ticker     = widget.trade['ticker'];
    final double pnl        = (widget.trade['pnl'] as num).toDouble();
    final String pct        = widget.trade['pct'];
    final bool   isProfit   = widget.trade['isProfit'];
    final String tradeType  = widget.trade['trade_type'];
    final String enterTime  = widget.trade['enter_time']  ?? 'N/A';
    final String exitTime   = widget.trade['exit_time']   ?? 'N/A';
    final String holdingTime= widget.trade['holding_time']?? 'N/A';
    final String tradeCount = widget.trade['trade_count'] ?? '0';
    final List<dynamic> transactions = widget.trade['transactions'] ?? [];

    final colorText = isProfit ? AppColors.green : AppColors.red;
    final String pnlText = pnl > 0 ? '+\$${pnl.toStringAsFixed(2)}' : '-\$${pnl.abs().toStringAsFixed(2)}';

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trade', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Text(ticker, style: const TextStyle(color: Color(0xFF888888), fontSize: 18, fontWeight: FontWeight.bold)),
              if (optionInfo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(optionInfo, style: const TextStyle(color: Color(0xFF4DA1FF), fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              const SizedBox(height: 8),
              Text(pnlText, style: TextStyle(color: colorText, fontSize: 48, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('($pct)', style: TextStyle(color: colorText, fontSize: 16)),
              const SizedBox(height: 40),

              // ── Transactions ─────────────────────────────────────
              const Align(alignment: Alignment.centerLeft, child: Text('Transactions', style: TextStyle(color: Color(0xFF888888), fontSize: 14))),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  ...transactions.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _buildTransactionRow(t['date'], t['action'], t['qty'], t['price']),
                  )),
                  const Divider(color: Color(0xFF2C2C2E), height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Net gain', style: TextStyle(color: AppColors.text, fontSize: 14)),
                    Text(pnlText, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                ]),
              ),
              const SizedBox(height: 30),

              // ── Trade information ─────────────────────────────────
              const Align(alignment: Alignment.centerLeft, child: Text('Trade information', style: TextStyle(color: Color(0xFF888888), fontSize: 14))),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: _buildInfoColumn('Type', tradeType)),
                    Expanded(child: _buildInfoColumn('Shares/Contracts', ticker.contains(RegExp(r'[0-9]')) ? 'Contracts' : 'Shares')),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _buildInfoColumn('Enter', enterTime)),
                    Expanded(child: _buildInfoColumn('Exit', exitTime)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _buildInfoColumn('Holding time', holdingTime)),
                    Expanded(child: _buildInfoColumn('Trades', tradeCount)),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _buildInfoColumn('Asset Class', ticker.contains(RegExp(r'[0-9]')) ? 'Options' : 'Equity')),
                  ]),
                ]),
              ),
              const SizedBox(height: 30),

              // ── Notes & Screenshots ───────────────────────────────
              _buildNotesSection(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── 备注 + 截图 区块 ──────────────────────────────────────
  Widget _buildNotesSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 标题行
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Notes', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
        GestureDetector(
          onTap: _showNoteEditor,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: const [
              Icon(Icons.edit_outlined, color: Color(0xFF4DA1FF), size: 13),
              SizedBox(width: 5),
              Text('Edit', style: TextStyle(color: Color(0xFF4DA1FF), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      // 备注文字卡片
      GestureDetector(
        onTap: _showNoteEditor,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _note.isEmpty ? AppColors.border : AppColors.blue.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: _note.isEmpty
            ? const Text(
                'Tap to add trade notes, entry reason, or lessons learned...',
                style: TextStyle(color: Color(0xFF555555), fontSize: 14, height: 1.5),
              )
            : Text(
                _note,
                style: TextStyle(color: AppColors.text, fontSize: 14, height: 1.6),
              ),
        ),
      ),
      const SizedBox(height: 20),

      // 截图标题行
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          'Screenshots${_imagePaths.isNotEmpty ? ' (${_imagePaths.length})' : ''}',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
        ),
        GestureDetector(
          onTap: _pickAndUploadImage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: const [
              Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF30D158), size: 14),
              SizedBox(width: 5),
              Text('Add', style: TextStyle(color: Color(0xFF30D158), fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),

      // 截图缩略图网格
      if (_imagePaths.isEmpty)
        GestureDetector(
          onTap: _pickAndUploadImage,
          child: Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF444444), size: 28),
              SizedBox(height: 6),
              Text('Add chart screenshot', style: TextStyle(color: Color(0xFF555555), fontSize: 13)),
            ]),
          ),
        )
      else
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _imagePaths.length + 1, // +1 for the add button
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              // 最后一格：添加按钮
              if (i == _imagePaths.length) {
                return GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    width: 100,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add, color: Color(0xFF555555), size: 24),
                      SizedBox(height: 4),
                      Text('Add', style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
                    ]),
                  ),
                );
              }
              // 截图缩略图
              final filename = _imagePaths[i];
              return GestureDetector(
                onTap:      () => _showFullScreenImage(filename),
                onLongPress:() => _deleteImage(filename),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    '$kBaseUrl/api/images/$filename',
                    width: 100, height: 120,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : Container(
                          width: 100, color: AppColors.card,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4DA1FF))),
                        ),
                    errorBuilder: (_, _, _) => Container(
                      width: 100, color: AppColors.surface2,
                      child: const Icon(Icons.broken_image, color: Color(0xFF888888)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildTransactionRow(String date, String action, String qty, String price) {
    final actionColor = action == 'BUY' ? AppColors.green : AppColors.red;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      SizedBox(width: 120, child: Text(date, style: TextStyle(color: AppColors.text, fontSize: 14))),
      SizedBox(width: 50, child: Text(action, style: TextStyle(color: actionColor, fontSize: 14, fontWeight: FontWeight.bold))),
      SizedBox(width: 30, child: Text(qty, textAlign: TextAlign.right, style: TextStyle(color: AppColors.text, fontSize: 14))),
      Expanded(child: Text(price, textAlign: TextAlign.right, style: TextStyle(color: AppColors.text, fontSize: 14))),
    ]);
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
    ]);
  }
}
