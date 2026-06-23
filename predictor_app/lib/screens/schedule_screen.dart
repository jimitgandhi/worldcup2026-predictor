import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../models/user_model.dart';
import '../services/espn_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/match_card.dart';
import '../widgets/match_predictions_sheet.dart';
import '../widgets/shimmer_loading.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _espn = EspnService();
  final _firestore = FirestoreService();
  final _user = FirebaseAuth.instance.currentUser!;

  List<Match> _allMatches = [];
  Map<String, Match> _firestoreOverrides = {};
  Map<String, Prediction> _predictions = {};
  List<UserModel> _users = [];
  bool _loading = true;
  bool _isAdmin = false;

  // Prevent double-settling (e.g. timer fires twice before Firestore stream catches up)
  final Set<String> _settlingMatchIds = {};

  Timer? _refreshTimer;
  Timer? _kickoffTimer;
  StreamSubscription? _firestoreMatchSub;
  StreamSubscription? _predsSub;
  StreamSubscription? _userSub;
  StreamSubscription? _leaderboardSub;
  StreamSubscription? _notifTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this); // 0=Upcoming, 1=Live, 2=Past
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadLive());
    _kickoffTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _predsSub = _firestore.userPredictionsStream(_user.uid).listen((preds) {
      if (mounted) {
        setState(() => _predictions = {for (final p in preds) p.matchId: p});
        _rescheduleNotifications();
      }
    });
    _firestoreMatchSub = _firestore.matchesStream().listen((fsMatches) {
      if (mounted) setState(() => _firestoreOverrides = {for (final m in fsMatches) m.id: m});
    });
    _leaderboardSub = _firestore.leaderboardStream().listen((users) {
      if (mounted) setState(() => _users = users);
    });
    _userSub = _firestore.currentUserStream(_user.uid).listen((model) {
      if (mounted && model != null) {
        final wasAdmin = _isAdmin;
        setState(() => _isAdmin = model.isAdmin);
        // If isAdmin just became true, run autoSettle now in case matches
        // finished while we were loading (isAdmin stream lags behind _load)
        if (!wasAdmin && model.isAdmin && _allMatches.isNotEmpty) {
          _autoSettle(_mergedMatches);
        }
      }
    });
    // Store subscription so we can cancel in dispose (prevents listener leak)
    _notifTapSub = NotificationService.onNotificationTap.listen((payload) {
      if (!mounted) return;
      if (payload == 'past') {
        _tabController.animateTo(2);
      } else {
        _tabController.animateTo(0);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _refreshTimer?.cancel();
    _kickoffTimer?.cancel();
    _firestoreMatchSub?.cancel();
    _predsSub?.cancel();
    _userSub?.cancel();
    _leaderboardSub?.cancel();
    _notifTapSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLive();
    }
  }

  Future<void> _load() async {
    final matches = await _espn.fetchAllMatches();
    if (mounted) {
      setState(() {
        _allMatches = matches;
        _loading = false;
      });
      // Only reschedule if we got a full match list (not just today's fallback)
      // fetchAllMatches falls back to fetchToday on failure — that would wipe future reminders
      if (matches.length > 5) _rescheduleNotifications();
      if (_isAdmin) _autoSettle(matches);
    }
  }

  Future<void> _loadLive() async {
    final todayMatches = await _espn.fetchToday();
    if (!mounted || todayMatches.isEmpty) return;
    final todayById = {for (final m in todayMatches) m.id: m};
    setState(() {
      _allMatches = _allMatches.map((m) => todayById[m.id] ?? m).toList();
    });
    if (_isAdmin) _autoSettle(todayMatches);
    _rescheduleNotifications();
  }

  /// Auto-settle matches that ESPN marks as finished but Firestore hasn't settled yet.
  /// Only runs when the current user is admin.
  void _autoSettle(List<Match> espnMatches) {
    for (final m in espnMatches) {
      if (m.status != MatchStatus.finished) continue;
      if (m.homeScore == null || m.awayScore == null) continue;
      final fsOverride = _firestoreOverrides[m.id];
      if (fsOverride?.status == MatchStatus.finished) continue; // already settled in Firestore
      if (_settlingMatchIds.contains(m.id)) continue; // already in-flight
      _settlingMatchIds.add(m.id);
      _firestore.settleMatch(
        matchId: m.id,
        actualHome: m.homeScore!,
        actualAway: m.awayScore!,
      ).catchError((e) {
        debugPrint('Auto-settle failed for ${m.id}: $e');
      }).whenComplete(() {
        _settlingMatchIds.remove(m.id);
      });
    }
  }

  /// Re-schedule all pre-match reminders, updating the body text based on
  /// whether the user already has a prediction for each match.
  void _rescheduleNotifications() {
    if (_allMatches.isEmpty || kIsWeb) return;
    NotificationService.scheduleMatchReminders(_mergedMatches);
  }

  List<Match> get _mergedMatches {
    final espnIds = {for (final m in _allMatches) m.id};
    final merged = _allMatches.map((m) {
      final fs = _firestoreOverrides[m.id];
      // Only use Firestore override when the match is settled — for live/upcoming,
      // ESPN real-time data is more accurate than Firestore's stale status.
      if (fs != null && fs.status == MatchStatus.finished) return fs;
      return m;
    }).toList();
    for (final m in _firestoreOverrides.values) {
      if (!espnIds.contains(m.id)) merged.add(m);
    }
    merged.sort((a, b) => a.kickoff.compareTo(b.kickoff));
    return merged;
  }

  Future<void> _submitPrediction(Match match, int home, int away) async {
    await _firestore.submitPrediction(
      userId: _user.uid,
      matchId: match.id,
      homeScore: home,
      awayScore: away,
      homeTeam: match.homeTeam,
      awayTeam: match.awayTeam,
      kickoff: match.kickoff,
    );
  }

  void _showMatchPredictions(BuildContext context, Match match) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => MatchPredictionsSheet(match: match, users: _users),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Match> matches, {
    bool canSubmit = false,
    bool showPredictions = false,
    bool tapToShowPredictions = false,
  }) {
    if (_loading) return const ShimmerList();
    if (matches.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer, size: 48, color: AppColors.text3),
            SizedBox(height: 12),
            Text('No matches here', style: TextStyle(color: AppColors.text3, fontSize: 14)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: matches.length,
        itemBuilder: (_, i) {
          final m = matches[i];
          Widget card = MatchCard(
            match: m,
            prediction: _predictions[m.id],
            onSubmit: (canSubmit && m.isPredictionOpen)
                ? (h, a) => _submitPrediction(m, h, a)
                : null,
          );
          if (showPredictions && _users.isNotEmpty) {
            card = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card,
                _LivePredictionsPanel(match: m, users: _users),
              ],
            );
          }
          if (tapToShowPredictions) {
            card = GestureDetector(
              onTap: () => _showMatchPredictions(context, m),
              child: card,
            );
          }
          return card;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _mergedMatches;
    final upcoming = all.where((m) => m.status == MatchStatus.upcoming).toList();
    final live = all.where((m) => m.status == MatchStatus.live).toList();
    // Past shown newest first
    final past = all.where((m) => m.status == MatchStatus.finished).toList().reversed.toList();

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.gold,
            indicatorWeight: 2,
            labelColor: AppColors.gold,
            unselectedLabelColor: AppColors.text3,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            dividerColor: AppColors.border,
            tabs: [
              const Tab(text: 'UPCOMING'),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('LIVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    if (live.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'PAST'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList(context, upcoming, canSubmit: true),
              _buildList(context, live, canSubmit: true, showPredictions: true),
              _buildList(context, past, tapToShowPredictions: true),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Live predictions panel ──────────────────────────────────────────────────
// Shown inline below each live match card, ordered by rank.

class _LivePredictionsPanel extends StatefulWidget {
  final Match match;
  final List<UserModel> users;

  const _LivePredictionsPanel({required this.match, required this.users});

  @override
  State<_LivePredictionsPanel> createState() => _LivePredictionsPanelState();
}

class _LivePredictionsPanelState extends State<_LivePredictionsPanel> {
  late Future<List<Prediction>> _future;

  @override
  void initState() {
    super.initState();
    _future = FirestoreService().fetchMatchPredictions(widget.match.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Prediction>>(
      future: _future,
      builder: (_, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final predMap = {for (final p in snap.data!) p.userId: p};
        final sorted = [...widget.users]..sort((a, b) {
          if (a.rank == 0 && b.rank == 0) return a.displayName.compareTo(b.displayName);
          if (a.rank == 0) return 1;
          if (b.rank == 0) return -1;
          return a.rank.compareTo(b.rank);
        });

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 5),
          decoration: BoxDecoration(
            color: AppColors.cardRaised,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline, size: 13, color: AppColors.text3),
                    const SizedBox(width: 6),
                    const Text(
                      "Everyone's picks",
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.text3, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  children: sorted.map((user) => PredTile(
                    user: user,
                    prediction: predMap[user.id],
                    compact: true,
                      liveHome: widget.match.homeScore,
                      liveAway: widget.match.awayScore,
                    )).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
