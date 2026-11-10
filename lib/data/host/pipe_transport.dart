import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Raised when the Rust host cannot be reached or answers something the
/// contract does not allow.
class HostUnavailable implements Exception {
  HostUnavailable(this.message);

  final String message;

  @override
  String toString() => 'HostUnavailable: $message';
}

/// The channel the contract travels over.
///
/// The interface keeps the client testable: the tests answer with canned
/// payloads instead of opening a pipe.
abstract class HostTransport {
  /// Sends one request and returns the decoded response.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]);
}

/// The Windows named pipe transport of the application contract.
///
/// The pipe lives on the machine only: it is never exposed to the network and
/// it is the single channel between the Flutter UI and the Rust core.
///
/// Every frame is a four byte little endian length followed by the UTF-8
/// JSON payload. Byte mode is used on the pipe, so the framing does not depend
/// on the message mode of the pipe.
class PipeTransport implements HostTransport {
  PipeTransport({this.pipeName = defaultPipeName});

  /// The name of the pipe the desktop host listens on.
  static const String defaultPipeName = 'antigravity-manager-host';

  /// The maximum size of a single frame, 8 MiB.
  static const int maxFrameBytes = 8 * 1024 * 1024;

  /// How often the client tries to open the pipe before it gives up.
  static const int openAttempts = 20;

  /// The pause between two attempts to open the pipe.
  static const Duration openRetryDelay = Duration(milliseconds: 50);

  /// The Windows error code of the last failed call.
  static const int errorFileNotFound = 2;

  /// Every pipe instance is connected.
  static const int errorPipeBusy = 231;

  final String pipeName;

  int _lastError = 0;
  String _lastErrorMessage = 'the host is not reachable';

  /// The Windows error code of the last failed call.
  int get lastErrorCode => _lastError;

  /// Whether the transport can run on this platform.
  bool get isSupported => Platform.isWindows;

  /// Sends one request and returns the decoded response.
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (!isSupported) {
      throw HostUnavailable('the named pipe is only available on Windows');
    }

