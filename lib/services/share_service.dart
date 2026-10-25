import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';

/// Envoi du devis (écran E10).
class ShareService {
  /// Partage le PDF via le menu du téléphone : l'artisan choisit WhatsApp,
  /// l'e-mail ou une autre application. C'est le seul moyen fiable de joindre un fichier.
  static Future<bool> sharePdf(Uint8List bytes, String fileName, String message) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'application/pdf')],
        text: message,
        subject: fileName,
      ),
    );
    // « unavailable » = la plateforme ne sait pas dire si l'envoi a eu lieu : on le considère fait.
    return result.status != ShareResultStatus.dismissed;
  }

  /// Ouvre une conversation WhatsApp avec le client, message pré-rempli (sans pièce jointe).
  static Future<bool> openWhatsApp(String phone, String message) async {
    final number = waNumber(phone);
    if (number.length < 11) return false;
    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
