import 'package:url_launcher/url_launcher.dart';

const consoleUrl = 'https://platform.claude.com/';

Future<bool> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
