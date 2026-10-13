import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../team/domain/team_models.dart';
import 'time_models.dart';

/// One position of the tracked working time on an invoice: some hours at one hourly rate.
class TimeBillingLine {
  const TimeBillingLine({required this.description, required this.minutes, required this.rateCents});

  final String description;
  final int minutes;
  final int rateCents;
}

/// The tracked time of [entries] as invoice positions. A person with their own hourly rate is
/// billed at that rate, everyone else at [defaultRateCents]. Time at the same rate is one position;
/// when the rates differ there is one position per rate, named after the role (for example
/// "Arbeitszeit Meister (Zeiterfassung)"), highest rate first. Names of people are not printed.
List<TimeBillingLine> timeBillingLines({
  required Iterable<TimeEntry> entries,
  required Map<String, int> rates,
  required Map<String, String> roles,
  required int defaultRateCents,
  required DateTime now,
}) {
  final minutesByRate = <int, int>{};
  final rolesByRate = <int, Set<String>>{};
  for (final t in entries) {
    final rate = (t.userId == null ? null : rates[t.userId]) ?? defaultRateCents;
    final m = t.minutes(now);
    if (m <= 0) continue;
    minutesByRate[rate] = (minutesByRate[rate] ?? 0) + m;
    final role = t.userId == null ? null : roles[t.userId];
    rolesByRate.putIfAbsent(rate, () => {});
    if (role != null) rolesByRate[rate]!.add(role);
  }
  if (minutesByRate.isEmpty) return const [];
  if (minutesByRate.length == 1) {
    final e = minutesByRate.entries.single;
    return [TimeBillingLine(description: 'Arbeitszeit (Zeiterfassung)', minutes: e.value, rateCents: e.key)];
  }

  final ordered = minutesByRate.keys.toList()..sort((a, b) => b.compareTo(a));
  String base(int rate) {
    final r = rolesByRate[rate]!;
    return r.length == 1 ? 'Arbeitszeit ${Roles.labelDe(r.single)} (Zeiterfassung)' : 'Arbeitszeit (Zeiterfassung)';
  }

  final counts = <String, int>{};
  for (final rate in ordered) {
    counts[base(rate)] = (counts[base(rate)] ?? 0) + 1;
  }
  return [
    for (final rate in ordered)
      TimeBillingLine(
        // two positions with the same name would look like a mistake: the rate tells them apart
        description: counts[base(rate)]! > 1 ? '${base(rate)}, ${CurrencyFormatter.formatCents(rate)}/Std' : base(rate),
        minutes: minutesByRate[rate]!,
        rateCents: rate,
      ),
  ];
}
