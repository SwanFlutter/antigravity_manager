// ignore_for_file: avoid_print

import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  final ok = await launchUrl(
    Uri.parse('https://example.com/'),
    mode: LaunchMode.externalApplication,
  );
  print('launchUrl returned: $ok');
}
