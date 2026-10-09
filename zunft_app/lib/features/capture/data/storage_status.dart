/// How much of the plan's storage (recordings, receipt photos, PDFs) a business has used.
class StorageStatus {
  const StorageStatus({required this.usedBytes, required this.limitBytes});

  final int usedBytes;
  final int limitBytes;

  factory StorageStatus.fromJson(Map<String, dynamic> j) =>
      StorageStatus(usedBytes: (j['used_bytes'] as num).toInt(), limitBytes: (j['limit_bytes'] as num).toInt());

  double get fraction => limitBytes <= 0 ? 1 : (usedBytes / limitBytes).clamp(0.0, 1.0);

  /// No room for new recordings and receipts.
  bool get full => usedBytes >= limitBytes;

  /// 80 % or more: time to warn.
  bool get nearlyFull => fraction >= 0.8;

  String get label => '${formatBytes(usedBytes)} von ${formatBytes(limitBytes)} belegt';
}

/// 3236817 -> "3,1 MB" (German decimal comma).
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}
