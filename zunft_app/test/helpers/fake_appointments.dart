import 'dart:typed_data';

import 'package:zunft_app/features/appointments/data/appointments_remote.dart';
import 'package:zunft_app/features/appointments/application/reminder_providers.dart';
import 'package:zunft_app/features/appointments/data/external_actions.dart';
import 'package:zunft_app/features/appointments/data/reminder_scheduler.dart';

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
