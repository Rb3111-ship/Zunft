import 'dart:typed_data';

import 'package:zunft_app/features/jobs/data/job_photos_remote.dart';
import 'package:zunft_app/features/jobs/domain/job_photo.dart';

import 'fake_logo.dart' show onePixelPng;

/// The server's job photos for the tests.
class FakeJobPhotosRemote implements JobPhotosRemote {
  final List<JobPhoto> photos = [];

  /// Thrown by every call while non-null.
  Exception? error;

  /// Paths whose picture cannot be downloaded.
  final Set<String> brokenFiles = {};
  final List<String> deleted = [];

  /// Every path that was downloaded, in order.
  final List<String> downloads = [];

  /// Photos without a small picture (taken before thumbnails existed): their "_t.jpg" does not exist.
  bool noThumbs = false;

  static JobPhoto photo(String id, {String jobId = 'j1', String kind = 'before', String? author = 'Thorsten', String? authorId = 'u9', DateTime? at}) =>
      JobPhoto(
        id: id,
        jobId: jobId,
        kind: kind,
        path: 'b1/u9/photos/$id.jpg',
        createdAt: at ?? DateTime(2026, 10, 12, 9, 15),
        authorId: authorId,
        authorName: author,
      );

  @override
  Future<List<JobPhoto>> fetchForJob(String jobId) async {
    if (error != null) throw error!;
    return photos.where((p) => p.jobId == jobId).toList();
  }

  @override
  Future<List<JobPhoto>> fetchAll() async {
    if (error != null) throw error!;
    return List.of(photos);
  }

  @override
  Future<Uint8List> download(String path) async {
    if (error != null) throw error!;
    downloads.add(path);
    if (brokenFiles.contains(path)) throw Exception('gone');
    if (noThumbs && path.endsWith('_t.jpg')) throw Exception('no thumbnail');
    return onePixelPng;
  }

  @override
  Future<void> delete(String id) async {
    if (error != null) throw error!;
    deleted.add(id);
    photos.removeWhere((p) => p.id == id);
  }
}
