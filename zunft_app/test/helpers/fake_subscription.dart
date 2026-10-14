import 'package:zunft_app/features/subscription/data/subscription_remote.dart';
import 'package:zunft_app/features/subscription/domain/subscription.dart';

/// What the server says about the subscription. Everything is fine unless a test says otherwise.
class FakeSubscriptionRemote implements SubscriptionRemote {
  FakeSubscriptionRemote([this.value]);

  Subscription? value;
  bool offline = false;
  int fetches = 0;

  static Subscription full() => const Subscription(status: 'active', access: 'full');

  static Subscription readOnly() => Subscription(status: 'canceled', access: 'readonly', paidUntil: DateTime(2026, 9, 1));

  static Subscription grace() => Subscription(
        status: 'past_due',
        access: 'grace',
        paidUntil: DateTime.now().subtract(const Duration(days: 2)),
        graceEndsAt: DateTime.now().add(const Duration(days: 5)),
      );

  static Subscription trial(int daysLeft) => Subscription(
        status: 'trialing',
        access: 'full',
        trialEndsAt: DateTime.now().add(Duration(days: daysLeft, hours: 1)),
      );

  @override
  Future<Subscription> fetch() async {
    fetches++;
    if (offline) throw Exception('offline');
    return value ?? full();
  }
}
