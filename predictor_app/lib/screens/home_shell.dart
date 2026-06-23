import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/schedule_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/admin_screen.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _isAdmin = false;
  StreamSubscription? _notifSub;
  StreamSubscription? _postMatchSub;
  final _firestore = FirestoreService();

  static const _screens = [
    ScheduleScreen(),
    LeaderboardScreen(),
    ProfileScreen(),
  ];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAdmin();
    // Foreground tap — stream fires while app is active
    _notifSub = NotificationService.onNotificationTap.listen((payload) {
      if (mounted) _navigateForPayload(payload);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Terminated-state launch
      final launch = NotificationService.consumeLaunchPayload();
      if (launch != null && mounted) _navigateFromLaunch(launch);
      _listenPostMatchNotifications();
      if (!kIsWeb && Platform.isAndroid) _checkNotificationPermissions();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final payload = NotificationService.consumePendingTapPayload();
      if (payload != null && mounted) _navigateForPayload(payload);
    }
  }

  void _navigateForPayload(String? payload) {
    setState(() => _index = 0);
  }

  void _navigateFromLaunch(String? payload) {
    setState(() => _index = 0);
    // For terminated-state only: fire the stream so ScheduleScreen switches tab.
    // Safe here because HomeShell's _notifSub is not yet listening (set up before this runs
    // in the same postFrameCallback, but stream events are async microtasks so no loop).
    NotificationService.fireNavigation(payload);
  }

  void _listenPostMatchNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final seen = <String>{};
    _postMatchSub = _firestore.unreadNotificationsStream(uid).listen((snap) async {
      for (final doc in snap.docs) {
        final id = doc.id;
        if (seen.contains(id)) continue;
        seen.add(id);
        final data = doc.data() as Map<String, dynamic>;
        final home = data['homeTeam'] ?? '';
        final away = data['awayTeam'] ?? '';
        final pts = data['pointsEarned'] ?? 0;
        final aHome = data['actualHome'] ?? 0;
        final aAway = data['actualAway'] ?? 0;
        final pHome = data['predHome'] ?? 0;
        final pAway = data['predAway'] ?? 0;
        await _firestore.markNotificationRead(id);
        if (!kIsWeb) {
          await NotificationService.showPostMatchNotification(
            id: id.hashCode.abs() % 2000000000,
            title: '⚽ $home $aHome–$aAway $away · FT',
            body: 'Your pick: $pHome–$pAway  •  +$pts pts earned!',
            payload: 'past',
          );
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSub?.cancel();
    _postMatchSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (mounted && doc.exists && doc.data()?['isAdmin'] == true) {
      setState(() => _isAdmin = true);
    }
  }

  Future<void> _checkNotificationPermissions() async {
    if (!mounted) return;
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    // Step 1: notification permission (Android 13+ POST_NOTIFICATIONS)
    final notifGranted = await android.areNotificationsEnabled() ?? false;
    if (!notifGranted && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.cardRaised,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Text('⚽', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Enable Notifications',
                  style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text(
            'Get a reminder 10 minutes before each match kicks off — so you never miss submitting your prediction.',
            style: TextStyle(color: AppColors.text2, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now', style: TextStyle(color: AppColors.text3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (proceed == true) await android.requestNotificationsPermission();
    }

    // Step 2: exact alarm permission — always check separately.
    // On Android 13+ USE_EXACT_ALARM (manifest) grants this automatically → canSchedule = true → no-op.
    // On Android 12 SCHEDULE_EXACT_ALARM requires user to grant in Settings — we silently open it.
    // Without exact alarms the system may delay notifications by hours in Doze mode.
    final canExact = await android.canScheduleExactNotifications() ?? true;
    if (!canExact) {
      await android.requestExactAlarmsPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset('assets/images/fifa_logo26.webp', height: 26),
            const SizedBox(width: 10),
            Container(width: 1, height: 18, color: AppColors.border),
            const SizedBox(width: 10),
            const Text('Predictor ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text)),
            const Text("'26",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.gold)),
          ],
        ),
        actions: [
          // Real-time points badge
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (_, snap) {
              int pts = 0;
              if (snap.hasData && snap.data!.exists) {
                pts = (snap.data!.data() as Map<String, dynamic>)['totalPoints'] as int? ?? 0;
              }
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.goldDim,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                ),
                child: Text('$pts pts',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold)),
              );
            },
          ),
          const SizedBox(width: 8),
          // Admin button — only visible if user has isAdmin: true in Firestore
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: AppColors.gold, size: 20),
              tooltip: 'Admin',
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminScreen())),
            ),
          GestureDetector(
            onTap: () => setState(() => _index = 2),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _AppBarAvatar(user: user),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _AppBarAvatar extends StatelessWidget {
  final User user;
  const _AppBarAvatar({required this.user});

  String get _initials {
    final name = user.displayName ?? 'P';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ),
        border: Border.all(color: Colors.white24, width: 1.5),
      ),
      child: user.photoURL != null
        ? ClipOval(
            child: Image.network(user.photoURL!, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(_initials,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))))
        : Center(
            child: Text(_initials,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _NavItem(icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today,
                label: 'Schedule', active: index == 0, onTap: () => onTap(0)),
              _NavItem(icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard,
                label: 'Leaderboard', active: index == 1, onTap: () => onTap(1)),
              _NavItem(icon: Icons.person_outline, activeIcon: Icons.person,
                label: 'Profile', active: index == 2, onTap: () => onTap(2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon, required this.activeIcon,
    required this.label, required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? activeIcon : icon,
              size: 22,
              color: active ? AppColors.gold : AppColors.text3),
            const SizedBox(height: 3),
            Text(label,
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: active ? AppColors.gold : AppColors.text3,
              )),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 4, height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.gold : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
