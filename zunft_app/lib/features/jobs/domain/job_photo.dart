/// A photo on a job: the state of the work before, after, or another picture (proof for disputes).
class JobPhoto {
  const JobPhoto({
    required this.id,
    required this.jobId,
    required this.kind,
    required this.path,
    required this.createdAt,
    this.authorId,
    this.authorName,
  });

  final String id;
  final String jobId;

  /// before | after | other
  final String kind;

  /// Where the file is stored in the private "captures" bucket.
  final String path;
  final DateTime createdAt;
  final String? authorId;
  final String? authorName;

  static const kinds = ['before', 'after', 'other'];

  factory JobPhoto.fromRow(Map<String, dynamic> r) => JobPhoto(
        id: r['id'] as String,
        jobId: r['job_id'] as String,
        kind: (r['kind'] as String?) ?? 'other',
        path: r['storage_path'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        authorId: r['created_by'] as String?,
        authorName: r['created_by_name'] as String?,
      );
}

/// The German word for a kind (used in lists and in the export).
String photoKindLabelDe(String kind) => switch (kind) {
      'before' => 'Vorher',
      'after' => 'Nachher',
      _ => 'Weitere',
    };
