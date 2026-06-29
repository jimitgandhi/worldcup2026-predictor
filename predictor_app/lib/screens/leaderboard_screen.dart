import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/match_widgets.dart';
import '../widgets/shimmer_loading.dart';
import 'analytics_screen.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  void _showAnalytics(BuildContext context, List<UserModel> users) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnalyticsScreen(users: users),
    );
  }

  void _showUserPredictions(BuildContext context, UserModel user) {
    final firestore = FirestoreService();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  _AvatarBubble(user: user, size: 36, borderColor: Colors.transparent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        Text('${user.totalPoints} pts · Rank #${user.rank}',
                          style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => _UserStatsDialog(user: user),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.cardRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pie_chart_outline, size: 13, color: AppColors.text2),
                          SizedBox(width: 5),
                          Text('Stats', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            // Predictions list
            Expanded(
              child: FutureBuilder<List<Prediction>>(
                future: firestore.fetchUserPastPredictions(user.id),
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                  }
                  final preds = snap.data!;
                  if (preds.isEmpty) {
                    return const Center(
                      child: Text('No past predictions yet',
                        style: TextStyle(color: AppColors.text3, fontSize: 13)),
                    );
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: preds.length,
                    itemBuilder: (_, i) {
                      final p = preds[i];
                      final matchTitle = (p.homeTeam.isNotEmpty && p.awayTeam.isNotEmpty)
                          ? '${p.homeTeam} vs ${p.awayTeam}' : p.matchId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: p.isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.07) : AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: p.isDoubleDown ? const Color(0xFF3B82F6).withOpacity(0.4) : AppColors.border,
                          ),
                          boxShadow: p.isDoubleDown
                              ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.12), blurRadius: 8)]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(matchTitle,
                                    style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis),
                                  Text('Pick: ${p.homeScore} – ${p.awayScore}${(p.penHome != null && p.penAway != null) ? '  ·  Pens: ${p.penHome}–${p.penAway}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11, color: AppColors.text2)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PointPills(p),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPointsInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚽', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      const Text('How Points Work',
                        style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3,
                        )),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, size: 20, color: AppColors.text3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _PointRow('✦ Exact Score', AppColors.green,
                    'Both scores exactly right.'),
                  const Divider(color: AppColors.border, height: 20),
                  _PointRow('✓~ Almost Correct', AppColors.gold,
                    'Right result + one score matches.'),
                  const Divider(color: AppColors.border, height: 20),
                  _PointRow('✓ Correct Result', AppColors.gold,
                    'Right result, neither score matches.'),
                  const Divider(color: AppColors.border, height: 20),
                  _PointRow('~ One Score', AppColors.orange,
                    'One score matches, wrong result.'),
                  const Divider(color: AppColors.border, height: 20),
                  _PointRow('✗ Wrong', AppColors.red,
                    'Neither score correct, wrong result.'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.goldDim,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                    ),
                    child: const Text(
                      '⚡ Almost Correct stacks on Correct Result.\n🔒 Predictions lock at kickoff.',
                      style: TextStyle(fontSize: 12, color: AppColors.gold, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x1A7C3AED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x337C3AED)),
                    ),
                    child: const Text(
                      '🎯 Knockout Penalty Bonus\n\nPredict the penalty shootout too. Same scoring rules but half points (max 25) — stacks on top of your main score.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFA78BFA), height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                    ),
                    child: const Text(
                      '⚡ Double Down\n\nUse once per tournament on any upcoming match. All points earned (including pens) are doubled.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF60A5FA), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final me = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<List<UserModel>>(
      stream: firestore.leaderboardStream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SingleChildScrollView(child: ShimmerList(count: 8));
        }
        final users = snap.data!;

        return CustomScrollView(
          slivers: [
            // Hero header
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Leaderboard',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showPointsInfo(context),
                                child: Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.cardRaised,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Icon(Icons.question_mark_rounded,
                                    size: 12, color: AppColors.text3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showAnalytics(context, users),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.cardRaised,
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.show_chart_rounded, size: 12, color: AppColors.text2),
                                      SizedBox(width: 4),
                                      Text('Analytics',
                                        style: TextStyle(
                                          fontSize: 10, fontWeight: FontWeight.w700,
                                          color: AppColors.text2, letterSpacing: 0.2)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text('${users.length} players · Updated live',
                            style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                        ],
                      ),
                    ),
                    StreamBuilder<UserModel?>(
                      stream: firestore.currentUserStream(me.uid),
                      builder: (_, snap) {
                        final rank = snap.data?.rank ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.goldDim,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                          ),
                          child: Column(
                            children: [
                              Text('#$rank',
                                style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.gold,
                                )),
                              const Text('YOUR RANK',
                                style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700,
                                  color: AppColors.text3, letterSpacing: 0.5,
                                )),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Full list — top 3 get medal styling
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final user = users[i];
                    final rank = i + 1;
                    final isMe = user.id == me.uid;
                    return _LeaderboardRow(
                      user: user, rank: rank, isMe: isMe,
                      onTap: () => _showUserPredictions(context, user),
                    );
                  },
                  childCount: users.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  final UserModel user;
  final double size;
  final Color borderColor;
  const _AvatarBubble({required this.user, required this.size, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: user.photoUrl != null
          ? ClipOval(child: CachedNetworkImage(imageUrl: user.photoUrl!, fit: BoxFit.cover))
          : Center(
              child: Text(user.initials,
                style: TextStyle(
                  fontSize: size * 0.28, fontWeight: FontWeight.w800, color: Colors.white,
                )),
            ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final UserModel user;
  final int rank;
  final bool isMe;
  final VoidCallback onTap;
  const _LeaderboardRow({required this.user, required this.rank, required this.isMe, required this.onTap});

  static const _medalEmoji = ['🥇', '🥈', '🥉'];
  static const _medalBorder = [
    Color(0xFFF0C040), // gold
    Color(0xFFC0C0C0), // silver
    Color(0xFFCD7F32), // bronze
  ];
  static const _medalBg = [
    Color(0x1AF0C040), // gold tint
    Color(0x14C0C0C0), // silver tint
    Color(0x14CD7F32), // bronze tint
  ];

  @override
  Widget build(BuildContext context) {
    final isMedal = rank <= 3;
    final medalIdx = rank - 1;
    final borderColor = isMe
        ? AppColors.gold.withOpacity(0.3)
        : AppColors.border;
    final bgColor = isMe ? const Color(0x0DC9A84C) : AppColors.card;

    return GestureDetector(
      onTap: onTap,
      child: Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: isMedal
                ? Text(_medalEmoji[medalIdx],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18))
                : Text('$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: isMe ? AppColors.gold : AppColors.text3,
                    )),
          ),
          const SizedBox(width: 10),
          _AvatarBubble(
            user: user,
            size: 36,
            borderColor: Colors.transparent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user.displayName,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                      )),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text('YOU',
                          style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            color: AppColors.bg, letterSpacing: 0.5,
                          )),
                      ),
                    ],
                  ],
                ),
                Text('${user.predictionsCount} predictions',
                  style: const TextStyle(fontSize: 11, color: AppColors.text3)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${user.totalPoints}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.gold)),
              const Text('pts',
                style: TextStyle(fontSize: 10, color: AppColors.text3)),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.text3),
        ],
      ),
    ));
  }
}

