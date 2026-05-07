import 'package:flutter/material.dart';

/// A pulsing shimmer placeholder — drop-in replacement for loading spinners.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-2.0 + _anim.value * 4, 0),
            end: Alignment(-1.0 + _anim.value * 4, 0),
            colors: const [
              Color(0xFF1A1A1C),
              Color(0xFF2C2C2E),
              Color(0xFF1A1A1C),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quick skeleton card made of stacked ShimmerBox rows.
class ShimmerCard extends StatelessWidget {
  final int rows;
  const ShimmerCard({super.key, this.rows = 3});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13151A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(height: 18, radius: 6, width: 140),
          const SizedBox(height: 12),
          for (int i = 0; i < rows; i++) ...[
            ShimmerBox(height: 13, radius: 4),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
