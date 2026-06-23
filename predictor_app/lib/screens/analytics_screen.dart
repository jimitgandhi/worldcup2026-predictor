import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

// One distinct color per user (up to 8)
const _kChartColors = [
  Color(0xFFC9A84C), // gold
  Color(0xFF3B82F6), // blue
  Color(0xFF10B981), // green
  Color(0xFFEF4444), // red
  Color(0xFF8B5CF6), // purple
  Color(0xFFF59E0B), // amber
  Color(0xFF06B6D4), // cyan
  Color(0xFFEC4899), // pink
];

class _ChartData {
  final List<Match> matches;
  final List<UserModel> users;
  /// userId → cumulative points after each finished match (index = match order)
  final Map<String, List<double>> runningTotals;

  const _ChartData({
    required this.matches,
    required this.users,
    required this.runningTotals,
  });

  bool get isEmpty => matches.isEmpty;
}

class AnalyticsScreen extends StatefulWidget {
  final List<UserModel> users;

  const AnalyticsScreen({super.key, required this.users});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late Future<_ChartData> _dataFuture;
  StreamSubscription? _leaderboardSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _dataFuture = _loadData();
    // Auto-refresh when scores are settled (leaderboard updates on every settle)
    _leaderboardSub = FirestoreService().leaderboardStream().listen((_) {
      if (mounted) setState(() => _dataFuture = _loadData());
    });
  }

  @override
  void dispose() {
    _leaderboardSub?.cancel();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<_ChartData> _loadData() async {
    final firestore = FirestoreService();
    final allPredsFuture = firestore.fetchAllPredictions();
    final matchesFuture = firestore.fetchFinishedMatches();
    final allPreds = await allPredsFuture;
    final finishedMatches = await matchesFuture;

    if (finishedMatches.isEmpty) {
      return _ChartData(
          matches: [], users: widget.users, runningTotals: {});
    }

    // matchId → userId → pointsEarned
    final Map<String, Map<String, int>> matchUserPts = {};
    for (final pred in allPreds) {
      if (pred.result == PredictionResult.pending) continue;
      matchUserPts.putIfAbsent(pred.matchId, () => <String, int>{})[pred.userId] =
          pred.pointsEarned ?? 0;
    }

    // Build cumulative totals per user across matches in order
    final Map<String, double> running = {
      for (final u in widget.users) u.id: 0.0
    };
    final Map<String, List<double>> totals = {
      for (final u in widget.users) u.id: []
    };

    for (final match in finishedMatches) {
      final userPts = matchUserPts[match.id] ?? {};
      for (final u in widget.users) {
        running[u.id] = (running[u.id] ?? 0) + (userPts[u.id] ?? 0);
        totals[u.id]!.add(running[u.id]!);
      }
    }

    return _ChartData(
      matches: finishedMatches,
      users: widget.users,
      runningTotals: totals,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Text(
                  '📈  Score Progression',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 20, color: AppColors.text3),
                ),
              ],
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.gold,
            indicatorWeight: 2,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.text3,
            labelStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            dividerColor: AppColors.border,
            tabs: const [
              Tab(text: 'ABSOLUTE'),
              Tab(text: 'VS LEADER'),
            ],
          ),
          Expanded(
            child: FutureBuilder<_ChartData>(
              future: _dataFuture,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }
                if (snap.hasError || !snap.hasData) {
                  return const Center(
                    child: Text('Failed to load data',
                      style: TextStyle(color: AppColors.text3)),
                  );
                }
                final data = snap.data!;
                if (data.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart, size: 48, color: AppColors.text3),
                        SizedBox(height: 12),
                        Text('No settled matches yet',
                          style: TextStyle(color: AppColors.text3, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Chart will appear once matches are settled',
                          style: TextStyle(color: AppColors.text3, fontSize: 12)),
                      ],
                    ),
                  );
                }

                return TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _ChartView(data: data, relative: false),
                    _ChartView(data: data, relative: true),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartView extends StatefulWidget {
  final _ChartData data;
  final bool relative;

  const _ChartView({super.key, required this.data, required this.relative});

  @override
  State<_ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<_ChartView> {
  final _scrollCtrl = ScrollController();
  int? _selectedIdx; // currently tapped match index

  static const _colWidth = 90.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients &&
          _scrollCtrl.position.maxScrollExtent > 0) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<FlSpot> _spots(String userId) {
    final totals = widget.data.runningTotals[userId] ?? [];
    if (!widget.relative) {
      return totals.asMap().entries
          .map((e) => FlSpot(e.key.toDouble(), e.value))
          .toList();
    }
    // Relative: each point minus the leader's total at that match
    return totals.asMap().entries.map((e) {
      final idx = e.key;
      final leaderPts = widget.data.users
          .map((u) => widget.data.runningTotals[u.id]?[idx] ?? 0.0)
          .reduce(max);
      return FlSpot(idx.toDouble(), e.value - leaderPts);
    }).toList();
  }

  double get _maxY {
    if (widget.relative) return 10; // leader is always 0, so max is ~0
    final allTotals = widget.data.users
        .expand((u) => widget.data.runningTotals[u.id] ?? [0.0]);
    if (allTotals.isEmpty) return 100;
    return (allTotals.reduce(max) * 1.15).ceilToDouble();
  }

  double get _minY {
    if (!widget.relative) return 0;
    double minVal = 0;
    final n = widget.data.matches.length;
    for (int i = 0; i < n; i++) {
      final leaderPts = widget.data.users
          .map((u) => widget.data.runningTotals[u.id]?[i] ?? 0.0)
          .reduce(max);
      for (final u in widget.data.users) {
        final v = (widget.data.runningTotals[u.id]?[i] ?? 0.0) - leaderPts;
        if (v < minVal) minVal = v;
      }
    }
    return (minVal * 1.15).floorToDouble();
  }

  String _matchLabel(int idx) {
    final m = widget.data.matches[idx];
    final h = m.homeTeamCode.toUpperCase();
    final a = m.awayTeamCode.toUpperCase();
    if (h.isEmpty || a.isEmpty) return 'M${idx + 1}';
    final hs = h.length > 3 ? h.substring(0, 3) : h;
    final as_ = a.length > 3 ? a.substring(0, 3) : a;
    return '$hs-$as_';
  }

  @override
  Widget build(BuildContext context) {
    final numMatches = widget.data.matches.length;
    final screenWidth = MediaQuery.of(context).size.width;
    final chartWidth = max(screenWidth, (numMatches + 1) * _colWidth);

    return Column(
      children: [
        _Legend(users: widget.data.users),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: numMatches.toDouble(),
                      minY: _minY,
                      maxY: _maxY,
                      // No clipData — clipping was preventing tooltips from rendering
                      gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0x11FFFFFF),
                        strokeWidth: 1,
                      ),
                      getDrawingVerticalLine: (_) => const FlLine(
                        color: Color(0x08FFFFFF),
                        strokeWidth: 0.5,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: const Color(0x11FFFFFF)),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.text3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= numMatches) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _matchLabel(idx),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: AppColors.text3,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: widget.data.users.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final user = entry.value;
                      final color = _kChartColors[idx % _kChartColors.length];
                      return LineChartBarData(
                        spots: _spots(user.id),
                        color: color,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                            radius: 3.5,
                            color: color,
                            strokeWidth: 1.5,
                            strokeColor: AppColors.bg,
                          ),
                        ),
                        belowBarData: BarAreaData(show: false),
                      );
                    }).toList(),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: false,
                      touchSpotThreshold: 40,
                      touchCallback: (event, response) {
                        final spots = response?.lineBarSpots;
                        if (spots == null || spots.isEmpty) return;
                        final idx = spots.first.x.round()
                            .clamp(0, numMatches - 1);
                        if (mounted) setState(() => _selectedIdx = idx);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Info panel — shows all users' values at the selected match
        if (_selectedIdx != null && _selectedIdx! < widget.data.matches.length)
          _MatchInfoPanel(
            matchIdx: _selectedIdx!,
            data: widget.data,
            relative: widget.relative,
          ),
      ],
    );
  }
}