Widget _PointPills(Prediction p) {
  Color _resultColor(PredictionResult? r) {
    switch (r) {
      case PredictionResult.exact:         return AppColors.green;
      case PredictionResult.correctPlusOne:
      case PredictionResult.correctResult: return AppColors.gold;
      case PredictionResult.oneScore:      return AppColors.orange;
      case PredictionResult.wrong:         return AppColors.red;
      default:                             return AppColors.text3;
    }
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
  );

  final isPending = p.result == null || p.result == PredictionResult.pending;
  if (isPending) {
    return _pill('· Pending', AppColors.text3);
  }

  final mainPts = p.pointsEarned ?? 0;
  final penPts  = p.penPointsEarned ?? 0;
  final mainColor = _resultColor(p.result);

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _pill('+$mainPts', mainColor),
      if (p.penHome != null && p.penAway != null) ...[
        const SizedBox(width: 5),
        _pill('⚡+$penPts', const Color(0xFF7C3AED)),
      ],
      if (p.isDoubleDown) ...[
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.15),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.4)),
            boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.2), blurRadius: 5)],
          ),
          child: Text('2× = ${(mainPts + penPts) * 2}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF60A5FA))),
        ),
      ],
    ],
  );
}

Widget _PointRow(String label, Color color, String desc) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 3),
      Text(desc,
        style: const TextStyle(fontSize: 11, color: AppColors.text3, height: 1.4)),
    ],
  );
}

