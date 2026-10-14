/// The subscription of the business, as the server reports it (`subscription_status()`).
///
/// [access] is the part that matters: "full", "grace" (a payment is late, everything still works for
/// a few days) or "readonly" (nothing new can be created; reading and exporting still work).
class Subscription {
  const Subscription({
    required this.status,
    required this.access,
    this.trialEndsAt,
    this.paidUntil,
    this.graceEndsAt,
  });

  final String status; // trialing | active | past_due | canceled
  final String access; // full | grace | readonly
  final DateTime? trialEndsAt;
  final DateTime? paidUntil;
  final DateTime? graceEndsAt;

  bool get isReadOnly => access == 'readonly';
  bool get isGrace => access == 'grace';
  bool get isTrial => status == 'trialing';

  /// Whole days left of the free trial (0 = ends today), null if this is not a running trial.
  int? trialDaysLeft(DateTime now) {
    if (!isTrial || isReadOnly || trialEndsAt == null) return null;
    final end = trialEndsAt!.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(end.year, end.month, end.day).difference(today).inDays.clamp(0, 9999);
  }

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        status: (j['status'] as String?) ?? 'active',
        access: (j['access'] as String?) ?? 'full',
        trialEndsAt: _date(j['trial_ends_at']),
        paidUntil: _date(j['paid_until']),
        graceEndsAt: _date(j['grace_ends_at']),
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        'access': access,
        'trial_ends_at': trialEndsAt?.toUtc().toIso8601String(),
        'paid_until': paidUntil?.toUtc().toIso8601String(),
        'grace_ends_at': graceEndsAt?.toUtc().toIso8601String(),
      };

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
}
