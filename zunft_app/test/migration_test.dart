import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:zunft_app/core/database/app_database.dart';

void main() {
  test('a database that already has the new columns but announces an old version still opens', () async {
    final dir = Directory.systemTemp.createTempSync('zunft_mig');
    final file = File('${dir.path}/db.sqlite');
    try {
      final first = AppDatabase(NativeDatabase(file));
      await first.setMeta('k', 'v');
      await first.close();

      final raw = sql.sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 3'); // e.g. restored from a backup in a half-upgraded state
      raw.dispose();

      final again = AppDatabase(NativeDatabase(file));
      expect(await again.getMeta('k'), 'v');
      expect(await again.customSelect('PRAGMA user_version').getSingle().then((r) => r.read<int>('user_version')), 9);
      await again.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
