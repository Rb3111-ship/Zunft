/// Roles, as stored in `profiles.role`.
///
/// owner + buero ("managers") see everything, assign jobs and issue documents; only the owner
/// manages the team. meister + geselle ("employees") see only the jobs assigned to them.
class Roles {
  static const owner = 'owner';
  static const buero = 'buero';
  static const meister = 'meister';
  static const geselle = 'geselle';

  /// Roles the owner can invite people into.
  static const invitable = [geselle, meister, buero];

  static const labels = {
    owner: 'Inhaber',
    buero: 'Büro',
    meister: 'Meister',
    geselle: 'Geselle',
  };

  static String label(String role) => labels[role] ?? role;

  static const descriptions = {
    geselle: 'Sieht nur zugewiesene Aufträge und nimmt Notizen auf.',
    meister: 'Wie Geselle: sieht nur zugewiesene Aufträge.',
    buero: 'Sieht alles, weist Aufträge zu und erstellt Rechnungen.',
  };
}

/// A person of the business (table `profiles`).
class TeamMember {
  const TeamMember({required this.id, required this.fullName, required this.role, required this.active});

  final String id;
  final String fullName;
  final String role;
  final bool active;

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String,
        active: (json['active'] as bool?) ?? true,
      );
}

/// An invitation that has been created and not yet used.
class TeamInvite {
  const TeamInvite({required this.id, required this.code, required this.role, required this.expiresAt});

  final String id;
  final String code;
  final String role;
  final DateTime expiresAt;

  factory TeamInvite.fromJson(Map<String, dynamic> json) => TeamInvite(
        id: json['id'] as String,
        code: json['code'] as String,
        role: json['role'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      );

  /// What the QR code contains. The prefix lets the scanner ignore unrelated QR codes.
  String get qrData => '$invitePrefix$code';

  static const invitePrefix = 'zunft-invite:';
}

/// Plan and seats of the business.
class TeamOverview {
  const TeamOverview({required this.members, required this.invites, required this.seatLimit});

  final List<TeamMember> members;
  final List<TeamInvite> invites;
  final int seatLimit;

  int get activeMembers => members.where((m) => m.active).length;

  /// Active people plus open invitations: what the plan counts.
  int get seatsInUse => activeMembers + invites.length;

  int get freeSeats => (seatLimit - seatsInUse).clamp(0, seatLimit);
}

/// Pulls an invitation code out of whatever was scanned or typed: the QR payload
/// ("zunft-invite:ABCD2345"), the bare code, or a code with spaces or dashes ("abcd-2345").
/// Returns null if nothing looks like a code.
String? parseInviteCode(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.toLowerCase().startsWith(TeamInvite.invitePrefix)) {
    text = text.substring(TeamInvite.invitePrefix.length);
  }
  final compact = text.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  return RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(compact) ? compact : null;
}
