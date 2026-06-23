import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/match.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'match_reminders';
  static const _channelName = 'Match Reminders';
  static const _channelDesc = 'Reminder 10 minutes before each match';

  // Stream that emits when a notification is tapped — listeners navigate to appropriate tab
  static final _tapController = StreamController<String?>.broadcast();
  static Stream<String?> get onNotificationTap => _tapController.stream;

  // Stores the last tapped payload so HomeShell can read it on app resume.
  // Broadcast streams lose events if nobody is subscribed at the exact moment of add().
  static String? _pendingTapPayload;
  static String? consumePendingTapPayload() {
    final p = _pendingTapPayload;
    _pendingTapPayload = null;
    return p;
  }

  // Payload stored when app is launched from a terminated state via notification tap.
  static String? _launchPayload;
  static String? consumeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    // Set local timezone so scheduled notifications fire at the correct local time
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload ?? 'schedule';
        _pendingTapPayload = payload;
        _tapController.add(payload);
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
    );

    // Handle tap when app was fully terminated and launched by notification
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchPayload = launchDetails?.notificationResponse?.payload ?? 'schedule';
    }

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  static Future<void> scheduleMatchReminders(
    List<Match> matches,
  ) async {
    // Only cancel the specific reminder IDs we manage — never touch post-match
    // or other notifications that may have just fired
    final reminderIds = matches
        .map((m) => m.id.hashCode.abs() % 2000000000)
        .toSet();
    for (final id in reminderIds) {
      await _plugin.cancel(id);
    }

    final now = DateTime.now();

    for (final match in matches) {
      if (match.status != MatchStatus.upcoming) continue;
      final reminderTime = match.kickoff.subtract(const Duration(minutes: 10));
      if (reminderTime.isBefore(now)) continue;

      final tzTime = tz.TZDateTime.from(reminderTime, tz.local);
      final notifId = match.id.hashCode.abs() % 2000000000;
      const body = '⏱️ Last chance! Lock in your prediction now 🔒';

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      );

      // Try exact alarm first; fall back to inexact if denied/unavailable
      try {
        await _plugin.zonedSchedule(
          notifId,
          '⚽ ${match.homeTeam} vs ${match.awayTeam}',
          body,
          tzTime,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'schedule',
        );
      } catch (_) {
        // Exact alarm permission denied — fall back to inexact (may fire slightly late)
        try {
          await _plugin.zonedSchedule(
            notifId,
            '⚽ ${match.homeTeam} vs ${match.awayTeam}',
            body,
            tzTime,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'schedule',
          );
        } catch (e) {
          debugPrint('Could not schedule notification for ${match.homeTeam} vs ${match.awayTeam}: $e');
        }
      }
    }
  }

  /// Fires an immediate test notification (no scheduling delay).
  static Future<void> sendTestNotification() async {
    await _plugin.show(
      999999,
      '⚽ Test: USA vs Mexico',
      'Kicks off in 10 minutes! Lock in your prediction now 🔒',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: 'schedule',
    );
  }

  /// Fires a post-match result notification immediately.
  static Future<void> showPostMatchNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true, presentBadge: true, presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  /// Fire a navigation event — used for terminated-state launch where the stream
  /// callback never fires (only getNotificationAppLaunchDetails runs).
  static void fireNavigation(String? payload) {
    _tapController.add(payload ?? 'schedule');
  }

  static Future<int> pendingCount() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }
}

// Top-level handler required by flutter_local_notifications for background taps
@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {
  // Background tap — navigates to schedule when app opens
  // The foreground handler (onDidReceiveNotificationResponse) handles active app taps
}
