import 'package:zunft_app/features/team/data/team_remote.dart';
import 'package:zunft_app/features/team/domain/team_models.dart';

/// Stand-in for the team functions in the cloud. Applies the same seat rule: active people plus
/// open invitations may not exceed the plan.
class FakeTeamRemote implements TeamRemote {
  FakeTeamRemote({List<TeamMember>? members, this.seatLimit = 5})
      : members = [
          ...(members ?? const [TeamMember(id: 'u1', fullName: 'Erika', role: Roles.owner, active: true)]),
        ]; // a growable copy: tests pass const lists

  final List<TeamMember> members;
  final List<TeamInvite> invites = [];
  final Map<String, Set<String>> assignees = {};

  /// The hourly rates set for people (cents).
  final Map<String, int> rates = {};
  int seatLimit;
  int _next = 0;

  /// Thrown by every call while non-null.
  TeamException? error;

  final List<String> log = [];

  int get _seats => members.where((m) => m.active).length + invites.length;

  @override
  Future<TeamOverview> fetchOverview() async {
    if (error != null) throw error!;
    return TeamOverview(members: List.of(members), invites: List.of(invites), seatLimit: seatLimit);
  }

  @override
  Future<TeamInvite> createInvite(String role) async {
    if (error != null) throw error!;
    if (_seats >= seatLimit) {
      throw const TeamException(
          'Alle Plätze deines Pakets sind belegt. Für mehr Personen wird ein größeres Paket gebraucht.');
    }
    final i = TeamInvite(
        id: 'inv${++_next}', code: 'ABCD234$_next', role: role, expiresAt: DateTime.now().add(const Duration(days: 7)));
    invites.add(i);
    log.add('invite:$role');
    return i;
  }

  @override
  Future<void> revokeInvite(String id) async {
    if (error != null) throw error!;
    invites.removeWhere((i) => i.id == id);
    log.add('revoke:$id');
  }

  @override
  Future<void> setMemberActive(String userId, bool active) async {
    if (error != null) throw error!;
    final idx = members.indexWhere((m) => m.id == userId);
    if (active && !members[idx].active && _seats >= seatLimit) {
      throw const TeamException(
          'Alle Plätze deines Pakets sind belegt. Für mehr Personen wird ein größeres Paket gebraucht.');
    }
    final m = members[idx];
    members[idx] = TeamMember(id: m.id, fullName: m.fullName, role: m.role, active: active);
    log.add('active:$userId:$active');
  }

  @override
  Future<void> removeMember(String userId) async {
    if (error != null) throw error!;
    members.removeWhere((m) => m.id == userId);
    for (final set in assignees.values) {
      set.remove(userId);
    }
    log.add('remove:$userId');
  }

  @override
  @override
  Future<Map<String, int>> fetchRates() async {
    if (error != null) throw error!;
    return Map.of(rates);
  }

  @override
  Future<void> setRate(String userId, int? cents) async {
    if (error != null) throw error!;
    log.add('rate:$userId:$cents');
    if (cents == null) {
      rates.remove(userId);
    } else {
      rates[userId] = cents;
    }
  }

  @override
  Future<Set<String>> fetchAssignees(String jobId) async {
    if (error != null) throw error!;
    return {...?assignees[jobId]};
  }

  @override
  Future<void> setAssignees(String jobId, Set<String> userIds) async {
    if (error != null) throw error!;
    assignees[jobId] = {...userIds};
    log.add('assign:$jobId:${(userIds.toList()..sort()).join(',')}');
  }
}

/// Erika (owner, the signed-in user) plus a colleague each for office, Geselle and a switched-off person.
List<TeamMember> sampleTeam() => const [
      TeamMember(id: 'u1', fullName: 'Erika', role: Roles.owner, active: true),
      TeamMember(id: 'u2', fullName: 'Gesa Geselle', role: Roles.geselle, active: true),
      TeamMember(id: 'u3', fullName: 'Bernd Büro', role: Roles.buero, active: true),
      TeamMember(id: 'u4', fullName: 'Max Ausgeschieden', role: Roles.geselle, active: false),
    ];
