import '../../../core/i18n/i18n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/auth_providers.dart';
import '../data/reminder_scheduler.dart';
import '../domain/reminder_plan.dart';
import 'appointment_providers.dart';

/// The reminder settings of THIS phone (not synced: every device decides for itself).
class ReminderPrefs {
  const ReminderPrefs({this.enabled = false, this.leadMinutes = 30});
  final bool enabled;
  final int leadMinutes;
}

abstract class ReminderPrefsStore {
  Future<ReminderPrefs> load();
  Future<void> save(ReminderPrefs prefs);
}

class SharedPrefsReminderStore implements ReminderPrefsStore {
  @override
  Future<ReminderPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return ReminderPrefs(enabled: p.getBool('reminders_enabled') ?? false, leadMinutes: p.getInt('reminders_lead') ?? 30);
  }

  @override
  Future<void> save(ReminderPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('reminders_enabled', prefs.enabled);
    await p.setInt('reminders_lead', prefs.leadMinutes);
  }
}

class ReminderState {
  const ReminderState({this.loaded = false, this.enabled = false, this.leadMinutes = 30});
  final bool loaded;
  final bool enabled;
  final int leadMinutes;

  ReminderState copyWith({bool? loaded, bool? enabled, int? leadMinutes}) => ReminderState(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );
}

/// Tests replace these.
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => LocalNotificationsScheduler());
final reminderPrefsStoreProvider = Provider<ReminderPrefsStore>((ref) => SharedPrefsReminderStore());
final reminderClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final reminderProvider = StateNotifierProvider<ReminderController, ReminderState>(
    (ref) => ReminderController(ref.watch(reminderPrefsStoreProvider), ref.watch(reminderSchedulerProvider)));

class ReminderController extends StateNotifier<ReminderState> {
  ReminderController(this._store, this._scheduler) : super(const ReminderState()) {
    _load();
  }

  final ReminderPrefsStore _store;
  final ReminderScheduler _scheduler;

  Future<void> _load() async {
    final prefs = await _store.load();
    if (mounted) state = ReminderState(loaded: true, enabled: prefs.enabled, leadMinutes: prefs.leadMinutes);
  }

  /// Switching on first asks the phone for permission to show notifications. Returns null if done,
  /// otherwise the reason it was not.
  Future<String?> setEnabled(bool enabled) async {
    if (enabled && !await _scheduler.requestPermission()) {
      return 'Die Erlaubnis für Benachrichtigungen fehlt. Bitte in den Handy-Einstellungen für Zunft erlauben.'.tr;
    }
    await _store.save(ReminderPrefs(enabled: enabled, leadMinutes: state.leadMinutes));
    if (mounted) state = state.copyWith(enabled: enabled);
    return null;
  }

  Future<void> setLead(int minutes) async {
    await _store.save(ReminderPrefs(enabled: state.enabled, leadMinutes: minutes));
    if (mounted) state = state.copyWith(leadMinutes: minutes);
  }
}

/// Keeps the notifications planned on this phone in step with the calendar: whenever an
/// appointment or a setting changes, the plan is made again (cancel all, plan the next ones).
final reminderSyncProvider = Provider<void>((ref) {
  final prefs = ref.watch(reminderProvider);
  final appointments = ref.watch(appointmentsProvider).valueOrNull;
  final userId = ref.watch(profileProvider).valueOrNull?.id;
  ref.watch(languageProvider); // the reminder texts follow the app language
  if (!prefs.loaded) return;
  final scheduler = ref.read(reminderSchedulerProvider);
  if (!prefs.enabled) {
    scheduler.replaceAll(const []);
    return;
  }
  if (appointments == null || userId == null) return;
  scheduler.replaceAll(planReminders(
    appointments: appointments,
    userId: userId,
    now: ref.read(reminderClockProvider)(),
    lead: Duration(minutes: prefs.leadMinutes),
  ));
});
