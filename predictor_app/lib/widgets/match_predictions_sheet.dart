import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/scoring_service.dart';
import '../theme/app_theme.dart';
import 'match_widgets.dart';

/// Bottom sheet showing all users' predictions for a specific match.
/// Used in the Past tab (tap) and as the data source for the live inline panel.
class MatchPredictionsSheet extends StatelessWidget {
  final Match match;
  final List<UserModel> users;

  const MatchPredictionsSheet({
    super.key,
    required this.match,
    required this.users,
  });

  static List<UserModel> _sortedByRank(List<UserModel> users) {
    final sorted = [...users];
    sorted.sort((a, b) {
      if (a.rank == 0 && b.rank == 0) return a.displayName.compareTo(b.displayName);
      if (a.rank == 0) return 1;
      if (b.rank == 0) return -1;
      return a.rank.compareTo(b.rank);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Match header — teams + final score
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        match.homeTeam,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.goldDim,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                      ),
                      child: Text(
                        '${match.homeScore ?? 0}–${match.awayScore ?? 0}',
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.gold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        match.awayTeam,
                        textAlign: TextAlign.left,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  match.group,
                  style: const TextStyle(fontSize: 11, color: AppColors.text3),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          // Penalty score display if match went to penalties
          if (match.wentToPenalties)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x1A7C3AED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x337C3AED)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sports_soccer, size: 12, color: Color(0xFFA78BFA)),
                    const SizedBox(width: 6),
                    Text(
                      'Penalty shootout: ${match.penaltyHomeScore}–${match.penaltyAwayScore}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFA78BFA)),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.people_outline, size: 14, color: AppColors.text3),
                const SizedBox(width: 6),
                Text(
                  '${users.length} players · ranked by leaderboard',
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.text3, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Prediction>>(
              future: FirestoreService().fetchMatchPredictions(match.id),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }
                final predMap = {for (final p in snap.data!) p.userId: p};
                final sorted = _sortedByRank(users);

                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    return PredTile(
                      user: sorted[i],
                      prediction: predMap[sorted[i].id],
                      isDoubleDown: sorted[i].doubleDownMatchId == match.id ||
                          (predMap[sorted[i].id]?.isDoubleDown ?? false),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Single row showing a user's prediction for a match.
/// Used in both the bottom sheet and the live inline panel.
class PredTile extends StatelessWidget {
  final UserModel user;
  final Prediction? prediction;
  final bool compact;
  final int? liveHome;
  final int? liveAway;
  final int? livePenHome;
  final int? livePenAway;
  final bool isDoubleDown;

  const PredTile({
    super.key,
    required this.user,
    required this.prediction,
    this.compact = false,
    this.liveHome,
    this.liveAway,
    this.livePenHome,
    this.livePenAway,
    this.isDoubleDown = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSettled = prediction != null && prediction!.result != PredictionResult.pending;
    final totalPoints = (prediction?.pointsEarned ?? 0) + (prediction?.penPointsEarned ?? 0);
    final hasPenBonus = prediction?.penResult != null;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 4 : 8),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 8 : 11,
      ),
      decoration: BoxDecoration(
        color: isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(
          color: isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.4) : AppColors.border,
        ),
        boxShadow: isDoubleDown
            ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.15), blurRadius: 8)]
            : null,
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 24,
            child: Text(
              user.rank > 0 ? '#${user.rank}' : '–',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.text3),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          UserAvatar(user: user, size: compact ? 24 : 28),
          const SizedBox(width: 8),
          // Name + penalty pick
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      user.displayName.split(' ').first,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isDoubleDown) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                        ),
                        child: const Text('2×',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF60A5FA))),
                      ),
                    ],
                  ],
                ),
                if (prediction?.penHome != null && prediction?.penAway != null)
                  Text(
                    '🎯 Pens: ${prediction!.penHome}–${prediction!.penAway}',
                    style: const TextStyle(fontSize: 9, color: Color(0xFFA78BFA), fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          // Pick + result chip
          if (prediction != null) ...[
            Text(
              '${prediction!.homeScore}–${prediction!.awayScore}',
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text2),
            ),
            const SizedBox(width: 8),
            if (liveHome != null && liveAway != null &&
                prediction!.result == PredictionResult.pending) ...[
              _LivePtsBadge(
                prediction: prediction!,
                liveHome: liveHome!,
                liveAway: liveAway!,
                livePenHome: livePenHome,
                livePenAway: livePenAway,
                isDoubleDown: isDoubleDown,
              ),
            ] else
              ResultChip(
                result: prediction!.result,
                points: isSettled ? totalPoints : prediction!.pointsEarned,
                hasPenBonus: hasPenBonus,
              ),
          ] else
            const Text(
              'No pick',
              style: TextStyle(
                fontSize: 11, color: AppColors.text3, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}

/// Small circular avatar used across prediction-related widgets.
class UserAvatar extends StatelessWidget {
  final UserModel user;
  final double size;

  const UserAvatar({super.key, required this.user, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
      ),
      child: user.photoUrl != null
          ? ClipOval(
              child: CachedNetworkImage(imageUrl: user.photoUrl!, fit: BoxFit.cover),
            )
          : Center(
              child: Text(
                user.initials,
                style: TextStyle(
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }
}

class _LivePtsBadge extends StatelessWidget {
  final Prediction prediction;
  final int liveHome;
  final int liveAway;
  final int? livePenHome;
  final int? livePenAway;
  final bool isDoubleDown;

  const _LivePtsBadge({
    required this.prediction,
    required this.liveHome,
    required this.liveAway,
    this.livePenHome,
    this.livePenAway,
    this.isDoubleDown = false,
  });

  @override
  Widget build(BuildContext context) {
    final scored = ScoringService.calculate(
      predHome: prediction.homeScore,
      predAway: prediction.awayScore,
      actualHome: liveHome,
      actualAway: liveAway,
    );
    int penPts = 0;
    if (livePenHome != null && livePenAway != null
        && prediction.penHome != null && prediction.penAway != null) {
      penPts = ScoringService.calculatePen(
        predHome: prediction.penHome!,
        predAway: prediction.penAway!,
        actualHome: livePenHome!,
        actualAway: livePenAway!,
      ).points;
    }
    final rawPts = scored.points + penPts;
    final pts = isDoubleDown ? rawPts * 2 : rawPts;
    final color = pts >= 50
        ? AppColors.green
        : pts >= 20
            ? AppColors.gold
            : pts >= 10
                ? AppColors.orange
                : AppColors.text3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.12) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.4) : color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: const BoxDecoration(
              color: AppColors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            isDoubleDown ? '⚡ 2×+$pts' : '+$pts',
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: isDoubleDown ? const Color(0xFF60A5FA) : color)),
        ],
      ),
    );
  }
}
