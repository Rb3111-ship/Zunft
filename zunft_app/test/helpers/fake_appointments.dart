import 'dart:async';
import 'dart:typed_data';

import 'package:zunft_app/features/appointments/data/appointments_remote.dart';
import 'package:zunft_app/features/appointments/application/reminder_providers.dart';
import 'package:zunft_app/features/appointments/data/external_actions.dart';
import 'package:zunft_app/features/appointments/data/reminder_scheduler.dart';
import 'package:zunft_app/features/push/application/push_providers.dart';
import 'package:zunft_app/features/push/data/push_remote.dart';
import 'package:zunft_app/features/push/data/push_service.dart';

class FakeAppointmentsRemote implements AppointmentsRemote {
  final List<({String id, String status})> calls = [];
  AppointmentException? error;

  @override
  Future<void> setStatus(String id, String status) async {
    if (error != null) throw error!;
    calls.add((id: id, status: status));
  }
}

class FakeExternalActions implements ExternalActions {
  final List<Uri> opened = [];
  final List<({String text, String? subject})> texts = [];
  final List<({String name, Uint8List bytes})> calendarFiles = [];
  bool canOpen = true;

  @override
  Future<bool> openUrl(Uri uri) async {
    opened.add(uri);
    return canOpen;
  }

  @override
  Future<void> shareText(String text, {String? subject}) async => texts.add((text: text, subject: subject));

  @override
  Future<void> shareCalendarFile(Uint8List bytes, String fileName) async =>
      calendarFiles.add((name: fileName, bytes: bytes));
}

class FakeReminderScheduler implements ReminderScheduler {
  bool allow = true;
  int permissionRequests = 0;

  /// What was planned last (and how often the plan was replaced).
  List<Reminder> planned = [];
  int replaced = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    planned = reminders;
    replaced++;
  }
}

class FakeReminderPrefsStore implements ReminderPrefsStore {
  FakeReminderPrefsStore([this.prefs = const ReminderPrefs()]);
  ReminderPrefs prefs;

  @override
  Future<ReminderPrefs> load() async => prefs;

  @override
  Future<void> save(ReminderPrefs p) async => prefs = p;
}

class FakePushService implements PushService {
  bool allow = true;
  String? currentToken = 'fcm-token-1';
  int permissionRequests = 0;
  bool tokenDeleted = false;
  final tokenController = StreamController<String>.broadcast();
  final messageController = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenChanges => tokenController.stream;

  @override
  Stream<PushMessage> get messages => messageController.stream;

  @override
  Future<void> deleteToken() async => tokenDeleted = true;
}

class FakePushRemote implements PushRemote {
  final List<String> calls = []; // 'register:<token>' / 'unregister:<token>'
  Object? error;

  @override
  Future<void> register(String token) async {
    if (error != null) throw error!;
    calls.add('register:$token');
  }

  @override
  Future<void> unregister(String token) async {
    if (error != null) throw error!;
    calls.add('unregister:$token');
  }
}

class FakePushPrefsStore implements PushPrefsStore {
  FakePushPrefsStore([this.prefs = const PushPrefs()]);
  PushPrefs prefs;

  @override
  Future<PushPrefs> load() async => prefs;

  @override
  Future<void> save(PushPrefs p) async => prefs = p;
}
