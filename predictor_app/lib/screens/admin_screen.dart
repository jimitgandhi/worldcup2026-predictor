import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/match.dart';
import '../models/user_model.dart';
import '../services/espn_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/match_widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _espn = EspnService();
  final _firestore = FirestoreService();
  late TabController _tabs;

  List<Match> _matches = [];
  List<UserModel> _users = [];
  bool _loadingMatches = true;
  bool _loadingUsers = true;
  String? _settling;
  bool _busy = false;

  // Demo live match
  String? _demoMatchId;
  int _demoHome = 0;
  int _demoAway = 0;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadMatches();
    _loadUsers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _demoTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    setState(() => _loadingMatches = true);
    final m = await _espn.fetchAllMatches();
    if (mounted) setState(() { _matches = m; _loadingMatches = false; });
  }

  Future<void> _syncMatchesToFirestore() async {
    if (!await _confirm('🔄 Sync Matches from ESPN?',
        'This will fetch all matches from ESPN and update Firestore with latest data including kickoff times.')) return;
    setState(() => _busy = true);
    try {
      final matches = await _espn.fetchAllMatches();
      int updated = 0;
      for (final match in matches) {
        await _firestore.upsertMatch(match);
        updated++;
      }
      _snack('✅ Synced $updated matches from ESPN', AppColors.gold, AppColors.bg);
    } catch (e) {
      _snack('Error: $e', Colors.red.shade900, Colors.white);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    final snap = await FirebaseFirestore.instance
        .collection('users').orderBy('totalPoints', descending: true).get();
    if (mounted) setState(() {
      _users = snap.docs.map(UserModel.fromFirestore).toList();
      _loadingUsers = false;
    });
  }

  // ─── SETTLE ─────────────────────────────────────────────
  Future<void> _showSettleDialog(Match match) async {
    int home = match.homeScore ?? 0;
    int away = match.awayScore ?? 0;
    bool wentToPens = match.wentToPenalties;
    int penHome = match.penaltyHomeScore ?? 5;
    int penAway = match.penaltyAwayScore ?? 4;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Settle: ${match.homeTeam} vs ${match.awayTeam}',
            style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ScoreSelector(label: match.homeTeam, value: home, onChanged: (v) => setD(() => home = v)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('—', style: TextStyle(color: AppColors.text2, fontSize: 20))),
                  _ScoreSelector(label: match.awayTeam, value: away, onChanged: (v) => setD(() => away = v)),
                ],
              ),
              if (match.isKnockout) ...[
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                Row(
                  children: [
                    const Text('Went to penalties?',
                      style: TextStyle(color: AppColors.text2, fontSize: 13)),
                    const Spacer(),
                    Switch.adaptive(
                      value: wentToPens,
                      onChanged: (v) => setD(() => wentToPens = v),
                      activeColor: const Color(0xFF7C3AED),
                    ),
                  ],
                ),
                if (wentToPens) ...[
                  const Text('Penalty shootout score:',
                    style: TextStyle(color: AppColors.text3, fontSize: 11)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ScoreSelector(label: match.homeTeam, value: penHome, onChanged: (v) => setD(() => penHome = v)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('—', style: TextStyle(color: AppColors.text2, fontSize: 20))),
                      _ScoreSelector(label: match.awayTeam, value: penAway, onChanged: (v) => setD(() => penAway = v)),
                    ],
                  ),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text3))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              onPressed: () async {
                Navigator.pop(ctx);
                await _settle(match, home, away,
                  penaltyHome: wentToPens ? penHome : null,
                  penaltyAway: wentToPens ? penAway : null,
                );
              },
              child: const Text('Settle & Score',
                style: TextStyle(color: AppColors.bg, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settle(Match match, int home, int away, {int? penaltyHome, int? penaltyAway}) async {
    setState(() => _settling = match.id);
    try {
      await _firestore.resettleMatch(
        matchId: match.id,
        actualHome: home,
        actualAway: away,
        penaltyHome: penaltyHome,
        penaltyAway: penaltyAway,
      );
      final penStr = penaltyHome != null ? ' (Pens: $penaltyHome–$penaltyAway)' : '';
      final verb = match.status == MatchStatus.finished ? 'Re-settled' : 'Settled';
      _snack('✅ $verb: ${match.homeTeam} $home–$away ${match.awayTeam}$penStr', AppColors.gold, AppColors.bg);
      _loadMatches(); _loadUsers();
    } catch (e) { _snack('Error: $e', Colors.red.shade800, Colors.white); }
    finally { if (mounted) setState(() => _settling = null); }
  }

  // ─── DELETE MATCH PREDICTIONS ───────────────────────────
  Future<void> _deleteMatchPredictions(Match match) async {
    if (!await _confirm('Delete predictions for ${match.homeTeam} vs ${match.awayTeam}?',
        'All predictions for this match will be removed. User points are NOT adjusted.')) return;
    setState(() => _busy = true);
    try {
      await _firestore.deletePredictionsForMatch(match.id);
      _snack('🗑️ Predictions deleted for ${match.homeTeam} vs ${match.awayTeam}', AppColors.red, Colors.white);
    } catch (e) { _snack('Error: $e', Colors.red.shade900, Colors.white); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  // ─── DELETE ALL ──────────────────────────────────────────
  Future<void> _deleteAllPredictions() async {
    if (!await _confirm('⚠️ Delete ALL predictions?',
        'This deletes every prediction in the database and resets all user points to 0. This cannot be undone.')) return;
    setState(() => _busy = true);
    try {
      final count = await _firestore.deleteAllPredictions();
      _snack('🗑️ Deleted $count predictions. All points reset.', AppColors.red, Colors.white);
      _loadUsers();
    } catch (e) { _snack('Error: $e', Colors.red.shade900, Colors.white); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  // ─── EDIT USER POINTS ───────────────────────────────────
  Future<void> _deleteUser(UserModel user) async {
    final confirmed = await _confirm(
      'Delete "${user.displayName}"?',
      'This removes their account, all predictions, and resets leaderboard ranks. Cannot be undone.');
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _firestore.deleteUser(user.id);
      await _firestore.refreshRanks();
      _loadUsers();
      _snack('Deleted ${user.displayName}', AppColors.red, Colors.white);
    } catch (e) {
      _snack('Error: $e', AppColors.red, Colors.white);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editUserPoints(UserModel user) async {
    final ctrl = TextEditingController(text: user.totalPoints.toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Edit points: ${user.displayName}',
          style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'Total Points', labelStyle: TextStyle(color: AppColors.text2)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text3))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
            onPressed: () async {
              Navigator.pop(ctx);
              final pts = int.tryParse(ctrl.text) ?? user.totalPoints;
              await FirebaseFirestore.instance.collection('users').doc(user.id).update({'totalPoints': pts});
              await _firestore.refreshRanks();
              _loadUsers();
              _snack('Updated ${user.displayName} → $pts pts', AppColors.gold, AppColors.bg);
            },
            child: const Text('Save', style: TextStyle(color: AppColors.bg, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ─── FORCE REFRESH RANKS ────────────────────────────────
  Future<void> _refreshRanks() async {
    setState(() => _busy = true);
    try {
      await _firestore.refreshRanks();
      _loadUsers();
      _snack('✅ Ranks refreshed', AppColors.gold, AppColors.bg);
    } catch (e) { _snack('Error: $e', Colors.red.shade800, Colors.white); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  // ─── RECALC ALL SCORES ───────────────────────────────────
  Future<void> _recalcAllScores() async {
    final confirmed = await _confirm(
      '♻️ Recalculate All Scores?',
      'Re-scores every settled prediction using the current point values (Exact=50, Correct+1=30, Correct=20, OneScore=10). This resets and recalculates all user totals. Cannot be undone.');
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final count = await _firestore.recalcAllScores();
      _loadUsers();
      _snack('✅ Recalculated $count predictions. Points updated!', AppColors.gold, AppColors.bg);
    } catch (e) {
      _snack('Error: $e', Colors.red.shade900, Colors.white);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── TEST NOTIFICATION ───────────────────────────────────
  Future<void> _testNotification() async {
    await NotificationService.sendTestNotification();
    _snack('🔔 Test notification sent!', AppColors.gold, AppColors.bg);
  }

  Future<void> _testScheduledNotification() async {
    final mode = await NotificationService.scheduleTestReminder();
    if (!mounted) return;
    final msg = mode == 'exact'
        ? '⏰ Scheduled (exact)! Should fire in 30s — background the app now.'
        : mode == 'inexact'
            ? '⚠️ Scheduled (inexact — exact alarm denied). May be delayed.'
            : '❌ Failed to schedule: $mode';
    _snack(msg, mode.startsWith('failed') ? AppColors.red : AppColors.gold, AppColors.bg);
  }

  Future<void> _showPendingNotifications() async {
    final pending = await NotificationService.getPendingNotifications();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('🔔 Pending: ${pending.length}',
            style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: pending.isEmpty
              ? const Text('No notifications scheduled.\nThis means pre-match reminders are NOT queued.',
                  style: TextStyle(color: AppColors.text2, fontSize: 13))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: pending.length.clamp(0, 20),
                  itemBuilder: (_, i) {
                    final n = pending[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${n.title ?? '(no title)'}',
                          style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }



  // ─── DEMO LIVE MATCH ─────────────────────────────────────
  Future<void> _startDemoMatch() async {
    // Pick first upcoming match
    final upcoming = _matches.where((m) => m.status == MatchStatus.upcoming).toList();
    if (upcoming.isEmpty) {
      _snack('No upcoming matches to demo', AppColors.red, Colors.white);
      return;
    }
    final match = upcoming.first;
    _demoMatchId = match.id;
    _demoHome = 0;
    _demoAway = 0;

    // Write to Firestore as live
    final demoMatch = Match(
      id: match.id, homeTeam: match.homeTeam, awayTeam: match.awayTeam,
      homeTeamCode: match.homeTeamCode, awayTeamCode: match.awayTeamCode,
      homeTeamLogo: match.homeTeamLogo, awayTeamLogo: match.awayTeamLogo,
      group: match.group, venue: match.venue,
      kickoff: DateTime.now().subtract(const Duration(minutes: 5)),
      status: MatchStatus.live, homeScore: 0, awayScore: 0, displayClock: '1\'',
    );
    await _firestore.upsertDemoMatch(demoMatch);
    setState(() {});

    // Increment score every 30s
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_demoMatchId == null) return;
      // Randomly increment home or away
      final rand = DateTime.now().millisecond % 3;
      if (rand == 0) _demoHome++;
      else if (rand == 1) _demoAway++;
      // else no goal this tick
      await _firestore.updateDemoScore(_demoMatchId!, _demoHome, _demoAway);
    });

    _snack('🎮 Demo match started: ${match.homeTeam} vs ${match.awayTeam}', AppColors.gold, AppColors.bg);
  }

  Future<void> _stopDemoMatch() async {
    _demoTimer?.cancel();
    _demoTimer = null;
    if (_demoMatchId != null) {
      await _firestore.deleteDemoMatch(_demoMatchId!);
      _demoMatchId = null;
    }
    setState(() {});
    _snack('Demo match stopped.', AppColors.text2, AppColors.bg);
  }

  // ─── HELPERS ─────────────────────────────────────────────
  void _snack(String msg, Color bg, Color fg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: bg,
      content: Text(msg, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    ));
  }

  Future<void> _backfillKickoffTimes() async {
    if (!await _confirm('🕐 Backfill Kickoff Times?',
        'This will add kickoffTime to all predictions that don\'t have it by looking up the match kickoff times.')) return;
    setState(() => _busy = true);
    try {
      final count = await _firestore.backfillKickoffTimes();
      _snack('✅ Updated $count predictions', AppColors.gold, AppColors.bg);
    } catch (e) {
      _snack('Error: $e', Colors.red.shade900, Colors.white);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(color: AppColors.text2, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text3))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ) ?? false;
  }

  // ─── BUILD ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          const Icon(Icons.admin_panel_settings, color: AppColors.gold, size: 18),
          const SizedBox(width: 8),
          const Text('Superadmin', style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (_busy) const SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.text3,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'MATCHES'),
            Tab(text: 'USERS'),
            Tab(text: 'LEADERBOARD'),
            Tab(text: 'DANGER'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MatchesTab(
            matches: _matches,
            loading: _loadingMatches,
            settling: _settling,
            onRefresh: _loadMatches,
            onSettle: _showSettleDialog,
            onDelete: _deleteMatchPredictions,
          ),
          _UsersTab(
            users: _users,
            loading: _loadingUsers,
            currentUid: user.uid,
            onRefresh: _loadUsers,
            onEditPoints: _editUserPoints,
            onDeleteUser: _deleteUser,
          ),
          _LeaderboardTab(users: _users, onRefreshRanks: _refreshRanks),
          _DangerTab(
            demoMatchId: _demoMatchId,
            onDeleteAll: _deleteAllPredictions,
            onTestNotification: _testNotification,
            onTestScheduledNotification: _testScheduledNotification,
            onShowPendingNotifications: _showPendingNotifications,
            onStartDemo: _startDemoMatch,
            onStopDemo: _stopDemoMatch,
            onRefreshRanks: _refreshRanks,
            onRecalcScores: _recalcAllScores,
            onBackfillKickoff: _backfillKickoffTimes,
            onSyncMatches: _syncMatchesToFirestore,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 1 — MATCHES
// ═══════════════════════════════════════════════════════════
class _MatchesTab extends StatelessWidget {
  final List<Match> matches;
  final bool loading;
  final String? settling;
  final VoidCallback onRefresh;
  final Function(Match) onSettle;
  final Function(Match) onDelete;
  const _MatchesTab({required this.matches, required this.loading,
    required this.settling, required this.onRefresh,
    required this.onSettle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    final live = matches.where((m) => m.status == MatchStatus.live).toList();
    final finished = matches.where((m) => m.status == MatchStatus.finished).toList();
    final upcoming = matches.where((m) => m.status == MatchStatus.upcoming).toList();
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${matches.length} matches total  ·  ${live.length} live  ·  ${finished.length} finished  ·  ${upcoming.length} upcoming',
            style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 8),
          if (live.isNotEmpty) ...[
            _label('🔴 LIVE'),
            ...live.map((m) => _MatchRow(m, settling: settling, onSettle: onSettle, onDelete: onDelete)),
          ],
          if (upcoming.isNotEmpty) ...[
            _label('UPCOMING'),
            ...upcoming.map((m) => _MatchRow(m, settling: settling, onSettle: onSettle, onDelete: onDelete)),
          ],
          if (finished.isNotEmpty) ...[
            _label('FINISHED'),
            ...finished.map((m) => _MatchRow(m, settling: settling, onSettle: onSettle, onDelete: onDelete)),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
    child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        letterSpacing: 1.6, color: AppColors.text3)));
}

class _MatchRow extends StatelessWidget {
  final Match match;
  final String? settling;
  final Function(Match) onSettle;
  final Function(Match) onDelete;
  const _MatchRow(this.match, {required this.settling, required this.onSettle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isSettling = settling == match.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FlagImage(logoUrl: match.homeTeamLogo, width: 24, height: 16),
          const SizedBox(width: 6),
          Expanded(child: Text('${match.homeTeam} vs ${match.awayTeam}',
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600))),
          if (match.homeScore != null)
            Text('${match.homeScore}–${match.awayScore}',
              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          FlagImage(logoUrl: match.awayTeamLogo, width: 24, height: 16),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          StatusBadge(status: match.status, clock: match.displayClock, kickoff: match.kickoff),
          const SizedBox(width: 6),
          Text(match.group, style: const TextStyle(color: AppColors.text3, fontSize: 10)),
          const Spacer(),
          // Delete predictions button
          GestureDetector(
            onTap: () => onDelete(match),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.redDim,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.red.withOpacity(0.3)),
              ),
              child: const Text('Del preds', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 6),
          // Settle / Re-settle button
          if (isSettling)
            const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2))
          else
            GestureDetector(
              onTap: () => onSettle(match),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: match.status == MatchStatus.upcoming ? AppColors.cardRaised : AppColors.goldDim,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: match.status == MatchStatus.upcoming
                      ? AppColors.border : AppColors.gold.withOpacity(0.3)),
                ),
                child: Text(
                  match.status == MatchStatus.finished ? 'Re-settle' : 'Settle',
                  style: TextStyle(
                    color: match.status == MatchStatus.upcoming ? AppColors.text3 : AppColors.gold,
                    fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 2 — USERS
// ═══════════════════════════════════════════════════════════
class _UsersTab extends StatelessWidget {
  final List<UserModel> users;
  final bool loading;
  final String currentUid;
  final VoidCallback onRefresh;
  final Function(UserModel) onEditPoints;
  final Function(UserModel) onDeleteUser;
  const _UsersTab({required this.users, required this.loading,
    required this.currentUid, required this.onRefresh,
    required this.onEditPoints, required this.onDeleteUser});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('${users.length} registered users', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
          const SizedBox(height: 8),
          ...users.map((u) => _UserRow(
            user: u,
            isCurrentUser: u.id == currentUid,
            onEditPoints: () => onEditPoints(u),
            onDelete: () => onDeleteUser(u),
          )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserModel user;
  final bool isCurrentUser;
  final VoidCallback onEditPoints;
  final VoidCallback onDelete;
  const _UserRow({required this.user, required this.isCurrentUser,
    required this.onEditPoints, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCurrentUser ? AppColors.gold.withOpacity(0.4) : AppColors.border),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.cardRaised,
          backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          child: user.photoUrl == null
              ? Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(user.displayName,
              style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
            if (isCurrentUser) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.goldDim, borderRadius: BorderRadius.circular(4)),
                child: const Text('YOU', style: TextStyle(color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ],
            if (user.isAdmin) ...[
              const SizedBox(width: 4),
              const Icon(Icons.admin_panel_settings, color: AppColors.gold, size: 14),
            ],
          ]),
          Text('${user.totalPoints} pts  ·  rank #${user.rank}  ·  ${user.predictionsCount} preds',
            style: const TextStyle(color: AppColors.text3, fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onEditPoints,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.goldDim,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.gold.withOpacity(0.2)),
            ),
            child: const Text('Edit pts', style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        if (!isCurrentUser) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.redDim,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.red.withOpacity(0.2)),
              ),
              child: const Text('Delete', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 3 — LEADERBOARD
// ═══════════════════════════════════════════════════════════
class _LeaderboardTab extends StatelessWidget {
  final List<UserModel> users;
  final VoidCallback onRefreshRanks;
  const _LeaderboardTab({required this.users, required this.onRefreshRanks});

  @override
  Widget build(BuildContext context) {
    final text = users.asMap().entries.map((e) =>
      '#${e.key + 1}  ${e.value.displayName}: ${e.value.totalPoints} pts').join('\n');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Expanded(child: Text('Current Standings',
            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700))),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.goldDim),
            onPressed: onRefreshRanks,
            icon: const Icon(Icons.refresh, color: AppColors.gold, size: 16),
            label: const Text('Recalc Ranks', style: TextStyle(color: AppColors.gold, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.cardRaised),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              backgroundColor: AppColors.card,
              content: Text('Leaderboard copied to clipboard', style: TextStyle(color: AppColors.text))));
          },
          icon: const Icon(Icons.copy, color: AppColors.text2, size: 16),
          label: const Text('Copy to Clipboard', style: TextStyle(color: AppColors.text2, fontSize: 12)),
        ),
        const SizedBox(height: 12),
        ...users.asMap().entries.map((e) {
          final u = e.value;
          final rank = e.key + 1;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: rank <= 3 ? AppColors.goldDim : AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: rank <= 3 ? AppColors.gold.withOpacity(0.2) : AppColors.border),
            ),
            child: Row(children: [
              SizedBox(width: 28, child: Text('#$rank',
                style: TextStyle(
                  color: rank <= 3 ? AppColors.gold : AppColors.text3,
                  fontSize: 12, fontWeight: FontWeight.w800))),
              Expanded(child: Text(u.displayName,
                style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600))),
              Text('${u.totalPoints} pts',
                style: const TextStyle(color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('(${u.predictionsCount} preds)',
                style: const TextStyle(color: AppColors.text3, fontSize: 11)),
            ]),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TAB 4 — DANGER ZONE
// ═══════════════════════════════════════════════════════════
class _DangerTab extends StatelessWidget {
  final String? demoMatchId;
  final VoidCallback onDeleteAll;
  final VoidCallback onTestNotification;
  final VoidCallback onTestScheduledNotification;
  final VoidCallback onShowPendingNotifications;
  final VoidCallback onStartDemo;
  final VoidCallback onStopDemo;
  final VoidCallback onRefreshRanks;
  final VoidCallback onRecalcScores;
  final VoidCallback onBackfillKickoff;
  final VoidCallback onSyncMatches;
  const _DangerTab({
    this.demoMatchId,
    required this.onDeleteAll,
    required this.onTestNotification,
    required this.onTestScheduledNotification,
    required this.onShowPendingNotifications,
    required this.onStartDemo,
    required this.onStopDemo,
    required this.onRefreshRanks,
    required this.onRecalcScores,
    required this.onBackfillKickoff,
    required this.onSyncMatches,
  });

  @override
  Widget build(BuildContext context) {
    final demoRunning = demoMatchId != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: '🎮 Testing',
          color: AppColors.blue,
          children: [
            _ActionTile(
              icon: demoRunning ? Icons.stop_circle : Icons.play_circle,
              color: demoRunning ? AppColors.red : AppColors.green,
              title: demoRunning ? 'Stop demo match' : 'Start demo live match',
              subtitle: demoRunning
                  ? 'Currently running - score increments every 30s'
                  : 'Makes first upcoming match live with auto-incrementing score',
              onTap: demoRunning ? onStopDemo : onStartDemo,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '🔔 Notifications',
          color: AppColors.gold,
          children: [
            _ActionTile(
              icon: Icons.notifications_active,
              color: AppColors.gold,
              title: 'Send test notification',
              subtitle: 'Fires an instant notification to verify setup',
              onTap: onTestNotification,
            ),
            _ActionTile(
              icon: Icons.alarm,
              color: AppColors.orange,
              title: 'Schedule test (30 seconds)',
              subtitle: 'Schedules via zonedSchedule — background the app, should fire in 30s',
              onTap: onTestScheduledNotification,
            ),
            _ActionTile(
              icon: Icons.list_alt,
              color: AppColors.blue,
              title: 'Show pending notifications',
              subtitle: 'Lists scheduled pre-match reminders — should show upcoming matches',
              onTap: onShowPendingNotifications,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '♻️ Maintenance',
          color: AppColors.orange,
          children: [
            _ActionTile(
              icon: Icons.leaderboard,
              color: AppColors.orange,
              title: 'Recalculate all ranks',
              subtitle: 'Re-orders leaderboard based on current points',
              onTap: onRefreshRanks,
            ),
            _ActionTile(
              icon: Icons.refresh_outlined,
              color: AppColors.gold,
              title: 'Recalculate all scores',
              subtitle: 'Re-scores every settled prediction with current point values (use after changing scoring system)',
              onTap: onRecalcScores,
            ),
            _ActionTile(
              icon: Icons.schedule,
              color: AppColors.blue,
              title: 'Backfill kickoff times',
              subtitle: 'Adds kickoffTime to old predictions that don\'t have it',
              onTap: onBackfillKickoff,
            ),
            _ActionTile(
              icon: Icons.cloud_sync,
              color: AppColors.blue,
              title: 'Sync matches from ESPN',
              subtitle: 'Fetches all matches from ESPN and updates Firestore (fixes missing kickoff times)',
              onTap: onSyncMatches,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '⚠️ Danger Zone',
          color: AppColors.red,
          children: [
            _ActionTile(
              icon: Icons.delete_forever,
              color: AppColors.red,
              title: 'Delete ALL predictions',
              subtitle: 'Wipes every prediction and resets all user points to 0',
              onTap: onDeleteAll,
              destructive: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;
  const _Section({required this.title, required this.color, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      ),
    ]);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionTile({required this.icon, required this.color, required this.title,
    required this.subtitle, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title, style: TextStyle(color: destructive ? AppColors.red : AppColors.text,
          fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.text3, fontSize: 11)),
      onTap: onTap,
      trailing: Icon(Icons.chevron_right, color: AppColors.text3, size: 18),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════
class _ScoreSelector extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _ScoreSelector({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 11),
        overflow: TextOverflow.ellipsis),
      const SizedBox(height: 8),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _Btn(icon: Icons.remove, onTap: () => onChanged((value - 1).clamp(0, 20))),
        const SizedBox(width: 10),
        Text('$value', style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        _Btn(icon: Icons.add, onTap: () => onChanged((value + 1).clamp(0, 20))),
      ]),
    ]);
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
        child: Icon(icon, size: 16, color: AppColors.text2),
      ),
    );
  }
}

