import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/team_models.dart';

/// A team action failed. [message] is German and safe to show.
class TeamException implements Exception {
  const TeamException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Server access for the team, invitations and job assignments. Faked in tests.
abstract class TeamRemote {
  /// Everyone in the business, the open invitations (owner only; empty for others) and the plan.
  Future<TeamOverview> fetchOverview();

  Future<TeamInvite> createInvite(String role);
  Future<void> revokeInvite(String id);

  /// Switches a person's access off or on. Their notes stay.
  Future<void> setMemberActive(String userId, bool active);

  /// The people a job is assigned to.
  Future<Set<String>> fetchAssignees(String jobId);

  /// Replaces the list of people on a job.
  Future<void> setAssignees(String jobId, Set<String> userIds);
}

class SupabaseTeamRemote implements TeamRemote {
  SupabaseTeamRemote(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<TeamOverview> fetchOverview() => _guard(() async {
        final members = await _client.from('profiles').select('id, full_name, role, active').order('full_name');
        final plan = await _client.from('businesses').select('seat_limit').single();
        final invites = await _client
            .from('invites')
            .select('id, code, role, expires_at')
            .isFilter('used_at', null)
            .isFilter('revoked_at', null)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at');
        return TeamOverview(
          members: [for (final m in members) TeamMember.fromJson(Map<String, dynamic>.from(m))],
          invites: [for (final i in invites) TeamInvite.fromJson(Map<String, dynamic>.from(i))],
          seatLimit: (plan['seat_limit'] as num).toInt(),
        );
      });

  @override
  Future<TeamInvite> createInvite(String role) => _guard(() async {
        final res = await _client.rpc('create_invite', params: {'p_role': role});
        return TeamInvite.fromJson(Map<String, dynamic>.from(res as Map));
      });

  @override
  Future<void> revokeInvite(String id) => _guard(() async {
        await _client.rpc('revoke_invite', params: {'p_id': id});
      });

  @override
  Future<void> setMemberActive(String userId, bool active) => _guard(() async {
        await _client.rpc('set_member_active', params: {'p_user': userId, 'p_active': active});
      });

  @override
  Future<Set<String>> fetchAssignees(String jobId) => _guard(() async {
        final rows = await _client.from('job_assignments').select('user_id').eq('job_id', jobId);
        return {for (final r in rows) r['user_id'] as String};
      });

  @override
  Future<void> setAssignees(String jobId, Set<String> userIds) => _guard(() async {
        await _client.rpc('set_job_assignees', params: {'p_job': jobId, 'p_users': userIds.toList()});
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(_timeout);
    } on PostgrestException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('no free seat')) {
        throw const TeamException('Alle Plätze deines Pakets sind belegt. Für mehr Personen wird ein größeres Paket gebraucht.');
      }
      if (m.contains('not allowed') || e.code == '42501') {
        throw const TeamException('Dafür fehlt die Berechtigung.');
      }
      if (m.contains('owner cannot')) throw const TeamException('Der Inhaber kann nicht abgeschaltet werden.');
      if (m.contains('person not found')) throw const TeamException('Diese Person gehört nicht zum Betrieb oder ist abgeschaltet.');
      if (m.contains('job not found')) throw const TeamException('Dieser Auftrag existiert nicht mehr.');
      throw const TeamException('Der Server hat die Anfrage abgelehnt. Bitte später erneut versuchen.');
    } catch (e) {
      if (e is TeamException) rethrow;
      throw const TeamException('Keine Verbindung. Bitte Internet prüfen und erneut versuchen.');
    }
  }
}
