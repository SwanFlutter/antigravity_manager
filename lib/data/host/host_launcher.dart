import 'dart:io';

import 'pipe_transport.dart';

/// Starts the Rust host when it is not running yet.
///
/// The host owns the profile and the local proxy. The UI only talks to it
/// over the named pipe, so the host has to run before the first request.
class HostLauncher {
  HostLauncher({this.transport});

  final PipeTransport? transport;

  /// Whether the host answers right now.
  Future<bool> isRunning() async {
    try {
      await (transport ?? PipeTransport()).call('host.info');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Starts the host when it is not running yet.
  ///
  /// Returns true when the host answers after the call.
  Future<bool> ensureRunning() async {
    if (await isRunning()) return true;

    // The tests must never start a process.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;

    for (final candidate in candidates()) {
      final file = File(candidate);
      if (!file.existsSync()) continue;

      try {
        await Process.start(
          candidate,
          <String>[],
          mode: ProcessStartMode.detached,
          workingDirectory: file.parent.path,
        );
      } catch (_) {
        continue;
      }

      // The host needs a moment to open the pipe.
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (await isRunning()) return true;
      }
    }

    return false;
  }

  /// The places the host executable can live in.
  List<String> candidates() {
    final paths = <String>[];

    final directory = File(Platform.resolvedExecutable).parent;
    paths.add('${directory.path}\\antigravity-host.exe');

    // The development build inside the workspace.
    final root = Directory.current.path;
    paths.add(
      '$root\\rust\\target\\debug\\antigravity-host.exe',
    );

    return paths;
  }
}
