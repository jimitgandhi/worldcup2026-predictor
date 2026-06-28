import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/match_widgets.dart';
import '../widgets/shimmer_loading.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final authService = AuthService();
    final user = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<UserModel?>(
      stream: firestore.currentUserStream(user.uid),
      builder: (context, snap) {
        final u = snap.data;

        return CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(child: _ProfileHeader(user: user, model: u)),
            // Stats
            if (u != null) ...[
              SliverToBoxAdapter(child: _StatGrid(model: u)),
              SliverToBoxAdapter(child: _BreakdownBar(model: u)),
            ],
            // Recent predictions header + share button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    const Text('MY UPCOMING PICKS',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 1.8, color: AppColors.text3,
                      )),
                    const Spacer(),
                    // Share button — populated after predictions load
                  ],
                ),
              ),
            ),
            StreamBuilder<List<Prediction>>(
              stream: firestore.userPredictionsStream(user.uid),
              builder: (context, predSnap) {
                if (!predSnap.hasData) {
                  return const SliverToBoxAdapter(child: ShimmerList(count: 3));
                }
                // Show predictions for today and future matches (start of local day)
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final preds = predSnap.data!
                    .where((p) => p.kickoffTime != null && !p.kickoffTime!.isBefore(today))
                    .toList()
                  ..sort((a, b) => a.kickoffTime!.compareTo(b.kickoffTime!));

                if (preds.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: const Center(
                        child: Text('No upcoming predictions yet',
                          style: TextStyle(color: AppColors.text3)),
                      ),
                    ),
                  );
                }
                return SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Share banner (disabled on web)
                      if (!kIsWeb)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: GestureDetector(
                            onTap: () => _sharePredictions(preds),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.cardRaised,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.share_outlined, size: 15, color: AppColors.text2),
                                  SizedBox(width: 6),
                                  Text('Share my picks',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                        color: AppColors.text2)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Prediction rows
                      ...preds.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _PredRow(prediction: p),
                      )),
                    ],
                  ),
                );
              },
            ),
            // Sign out
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: GestureDetector(
                  onTap: () async => authService.signOut(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.red.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Sign out',
                      style: TextStyle(
                        color: Color(0xFFF87171),
                        fontSize: 13, fontWeight: FontWeight.w700,
                      )),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final User user;
  final UserModel? model;
  const _ProfileHeader({required this.user, required this.model});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white12, width: 2),
            ),
            child: user.photoURL != null
              ? ClipOval(child: CachedNetworkImage(imageUrl: user.photoURL!, fit: BoxFit.cover))
              : Center(
                  child: Text(
                    _initials(user.displayName ?? 'P'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName ?? 'Player',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                Text(user.email ?? '',
                  style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                const SizedBox(height: 6),
                if (model != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.goldDim,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                    ),
                    child: Text(
                      model!.rank > 0 ? 'Rank #${model!.rank} · Global' : 'Unranked',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _StatGrid extends StatelessWidget {
  final UserModel model;
  const _StatGrid({required this.model});

  @override
  Widget build(BuildContext context) {
    final pct = model.predictionsCount > 0
      ? '${(model.accuracy * 100).round()}%'
      : '—';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _StatTile(value: '${model.totalPoints}', label: 'Total pts', color: AppColors.gold),
          const SizedBox(width: 8),
          _StatTile(value: '${model.predictionsCount}', label: 'Predicted', color: AppColors.text),
          const SizedBox(width: 8),
          _StatTile(value: pct, label: 'Result Accuracy', color: AppColors.green),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatTile({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.5)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.8, color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  final UserModel model;
  const _BreakdownBar({required this.model});

  @override
  Widget build(BuildContext context) {
    final total = model.predictionsCount;
    double frac(int n) => total > 0 ? n / total : 0;
    final wrongCount = total - model.exactCount - model.correctPlusOneCount
        - model.correctResultCount - model.oneScoreCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PREDICTION BREAKDOWN',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.text2, letterSpacing: 0.3)),
          const SizedBox(height: 12),
          _Bar('Exact Score',     AppColors.green,  frac(model.exactCount),          model.exactCount),
          const SizedBox(height: 8),
          _Bar('Almost Correct',  AppColors.gold,   frac(model.correctPlusOneCount),  model.correctPlusOneCount),
          const SizedBox(height: 8),
          _Bar('Correct Result',  AppColors.gold,   frac(model.correctResultCount),   model.correctResultCount),
          const SizedBox(height: 8),
          _Bar('One Score',       AppColors.orange, frac(model.oneScoreCount),        model.oneScoreCount),
          const SizedBox(height: 8),
          _Bar('Wrong',           AppColors.text3,  frac(wrongCount.clamp(0, total)), wrongCount.clamp(0, total)),
          if (model.penBonusCount > 0) ...[
            const SizedBox(height: 8),
            _Bar('⚡ Pen Bonus',   const Color(0xFF7C3AED), frac(model.penBonusCount), model.penBonusCount),
          ],
        ],
      ),
    );
  }

  Widget _Bar(String label, Color color, double frac, int count) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, c) => Stack(
            children: [
              Container(height: 6, decoration: BoxDecoration(
                color: AppColors.cardRaised, borderRadius: BorderRadius.circular(100))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                height: 6, width: c.maxWidth * frac,
                decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(100)),
              ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 20,
          child: Text('$count',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

String _getFlag(String team) {
  // Convert country name to flag emoji
  final flags = {
    'USA': '🇺🇸', 'United States': '🇺🇸',
    'Mexico': '🇲🇽', 'Canada': '🇨🇦',
    'Argentina': '🇦🇷', 'Brazil': '🇧🇷', 'Uruguay': '🇺🇾', 'Chile': '🇨🇱',
    'Colombia': '🇨🇴', 'Ecuador': '🇪🇨', 'Paraguay': '🇵🇾', 'Peru': '🇵🇪',
    'Venezuela': '🇻🇪', 'Bolivia': '🇧🇴',
    'England': '🏴󠁧󠁢󠁥󠁮󠁧󠁿', 'Spain': '🇪🇸', 'Germany': '🇩🇪', 'France': '🇫🇷',
    'Portugal': '🇵🇹', 'Netherlands': '🇳🇱', 'Italy': '🇮🇹', 'Belgium': '🇧🇪',
    'Croatia': '🇭🇷', 'Denmark': '🇩🇰', 'Switzerland': '🇨🇭', 'Poland': '🇵🇱',
    'Serbia': '🇷🇸', 'Austria': '🇦🇹', 'Czech Republic': '🇨🇿', 'Sweden': '🇸🇪',
    'Wales': '🏴󠁧󠁢󠁷󠁬󠁳󠁿', 'Scotland': '🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'Norway': '🇳🇴', 'Ukraine': '🇺🇦',
    'Japan': '🇯🇵', 'South Korea': '🇰🇷', 'Australia': '🇦🇺', 'Iran': '🇮🇷',
    'Saudi Arabia': '🇸🇦', 'Qatar': '🇶🇦',
    'Morocco': '🇲🇦', 'Senegal': '🇸🇳', 'Tunisia': '🇹🇳', 'Egypt': '🇪🇬',
    'Nigeria': '🇳🇬', 'Ghana': '🇬🇭', 'Cameroon': '🇨🇲', 'Algeria': '🇩🇿',
    'Costa Rica': '🇨🇷', 'Panama': '🇵🇦', 'Jamaica': '🇯🇲',
  };
  return flags[team] ?? '⚽';
}

void _sharePredictions(List<Prediction> preds) {
  final lines = preds.map((p) {
    final homeFlag = _getFlag(p.homeTeam);
    final awayFlag = _getFlag(p.awayTeam);
    final match = (p.homeTeam.isNotEmpty && p.awayTeam.isNotEmpty)
        ? '$homeFlag ${p.homeTeam} vs ${p.awayTeam} $awayFlag'
        : p.matchId;
    return '$match → ${p.homeScore}–${p.awayScore}';
  }).join('\n');

  final text = '⚽ My WC2026 Predictions:\n\n$lines\n\n🏆 Shared via WC26 Predictor';
  Share.share(text, subject: 'My WC2026 Predictions');
}

class _PredRow extends StatelessWidget {
  final Prediction prediction;
  const _PredRow({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final matchTitle = (prediction.homeTeam.isNotEmpty && prediction.awayTeam.isNotEmpty)
        ? '${prediction.homeTeam} vs ${prediction.awayTeam}'
        : prediction.matchId;

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(matchTitle,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text('Your pick: ${prediction.homeScore} – ${prediction.awayScore}${prediction.penHome != null ? '  ·  Pens: ${prediction.penHome}–${prediction.penAway}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.text2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ResultChip(
            result: prediction.result,
            points: (prediction.pointsEarned ?? 0) + (prediction.penPointsEarned ?? 0),
            hasPenBonus: prediction.penResult != null,
          ),
        ],
      ),
    );
  }
}
