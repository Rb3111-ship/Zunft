import 'package:flutter_test/flutter_test.dart';
import 'package:zunft_app/features/capture/data/storage_status.dart';

import 'helpers/fake_capture.dart';
import 'helpers/job_app.dart';
import 'helpers/test_app.dart';

Future<void> openBetrieb(WidgetTester tester) async {
  await tester.tap(find.text('Betrieb'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sizes are written the German way', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(900), '900 B');
    expect(formatBytes(3236817), '3,1 MB');
    expect(formatBytes(1073741824), '1,0 GB');
  });

  test('fraction, nearly full and full', () {
    const s = StorageStatus(usedBytes: 80, limitBytes: 100);
    expect(s.fraction, 0.8);
    expect(s.nearlyFull, isTrue);
    expect(s.full, isFalse);
    expect(const StorageStatus(usedBytes: 100, limitBytes: 100).full, isTrue);
    expect(const StorageStatus(usedBytes: 500, limitBytes: 100).fraction, 1.0);
    expect(const StorageStatus(usedBytes: 1, limitBytes: 100).nearlyFull, isFalse);
  });

  group('the Speicher card', () {
    testApp('boss sees how much storage is used', (tester) async {
      await pumpJobApp(tester);
      await openBetrieb(tester);
      expect(find.text('Speicher'), findsOneWidget);
      expect(find.text('3,1 MB von 1,0 GB belegt'), findsOneWidget);
      expect(find.textContaining('fast voll'), findsNothing);
    });

    testApp('nearly full: warned', (tester) async {
      await pumpJobApp(tester, captureRemote: FakeCaptureRemote()..storage = const StorageStatus(usedBytes: 900, limitBytes: 1000));
      await openBetrieb(tester);
      expect(find.textContaining('fast voll'), findsOneWidget);
    });

    testApp('full storage says so plainly', (tester) async {
      await pumpJobApp(tester, captureRemote: FakeCaptureRemote()..storage = const StorageStatus(usedBytes: 1000, limitBytes: 1000));
      await openBetrieb(tester);
      expect(find.textContaining('Der Speicher ist voll'), findsOneWidget);
      expect(find.textContaining('Rechnungen können weiter erstellt werden'), findsOneWidget);
    });

    testApp('employees do not see it', (tester) async {
      await pumpJobApp(tester, role: 'geselle');
      await openBetrieb(tester);
      expect(find.text('Speicher'), findsNothing);
    });
  });
}
