import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../theme/app_theme.dart';

class FlagImage extends StatelessWidget {
  final String logoUrl;
  final double width;
  final double height;

  const FlagImage({
    super.key,
    required this.logoUrl,
    this.width = 44,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        width: width,
        height: height,
        fit: BoxFit.contain,
        placeholder: (_, __) => Container(
          width: width, height: height,
          decoration: BoxDecoration(
            color: AppColors.cardRaised,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: width, height: height,
          color: AppColors.cardRaised,
          child: const Icon(Icons.flag, size: 16, color: AppColors.text3),
        ),
      ),
    );
  }
}

class StatusBadge extends StatefulWidget {
  final MatchStatus status;
  final String? clock;
  final DateTime kickoff;

  const StatusBadge({
    super.key,
    required this.status,
    this.clock,
    required this.kickoff,
  });

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.status) {
      case MatchStatus.live:
        return FadeTransition(
          opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.redDim,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.red.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'LIVE ${widget.clock ?? ''}',
                  style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );

      case MatchStatus.finished:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.cardRaised,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text('FT',
            style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w700)),
        );

      case MatchStatus.upcoming:
        final now = DateTime.now();
        final diff = widget.kickoff.difference(now);
        // Kickoff passed but ESPN hasn't marked live yet — show LOCKED
        if (diff.isNegative) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.cardRaised,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text('🔒 LOCKED',
              style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w700)),
          );
        }
        String label;
        if (diff.inMinutes < 60) {
          label = '${diff.inMinutes}m';
        } else if (diff.inHours < 24) {
          label = '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
        } else {
          final hh = widget.kickoff.hour.toString().padLeft(2, '0');
          final mm = widget.kickoff.minute.toString().padLeft(2, '0');
          label = '${widget.kickoff.day}/${widget.kickoff.month} · $hh:$mm';
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x1F2563EB),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.blue.withOpacity(0.25)),
          ),
          child: Text(label,
            style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.w700)),
        );
    }
  }
}

class ResultChip extends StatelessWidget {
  final PredictionResult result;
  final int? points;
  final bool hasPenBonus;

  const ResultChip({super.key, required this.result, this.points, this.hasPenBonus = false});

  @override
  Widget build(BuildContext context) {
    Color bg, fg, borderColor;
    String label;
    String prefix;

    switch (result) {
      case PredictionResult.exact:
        bg = AppColors.greenDim; fg = AppColors.green;
        borderColor = AppColors.green.withOpacity(0.2);
        label = 'Exact'; prefix = '✦';
        break;
      case PredictionResult.correctPlusOne:
        bg = AppColors.goldDim; fg = AppColors.gold;
        borderColor = AppColors.gold.withOpacity(0.2);
        label = 'Correct +1'; prefix = '✓~';
        break;
      case PredictionResult.correctResult:
        bg = AppColors.goldDim; fg = AppColors.gold;
        borderColor = AppColors.gold.withOpacity(0.2);
        label = 'Correct Result'; prefix = '✓';
        break;
      case PredictionResult.oneScore:
        bg = AppColors.orangeDim; fg = AppColors.orange;
        borderColor = AppColors.orange.withOpacity(0.2);
        label = 'One Score'; prefix = '~';
        break;
      case PredictionResult.wrong:
        bg = AppColors.redDim; fg = AppColors.red;
        borderColor = AppColors.red.withOpacity(0.2);
        label = 'Wrong'; prefix = '✗';
        break;
      case PredictionResult.pending:
        bg = AppColors.cardRaised; fg = AppColors.text3;
        borderColor = AppColors.border;
        label = 'Pending'; prefix = '·';
        break;
    }

    final pts = points ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        '$prefix $label${result != PredictionResult.pending ? ' +$pts pts' : ''}',
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