    final request = jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': DateTime.now().microsecondsSinceEpoch,
      'method': method,
      'params': params,
    });

    final response = await _exchange(utf8.encode(request));

    final decoded = jsonDecode(utf8.decode(response));
    if (decoded is! Map<String, dynamic>) {
      throw HostUnavailable('the host answered with an unexpected payload');
    }
    return decoded;
  }

  /// Opens the pipe, writes one frame and reads the answer.
  Future<Uint8List> _exchange(Uint8List payload) async {
    final handle = await _openWithRetry();
    try {
      _writeAll(handle, _frame(payload));
      return _readFrame(handle);
    } finally {
      _closeHandle(handle);
    }
  }

  /// Opens the pipe, retrying while the host is busy.
  ///
  /// A pipe that does not exist at all means the host is not running: waiting
  /// for it here would only delay the answer. The launcher waits for the host
  /// to come up, this transport only waits for a busy instance.
  Future<Pointer<Void>> _openWithRetry() async {
    for (var attempt = 0; attempt < openAttempts; attempt++) {
      try {
        return _open();
      } on HostUnavailable catch (error) {
        final code = _lastError;
        final retryable = code == errorPipeBusy;
        if (!retryable || attempt + 1 == openAttempts) {
          _lastErrorMessage = error.message;
          rethrow;
        }
        await Future<void>.delayed(openRetryDelay);
      }
    }
    throw HostUnavailable(_lastErrorMessage);
  }

  /// Prefixes the payload with its length in little endian order.
  static Uint8List _frame(Uint8List payload) {
    final frame = Uint8List(payload.length + 4);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  // ---------------------------------------------------------------------
  // Windows API
  // ---------------------------------------------------------------------

  static const int _genericRead = 0x80000000;
  static const int _genericWrite = 0x40000000;
  static const int _shareRead = 0x00000001;
  static const int _shareWrite = 0x00000002;
  static const int _openExisting = 3;
  static const int _fileAttributeNormal = 0x00000080;

  /// The value `CreateFileW` returns when it fails.
  static const int _invalidHandleValue = -1;

  late final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  late final _CreateFileW _createFile = _kernel32.lookupFunction<
      _CreateFileWNative,
      _CreateFileW>(
    'CreateFileW',
  );

  late final _ReadFile _readFile = _kernel32.lookupFunction<
      _ReadFileNative,
      _ReadFile>(
    'ReadFile',
  );

  late final _WriteFile _writeFile = _kernel32.lookupFunction<
      _WriteFileNative,
      _WriteFile>(
    'WriteFile',
  );

  late final _CloseHandle _close = _kernel32.lookupFunction<
      _CloseHandleNative,
      _CloseHandle>(
    'CloseHandle',
  );

  late final _GetLastError _getLastError = _kernel32.lookupFunction<
      _GetLastErrorNative,
      _GetLastError>(
    'GetLastError',
  );

  /// Opens the pipe for reading and writing.
  Pointer<Void> _open() {
    final path = '\\\\.\\pipe\\$pipeName';
    final units = path.codeUnits;
    final buffer = calloc<Uint16>(units.length + 1);
    try {
      for (var index = 0; index < units.length; index++) {
        buffer[index] = units[index];
      }
      buffer[units.length] = 0;

      final handle = _createFile(
        buffer,
        _genericRead | _genericWrite,
        _shareRead | _shareWrite,
        nullptr,
        _openExisting,
        _fileAttributeNormal,
        nullptr,
      );

      if (handle.address == _invalidHandleValue || handle.address == 0) {
        _lastError = _getLastError();
        throw HostUnavailable('cannot open the pipe $path (error $_lastError)');
      }
      _lastError = 0;
      return handle;
    } finally {
      calloc.free(buffer);
    }
  }

  void _writeAll(Pointer<Void> handle, Uint8List payload) {
    final buffer = calloc<Uint8>(payload.length);
    try {
      buffer.asTypedList(payload.length).setAll(0, payload);

      var offset = 0;
      while (offset < payload.length) {
        final written = calloc<Uint32>(1);
        try {
          final chunk = payload.length - offset;
          final result = _writeFile(
            handle,
            buffer + offset,
            chunk,
            written,
            nullptr,
          );
          if (result == 0) {
            throw HostUnavailable(
              'the pipe write failed (error ${_getLastError()})',
            );
          }
          final count = written.value;
          if (count == 0) {
            throw HostUnavailable('the pipe write made no progress');
          }
          offset += count;
        } finally {
          calloc.free(written);
        }
      }
    } finally {
      calloc.free(buffer);
    }
  }

  Uint8List _readFrame(Pointer<Void> handle) {
    final header = calloc<Uint8>(4);
    try {
      _readExact(handle, header, 4);
      final length = ByteData.sublistView(header.asTypedList(4))
          .getUint32(0, Endian.little);
      if (length > maxFrameBytes) {
        throw HostUnavailable('the host sent a frame of $length bytes');
      }

      final payload = calloc<Uint8>(length == 0 ? 1 : length);
      try {
        _readExact(handle, payload, length);
        return Uint8List.fromList(
          payload.asTypedList(length).toList(growable: false),
        );
      } finally {
        calloc.free(payload);
      }
    } finally {
      calloc.free(header);
    }
  }

  void _readExact(Pointer<Void> handle, Pointer<Uint8> buffer, int length) {
    final read = calloc<Uint32>(1);
    try {
      final result = _readFile(handle, buffer, length, read, nullptr);
      if (result == 0) {
        throw HostUnavailable('the pipe read failed (error ${_getLastError()})');
      }
    } finally {
      calloc.free(read);
    }
  }

  void _closeHandle(Pointer<Void> handle) {
    _close(handle);
  }
}

typedef _CreateFileWNative = Pointer<Void> Function(
  Pointer<Uint16> lpFileName,
  Uint32 dwDesiredAccess,
  Uint32 dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  Uint32 dwCreationDisposition,
  Uint32 dwFlagsAndAttributes,
  Pointer<Void> hTemplateFile,
);

typedef _CreateFileW = Pointer<Void> Function(
  Pointer<Uint16> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  Pointer<Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  Pointer<Void> hTemplateFile,
);

typedef _ReadFileNative = Int32 Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nBytesToRead,
  Pointer<Uint32> lpBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _ReadFile = int Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  int nBytesToRead,
  Pointer<Uint32> lpBytesRead,
  Pointer<Void> lpOverlapped,
);

typedef _WriteFileNative = Int32 Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  Uint32 nBytesToWrite,
  Pointer<Uint32> lpBytesWritten,
  Pointer<Void> lpOverlapped,
);

typedef _WriteFile = int Function(
  Pointer<Void> hFile,
  Pointer<Uint8> lpBuffer,
  int nBytesToWrite,
  Pointer<Uint32> lpBytesWritten,
  Pointer<Void> lpOverlapped,
);

typedef _CloseHandleNative = Int32 Function(Pointer<Void> hObject);

typedef _CloseHandle = int Function(Pointer<Void> hObject);

typedef _GetLastErrorNative = Uint32 Function();

typedef _GetLastError = int Function();
