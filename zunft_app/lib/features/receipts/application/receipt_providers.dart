import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/receipts_remote.dart';
import '../domain/receipt_entry.dart';

final receiptsRemoteProvider = Provider<ReceiptsRemote>((ref) => SupabaseReceiptsRemote(Supabase.instance.client));

final fileSharerProvider = Provider<FileSharer>((ref) => SharePlusFileSharer());

/// All receipts of the business, read from the server.
final receiptArchiveProvider = FutureProvider.autoDispose<List<ReceiptEntry>>(
  (ref) => ref.watch(receiptsRemoteProvider).fetchAll(),
);
