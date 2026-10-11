import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The phone's side of push messages (Google's Firebase Cloud Messaging). Behind an interface so
/// tests need no phone and no Firebase.
abstract class PushService {
  /// Asks the person for permission to show notifications. true if allowed.
  Future<bool> requestPermission();

  /// The address of this phone at the push service, or null if it has none (yet).
  Future<String?> token();

  /// A new address after the old one expired or the app was restored.
  Stream<String> get tokenChanges;

  /// A push message arrived while the app was open, or the person opened the app by tapping one.
  Stream<void> get messages;

  /// Forgets this phone's address at the push service (the next token is a new one).
  Future<void> deleteToken();
}

class FirebasePushService implements PushService {
  bool _ready = false;
  Future<void>? _starting;

  /// Firebase and the notification channel are set up only when push is really used, so a person
  /// who never switches it on never runs any of it.
  Future<void> _init() => _starting ??= _doInit();

  Future<void> _doInit() async {
    await Firebase.initializeApp(); // reads android/app/google-services.json
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'appointments_push',
          'Terminmeldungen',
          description: 'Meldungen, wenn dir ein Termin zugeteilt, geändert oder abgesagt wird',
          importance: Importance.high,
        ));
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _init();
      final s = await FirebaseMessaging.instance.requestPermission();
      return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> token() async {
    try {
      await _init();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenChanges async* {
    await _init();
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }

  @override
  Stream<void> get messages {
    late final StreamController<void> controller;
    final subs = <StreamSubscription<dynamic>>[];
    controller = StreamController<void>(
      onListen: () async {
        try {
          await _init();
          subs.add(FirebaseMessaging.onMessage.listen((_) => controller.add(null)));
          subs.add(FirebaseMessaging.onMessageOpenedApp.listen((_) => controller.add(null)));
          if (await FirebaseMessaging.instance.getInitialMessage() != null) controller.add(null);
        } catch (_) {
          // no Firebase here: no messages
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> deleteToken() async {
    if (!_ready) return; // never used on this phone
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
