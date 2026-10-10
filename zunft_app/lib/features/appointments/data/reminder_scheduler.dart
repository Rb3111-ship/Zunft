import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// One notification the phone should show at [at].
class Reminder {
  const Reminder({required this.id, required this.title, required this.body, required this.at});

  final int id;
  final String title;
  final String body;
  final DateTime at;
}

/// Plans notifications on this phone (they appear even when the app is closed and when there is no
/// connection). Behind an interface so tests need no phone.
abstract class ReminderScheduler {
  /// Asks the person for permission to show notifications (Android 13+, iOS). true if allowed.
  Future<bool> requestPermission();

  /// Cancels everything planned before and plans exactly [reminders].
  Future<void> replaceAll(List<Reminder> reminders);
}

class LocalNotificationsScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Berlin')); // the business is German
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
            requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    try {
      await _init();
      await _plugin.cancelAllPendingNotifications();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'appointments',
          'Terminerinnerungen',
          channelDescription: 'Erinnerung vor einem Termin',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      for (final r in reminders) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: details,
          // Not exact: no special permission needed, and a reminder a few minutes late is fine.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Reminders are a convenience: never let them break the calendar.
    }
  }
}