class _InitialsDotPainter extends FlDotPainter {
  final String initials;
  final Color color;

  const _InitialsDotPainter({required this.initials, required this.color});

  @override
  List<Object?> get props => [initials, color];

  @override
  Color get mainColor => color;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset center) {
    // Background circle
    canvas.drawCircle(center, 10,
        Paint()..color = AppColors.bg..style = PaintingStyle.fill);
    // Colored ring
    canvas.drawCircle(center, 10,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
    // Initials text
    final tp = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          color: color,
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  Size getSize(FlSpot spot) => const Size(20, 20);

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;
}

class _Legend extends StatelessWidget {
  final List<UserModel> users;

  const _Legend({required this.users});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: users.asMap().entries.map((entry) {
          final color = _kChartColors[entry.key % _kChartColors.length];
          final user = entry.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16, height: 3,
                decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Text(
                user.displayName.split(' ').first,
                style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text2),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─── Inline match info panel ─────────────────────────────────────────────────
// Shows all users' values at the selected match, below the chart. No cropping.

class _MatchInfoPanel extends StatelessWidget {
  final int matchIdx;
  final _ChartData data;
  final bool relative;

  const _MatchInfoPanel({
    required this.matchIdx,
    required this.data,
    required this.relative,
  });

  @override
  Widget build(BuildContext context) {
    final match = data.matches[matchIdx];
    final label = '${match.homeTeam} vs ${match.awayTeam}';

    // Build sorted rows: user, cumulative pts, match pts delta
    final rows = data.users.asMap().entries.map((entry) {
      final i = entry.key;
      final user = entry.value;
      final totals = data.runningTotals[user.id] ?? [];
      final cumulative = matchIdx < totals.length ? totals[matchIdx] : 0.0;
      final prev = matchIdx > 0 && matchIdx - 1 < totals.length
          ? totals[matchIdx - 1]
          : 0.0;
      final matchPts = cumulative - prev;
      double displayVal;
      if (relative) {
        final leaderPts = data.users
            .map((u) => data.runningTotals[u.id]?[matchIdx] ?? 0.0)
            .reduce(max);
        displayVal = cumulative - leaderPts;
      } else {
        displayVal = cumulative;
      }
      return (
        user: user,
        color: _kChartColors[i % _kChartColors.length],
        displayVal: displayVal,
        matchPts: matchPts,
      );
    }).toList();

    // Sort by displayVal descending for absolute, ascending for relative
    rows.sort((a, b) => relative
        ? b.displayVal.compareTo(a.displayVal)
        : b.displayVal.compareTo(a.displayVal));

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardRaised,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app_outlined, size: 11, color: AppColors.text3),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text3),
                  overflow: TextOverflow.ellipsis),
              ),
              Text('Match ${matchIdx + 1}',
                style: const TextStyle(fontSize: 10, color: AppColors.text3)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: rows.map((r) {
              final valStr = relative
                  ? '${r.displayVal >= 0 ? '+' : ''}${r.displayVal.toInt()}'
                  : '${r.displayVal.toInt()} pts';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: r.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${r.user.displayName.split(' ').first} $valStr',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: r.matchPts > 0 ? AppColors.text : AppColors.text2),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
