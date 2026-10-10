import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Things an appointment hands over to other apps: the phone dialer, the maps app, the share
/// sheet (WhatsApp, SMS, e-mail, calendar). Behind an interface so tests need no phone.
abstract class ExternalActions {
  /// Opens [uri] in another app (tel:, https maps link). false if nothing could open it.
  Future<bool> openUrl(Uri uri);

  /// The share sheet with a text (for example the confirmation to a customer).
  Future<void> shareText(String text, {String? subject});

  /// The share sheet with a calendar file: the calendar app can import it.
  Future<void> shareCalendarFile(Uint8List bytes, String fileName);
}

class PlatformExternalActions implements ExternalActions {
  @override
  Future<bool> openUrl(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> shareText(String text, {String? subject}) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  Future<void> shareCalendarFile(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/calendar')], subject: fileName));
  }
}

/// A Google-Maps link that every phone opens (in the maps app if installed, else the browser).
Uri mapsUri(String address) =>
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address});

/// A phone link; spaces and slashes in the number are removed so the dialer accepts it.
Uri telUri(String phone) => Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
