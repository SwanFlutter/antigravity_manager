// ignore_for_file: avoid_print

// Temporary verification of the rebuilt host: the real account pool.

import 'package:antigravity_manager/data/host/host_client.dart';
import 'package:antigravity_manager/data/host/pipe_transport.dart';

Future<void> main() async {
  final client = HostClient(
    transport: PipeTransport(pipeName: PipeTransport.defaultPipeName),
  );

  final info = await client.hostInfo();
  print('host            : ${info.appVersion} contract ${info.contractVersion}');
  print('profile         : ${info.profilePath}');

  final payload = await client.accountsList();
  final list = (payload['accounts'] as List?) ?? const [];
  print('accounts        : ${list.length}');
  for (final entry in list) {
    final account = entry as Map<String, dynamic>;
    final quotas = (account['quotas'] as List?) ?? const [];
    print(
      '  - ${account['name']} | ${account['handle']} | plan=${account['plan']} '
      '| status=${account['status']} | inUse=${account['inUse']} '
      '| demo=${account['demo']}',
    );
    print(
      '      models=${quotas.length} fetchedAt=${account['quotaFetchedAt']} '
      'error=${account['quotaError']}',
    );
    for (final quota in quotas) {
      final q = quota as Map<String, dynamic>;
      print(
        '        ${q['name']} -> ${q['remaining']} (reset ${q['resetLabel']})',
      );
    }
  }

  final catalog = await client.modelsCatalog();
  print('model catalog   : ${catalog.length}');
}
