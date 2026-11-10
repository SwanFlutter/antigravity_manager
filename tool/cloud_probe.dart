// ignore_for_file: avoid_print

// A diagnostic that walks the whole cloud flow of the running host over the
// private named pipe.
//
// Run it with:
//   dart run tool/cloud_probe.dart
//
// It reads the state of the local proxy, starts it, rotates the key, reads
// the traffic log and asks the host to begin a Google connection. It never
// prints a secret: the key is only shown in its masked form.
import 'dart:convert';

import 'package:antigravity_manager/data/host/host_client.dart';
import 'package:antigravity_manager/data/host/pipe_transport.dart';

/// Shows a key without its middle.
String mask(String key) {
  if (key.length <= 8) return '••••';
  return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
}

Future<void> main(List<String> arguments) async {
  var rotate = false;
  var port = 8045;
  String? pipeName;

  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--rotate') {
      rotate = true;
    } else if (argument == '--port' && index + 1 < arguments.length) {
      port = int.tryParse(arguments[index + 1]) ?? port;
      index++;
    } else if (!argument.startsWith('--')) {
      pipeName = argument;
    }
  }

  final client = HostClient(
    transport: PipeTransport(pipeName: pipeName ?? PipeTransport.defaultPipeName),
  );

  try {
    final info = await client.hostInfo();
    print('contract version : ${info.contractVersion}');
    print('profile path     : ${info.profilePath}');

    final connected = await client.connectedAccounts();
    print('connected        : ${connected.length}');
    for (final account in connected) {
      print('  - ${account['email']} (${account['plan'] ?? 'no plan'})');
    }

    final status = await client.proxyStatus();
    print('proxy running    : ${status['running']}');
    print('proxy port       : ${status['port']}');
    print('proxy base url   : ${status['baseUrl']}');
    print('proxy models     : ${status['models']}');
    final key = status['apiKey'] as String?;
    print('proxy key        : ${key == null ? 'none (open mode)' : mask(key)}');

    if (status['running'] != true) {
      print('starting the proxy ...');
      final started = await client.startProxy(port: port);
      print('proxy running    : ${started['running']}');
      print('proxy port       : ${started['port']}');
    }

    if (rotate) {
      final rotated = await client.rotateProxyKey();
      final newKey = rotated['apiKey'] as String?;
      print('rotated key      : ${newKey == null ? 'none' : mask(newKey)}');
      print('key length       : ${newKey?.length ?? 0}');
    }

    final traffic = await client.traffic();
    print('traffic entries  : ${traffic.length}');
    for (final entry in traffic.take(5)) {
      print(
        '  - ${entry['protocol']} ${entry['model']} '
        '${entry['status']} ${entry['durationMs']}ms',
      );
    }

    print('starting a Google connection ...');
    final session = await client.startConnect();
    print('session id       : ${session['sessionId']}');
    print('redirect uri     : ${session['redirectUri']}');
    final url = session['authorizationUrl'] as String? ?? '';
    print('authorization    : ${url.replaceAll(RegExp(r'client_id=[^&]+'), 'client_id=***')}');

    final state = await client.connectStatus(session['sessionId'] as String);
    print('session state    : ${jsonEncode(state)}');
  } on HostError catch (error) {
    print('the host reported an error: $error');
  } on HostUnavailable catch (error) {
    print('the host is not reachable: $error');
  }
}
