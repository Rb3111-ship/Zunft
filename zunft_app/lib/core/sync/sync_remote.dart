import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';

/// No usable network (or the server is unreachable). Retry later; keep the outbox.
class SyncOfflineException implements Exception {
  const SyncOfflineException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'SyncOfflineException($cause)';
}

/// The session is no longer valid. Stop syncing until the user signs in again.
class SyncAuthException implements Exception {
  const SyncAuthException();
}

/// The server refused this one change (validation, RLS, constraint). Other changes can continue.
class SyncRejectedException implements Exception {
  const SyncRejectedException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'SyncRejectedException($code: $message)';
}

/// Server side of sync. Rows are plain JSON maps in the database's column naming.
abstract class SyncRemote {
  /// Rows with `updated_at >= since` (raw server timestamp string), oldest first.
  Future<List<Map<String, dynamic>>> fetchChanged(SyncEntity entity, {String? since, required int limit});

  Future<Set<String>> fetchIds(SyncEntity entity);

  Future<void> upsert(SyncEntity entity, Map<String, dynamic> row);

  Future<void> delete(SyncEntity entity, String id);
}

String tableOf(SyncEntity e) => switch (e) {
      SyncEntity.customer => 'customers',
      SyncEntity.job => 'jobs',
      SyncEntity.document => 'documents',
      SyncEntity.appointment => 'appointments',
    };

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(SyncEntity entity, {String? since, required int limit}) =>
      _guard(() async {
        var q = _client.from(tableOf(entity)).select();
        if (since != null) q = q.gte('updated_at', since);
        final rows = await q.order('updated_at', ascending: true).order('id', ascending: true).limit(limit);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<Set<String>> fetchIds(SyncEntity entity) => _guard(() async {
        // PostgREST caps a response at 1000 rows. A truncated id list would make the caller
        // prune live rows, so page through everything.
        const page = 1000;
        final ids = <String>{};
        for (var from = 0;; from += page) {
          final rows = await _client
              .from(tableOf(entity))
              .select('id')
              .order('id', ascending: true)
              .range(from, from + page - 1);
          ids.addAll(rows.map<String>((r) => r['id'] as String));
          if (rows.length < page) break;
        }
        return ids;
      });

  @override
  Future<void> upsert(SyncEntity entity, Map<String, dynamic> row) => _guard(() async {
        // Not .upsert(): INSERT ... ON CONFLICT also checks the SELECT policy against the new row,
        // and for jobs that policy looks the row up in the table, where it does not exist yet.
        // So the server refused every new job. Insert, and update if the row is already there.
        final table = _client.from(tableOf(entity));
        try {
          await table.insert(row);
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow;
          await table.update(row).eq('id', row['id'] as String);
        }
      });

  @override
  Future<void> delete(SyncEntity entity, String id) =>
      _guard(() async => _client.from(tableOf(entity)).delete().eq('id', id));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 30));
    } on PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (e.code == 'PGRST301' || e.code == 'PGRST303' || msg.contains('jwt')) throw const SyncAuthException();
      throw SyncRejectedException(e.message, code: e.code);
    } on AuthException {
      throw const SyncAuthException();
    } on SyncAuthException {
      rethrow;
    } catch (e) {
      // SocketException, ClientException, TimeoutException, ...
      throw SyncOfflineException(e);
    }
  }
}