// ─── User stats pie chart dialog ─────────────────────────────────────────────

class _UserStatsDialog extends StatefulWidget {
  final UserModel user;
  const _UserStatsDialog({required this.user});

  @override
  State<_UserStatsDialog> createState() => _UserStatsDialogState();
}

class _UserStatsDialogState extends State<_UserStatsDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  int? _touchedIdx;

  static const _sections = [
    (key: 'exact',      label: 'Exact',          color: AppColors.green),
    (key: 'plusOne',    label: 'Almost Correct',  color: AppColors.gold),
    (key: 'correct',    label: 'Correct Result',  color: Color(0xFFD4A017)),
    (key: 'oneScore',   label: 'One Score',       color: AppColors.orange),
    (key: 'wrong',      label: 'Wrong',           color: AppColors.red),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scale = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final total = u.predictionsCount;
    final wrongCount = (total - u.exactCount - u.correctPlusOneCount
        - u.correctResultCount - u.oneScoreCount).clamp(0, total);

    final counts = [
      u.exactCount, u.correctPlusOneCount, u.correctResultCount,
      u.oneScoreCount, wrongCount,
    ];

    final hitRate = total > 0
        ? ((u.exactCount + u.correctPlusOneCount + u.correctResultCount) / total * 100).toStringAsFixed(1)
        : '0.0';
    final avgPts = total > 0
        ? (u.totalPoints / total).toStringAsFixed(1)
        : '0.0';

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < _sections.length; i++) {
      final count = counts[i];
      if (count <= 0) continue;
      final isTouched = _touchedIdx == i;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: _sections[i].color,
        radius: isTouched ? 62 : 54,
        title: isTouched ? '${(count / total * 100).toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
        borderSide: isTouched
            ? BorderSide(color: _sections[i].color, width: 2)
            : BorderSide.none,
      ));
    }

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('📊', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${u.displayName.split(' ').first}\'s Stats',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 20, color: AppColors.text3),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Metric pills row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatPill('Hit Rate', '$hitRate%', AppColors.gold),
                _StatPill('Avg Pts', avgPts, AppColors.green),
                _StatPill('Matches', '$total', AppColors.text2),
              ],
            ),
            const SizedBox(height: 20),
            // Pie chart with sweep-in animation
            total == 0
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No settled predictions yet',
                    style: TextStyle(color: AppColors.text3)),
                )
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) {
                    return SizedBox(
                      height: 180,
                      child: PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 80 - (32 * t), // 80 → 48: ring expands outward
                          sectionsSpace: 2,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, response) {
                              setState(() {
                                if (!event.isInterestedForInteractions ||
                                    response?.touchedSection == null) {
                                  _touchedIdx = null;
                                } else {
                                  _touchedIdx = response!.touchedSection!.touchedSectionIndex;
                                }
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
            // Center label overlay (accuracy)
            if (total > 0)
              Transform.translate(
                offset: const Offset(0, -108),
                child: Column(
                  children: [
                    Text(hitRate,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.gold)),
                    const Text('%', style: TextStyle(fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: List.generate(_sections.length, (i) {
                final count = counts[i];
                if (count <= 0) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: _sections[i].color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('${_sections[i].label} ($count)',
                      style: const TextStyle(fontSize: 10, color: AppColors.text2, fontWeight: FontWeight.w600)),
                  ],
                );
              }),
            ),
            if (u.penBonusCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('⚡', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Text('Pen Bonus earned: ${u.penBonusCount}x',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

Widget _StatPill(String label, String value, Color color) {
  return Column(
    children: [
      Text(value,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 2),
      Text(label,
        style: const TextStyle(fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w600)),
    ],
  );
}
