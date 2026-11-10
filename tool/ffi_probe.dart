// ignore_for_file: avoid_print

// A small diagnostic that talks to the Rust host over the private named pipe.
//
// Run it with:
//   dart run tool/ffi_probe.dart
//
// It prints the contract version, the app version and the profile path of the
// running host, or the reason why the host cannot be reached.
import 'dart:convert';

import 'package:antigravity_manager/data/host/host_client.dart';
import 'package:antigravity_manager/data/host/pipe_transport.dart';

Future<void> main(List<String> arguments) async {
  final pipeName =
      arguments.isEmpty ? PipeTransport.defaultPipeName : arguments.first;

  final client = HostClient(transport: PipeTransport(pipeName: pipeName));

  try {
    final info = await client.hostInfo();
    print('contract version : ${info.contractVersion}');
    print('app version      : ${info.appVersion}');
    print('profile path     : ${info.profilePath}');

    final accounts = await client.accountsList();
    final items = accounts['accounts'];
    print('accounts         : ${items is List ? items.length : 0}');
    if (items is List) {
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final sample = item['demo'] == true ? 'sample' : 'real';
          print('  - ${item['id']} ${item['handle']} ($sample)');
        }
      }
    }

    final catalog = await client.modelsCatalog();
    print('models           : ${catalog.length}');
    print('host summary     : ${jsonEncode(accounts['summary'])}');
  } on HostError catch (error) {
    print('the host reported an error: $error');
  } on HostUnavailable catch (error) {
    print('the host is not reachable: $error');
  }
}
