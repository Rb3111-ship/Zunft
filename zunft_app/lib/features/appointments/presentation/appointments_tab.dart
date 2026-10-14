import '../../subscription/presentation/subscription_banner.dart';
import '../../../core/i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/refresh_all.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../customers/presentation/customers_tab.dart' show customerDisplayName;
import '../../data/data_providers.dart';
import '../../team/domain/team_models.dart';
import '../application/appointment_providers.dart';
import '../domain/appointment_models.dart';
import 'appointment_detail_screen.dart';
import 'appointment_edit_screen.dart';

/// The calendar: a day or a week at a time, for everyone or for one person.
class AppointmentsTab extends ConsumerStatefulWidget {
  const AppointmentsTab({super.key});

  @override
  ConsumerState<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends ConsumerState<AppointmentsTab> {
  late DateTime _day = startOfDay(DateTime.now());
  bool _week = false;

  /// null = everyone, otherwise one user id.
  String? _who;

  void _move(int days) => setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  String _monthTitle(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    return monday.month == sunday.month
        ? '${monthNames[monday.month - 1]} ${monday.year}'
        : '${monthNames[monday.month - 1].substring(0, 3)}. / ${monthNames[sunday.month - 1].substring(0, 3)}. ${sunday.year}';
  }

  @override
  Widget build(BuildContext context) {
    final appointments = ref.watch(appointmentsProvider);
    final members = ref.watch(teamMembersProvider).valueOrNull ?? const <TeamMember>[];
    final profile = ref.watch(profileProvider).valueOrNull;
    final canCreate = ref.watch(canCreateRecordsProvider);
    final manager = profile?.isManager ?? false;
    final monday = mondayOf(_day);
    final today = startOfDay(DateTime.now());

    return RefreshIndicator(
      onRefresh: () => refreshAll(ref),
      child: appointments.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accentAmber)),
        error: (e, _) => Center(
          child: TextButton(
              onPressed: () => ref.invalidate(appointmentsProvider),
              child: Text('Termine konnten nicht geladen werden. Erneut versuchen'.tr)),
        ),
        data: (all) {
          final visible = all.where((a) => _who == null || a.assignees.contains(_who)).toList();
          final activeMembers = members.where((m) => m.active).toList();
          int countOn(DateTime d) => appointmentsOnDay(visible, d).where((a) => !a.isCanceled).length;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _week ? 'Vorige Woche'.tr : 'Voriger Tag'.tr,
                    onPressed: () => _move(_week ? -7 : -1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_week ? _monthTitle(monday) : longDateLabel(_day),
                            textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (_week)
                          Text('${dateLabel(monday).substring(0, 6)} - ${dateLabel(monday.add(const Duration(days: 6)))}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _week ? 'Nächste Woche'.tr : 'Nächster Tag'.tr,
                    onPressed: () => _move(_week ? 7 : 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: false, label: Text('Tag'.tr)),
                        ButtonSegment(value: true, label: Text('Woche'.tr)),
                      ],
                      selected: {_week},
                      onSelectionChanged: (s) => setState(() => _week = s.first),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => setState(() => _day = today),
                    child: Text('Heute'.tr),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // The week strip: tap a day.
              Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(child: _dayChip(monday.add(Duration(days: i)), today, countOn(monday.add(Duration(days: i))), i)),
                ],
              ),
              if (activeMembers.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _filterChip('Alle'.tr, null),
                      if (profile != null) _filterChip('Ich'.tr, profile.id),
                      for (final m in activeMembers)
                        if (m.id != profile?.id) _filterChip(m.fullName, m.id),
                    ],
                  ),
                ),
              ],
              if (canCreate)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      if (!await ensureWritable(context, ref) || !context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AppointmentEditScreen(initialDay: _day)),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Neuer Termin'.tr),
                  ),
                ),
              const SizedBox(height: 4),
              if (_week)
                for (var i = 0; i < 7; i++) ..._daySection(visible, monday.add(Duration(days: i)), today, members, showHeader: true)
              else
                ..._daySection(visible, _day, today, members, showHeader: false),
              if (!manager && all.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Hier erscheinen die Termine, die dir zugewiesen wurden.'.tr,
                      textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, String? id) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _who == id,
          onSelected: (_) => setState(() => _who = id),
        ),
      );

  Widget _dayChip(DateTime d, DateTime today, int count, int index) {
    final selected = !_week && d == _day;
    final isToday = d == today;
    return GestureDetector(
      onTap: () => setState(() {
        _day = d;
        _week = false;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentAmber : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: isToday && !selected ? Border.all(color: AppTheme.accentAmber) : null,
        ),
        child: Column(
          children: [
            Text(weekdayShort[index],
                style: TextStyle(fontSize: 11, color: selected ? AppTheme.primaryDark : AppTheme.textSecondary)),
            Text('${d.day}',
                style: TextStyle(fontWeight: FontWeight.bold, color: selected ? AppTheme.primaryDark : null)),
            SizedBox(
              height: 10,
              child: count == 0
                  ? null
                  : Text('•' * (count > 3 ? 3 : count),
                      style: TextStyle(fontSize: 10, color: selected ? AppTheme.primaryDark : AppTheme.accentAmber)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _daySection(List<Appointment> visible, DateTime day, DateTime today, List<TeamMember> members,
      {required bool showHeader}) {
    final items = appointmentsOnDay(visible, day);
    return [
      if (showHeader)
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            '${weekdayNames[day.weekday - 1].toUpperCase()}  ${two(day.day)}.${two(day.month)}.${day == today ? '  ·  ${'HEUTE'.tr}' : ''}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: day == today ? AppTheme.accentAmber : AppTheme.textSecondary),
          ),
        ),
      if (items.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: showHeader ? 4 : 28),
          child: Text(showHeader ? '–' : 'Keine Termine an diesem Tag.'.tr,
              textAlign: showHeader ? TextAlign.start : TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
      for (final a in items) AppointmentCard(appointment: a, day: day, members: members),
    ];
  }
}

/// One appointment in a list: time, title, who, where, and its state.
class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({super.key, required this.appointment, this.day, required this.members});

  final Appointment appointment;

  /// The day the list shows (decides how a multi-day appointment is labelled); null = no day.
  final DateTime? day;
  final List<TeamMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final customers = ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final customer = customers.where((c) => c.id == a.customerId).firstOrNull;
    final names = [
      for (final id in a.assignees) members.where((m) => m.id == id).firstOrNull?.fullName ?? 'Mitarbeiter'.tr,
    ];
    // From midnight to midnight is an all-day entry.
    final allDay = a.start.hour == 0 && a.start.minute == 0 && a.end.hour == 0 && a.end.minute == 0;
    final timeText = allDay ? 'ganztägig'.tr : rangeLabel(a);
    final muted = a.isDone || a.isCanceled;
    final color = a.isAbsence ? AppTheme.accentBlue : AppTheme.accentAmber;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentDetailScreen(appointmentId: a.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 4, height: 54, decoration: BoxDecoration(color: muted ? AppTheme.dividerColor : color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(timeText, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      a.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        decoration: a.isCanceled ? TextDecoration.lineThrough : null,
                        color: muted ? AppTheme.textSecondary : null,
                      ),
                    ),
                    if (customer != null || (a.location ?? '').isNotEmpty)
                      Text(
                        [if (customer != null) customerDisplayName(customer), if ((a.location ?? '').isNotEmpty) a.location!].join(' · '),
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    if (names.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(names.join(', '), style: const TextStyle(fontSize: 12, color: AppTheme.accentBlue)),
                      ),
                  ],
                ),
              ),
              if (a.isDone) const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 22),
              if (a.isCanceled) const Icon(Icons.cancel_outlined, color: AppTheme.textSecondary, size: 22),
              if (a.isAbsence && !muted) Icon(Icons.beach_access_outlined, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
