/// The models the cloud side of the contract exchanges with the UI.
library;

import 'dart:convert';

/// An OAuth session that waits for the browser to come back.
class ConnectSession {
  const ConnectSession({
    required this.sessionId,
    required this.authorizationUrl,
    required this.redirectUri,
    required this.expiresAt,
  });

  final String sessionId;

  /// The URL the browser has to open.
  final String authorizationUrl;

  /// The loopback address the browser comes back to.
  final String redirectUri;

  /// When the session expires, in milliseconds since the Unix epoch.
  final int expiresAt;
}

/// The state of an OAuth session.
class ConnectState {
  const ConnectState({required this.status, this.email, this.error});

  /// `pending`, `completed`, `failed` or `expired`.
  final String status;
  final String? email;
  final String? error;

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed' || status == 'expired';
}

/// An account that is connected with real credentials.
class ConnectedAccount {
  const ConnectedAccount({
    required this.accountId,
    required this.email,
    this.plan,
    this.projectId,
  });

  final String accountId;
  final String email;
  final String? plan;
  final String? projectId;
}

/// The state of the local API proxy.
class ProxyStatus {
  const ProxyStatus({
    required this.running,
    required this.port,
    required this.baseUrl,
    required this.models,
    this.apiKey,
    this.selectedAccountId,
  });

  const ProxyStatus.empty()
    : running = false,
      port = 8045,
      baseUrl = 'http://127.0.0.1:8045',
      models = 0,
      apiKey = null,
      selectedAccountId = null;

  final bool running;
  final int port;
  final String baseUrl;
  final String? apiKey;
  final String? selectedAccountId;

  /// How many models the gateway can route to.
  final int models;
}

/// One request that passed through the local proxy.
class TrafficRecord {
  const TrafficRecord({
    required this.id,
    required this.at,
    required this.protocol,
    required this.model,
    required this.status,
    required this.durationMs,
    required this.requestBytes,
    required this.responseBytes,
    this.accountId,
    this.error,
  });

  final int id;

  /// When the request arrived, in milliseconds since the Unix epoch.
  final int at;
  final String protocol;
  final String model;
  final String? accountId;
  final int status;
  final int durationMs;
  final int requestBytes;
  final int responseBytes;
  final String? error;

  bool get isSuccess => status >= 200 && status < 300;
}

const List<String> _kMonthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats milliseconds since the Unix epoch like `Nov 7, 03:41`.
String formatEpochMillis(int millis, {bool withSeconds = false}) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final hours = date.hour.toString().padLeft(2, '0');
  final minutes = date.minute.toString().padLeft(2, '0');
  final base = '${_kMonthLabels[date.month - 1]} ${date.day}, $hours:$minutes';
  if (!withSeconds) return base;
  return '$base:${date.second.toString().padLeft(2, '0')}';
}

/// Parsed details from an account or API error response (e.g. VALIDATION_REQUIRED, TOS_VIOLATION).
class AccountErrorDetails {
  const AccountErrorDetails({
    required this.rawError,
    this.validationUrl,
    this.appealUrl,
    this.isValidationRequired = false,
    this.isTosViolation = false,
  });

  final String rawError;
  final String? validationUrl;
  final String? appealUrl;
  final bool isValidationRequired;
  final bool isTosViolation;

  String? get primaryActionUrl => validationUrl ?? appealUrl;

  static AccountErrorDetails parse(String errorText) {
    String? valUrl;
    String? appUrl;
    bool isVal =
        errorText.contains('VALIDATION_REQUIRED') ||
        errorText.contains('Verify your account');
    bool isTos =
        errorText.contains('TOS_VIOLATION') ||
        errorText.contains('restricted this account');

    try {
      final payload = jsonDecode(errorText);
      Object? target = payload;
      if (payload is Map && payload['error'] is Map) {
        final message = (payload['error'] as Map)['message'];
        if (message is String && message.trim().startsWith('{')) {
          try {
            target = jsonDecode(message);
          } catch (_) {}
        }
      }
      if (target is Map) {
        final err = target['error'];
        final details = err is Map ? err['details'] : null;
        if (details is List) {
          for (final entry in details) {
            if (entry is Map) {
              final reason = entry['reason'];
              if (reason == 'VALIDATION_REQUIRED') isVal = true;
              if (reason == 'TOS_VIOLATION') isTos = true;
              final meta = entry['metadata'];
              if (meta is Map) {
                if (meta['validation_url'] is String) {
                  valUrl = meta['validation_url'] as String;
                }
                if (meta['appeal_url'] is String) {
                  appUrl = meta['appeal_url'] as String;
                }
                if (meta['appealUrl'] is String) {
                  appUrl = meta['appealUrl'] as String;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // Fallback regex search for URLs in raw error text
    if (valUrl == null && appUrl == null) {
      final matches = RegExp(r'https?://[^\s"}]+').allMatches(errorText);
      for (final match in matches) {
        final url = match.group(0)!;
        if (url.contains('accounts.google.com') ||
            url.contains('signin') ||
            url.contains('continue')) {
          valUrl ??= url;
        } else if (url.contains('forms.gle') || url.contains('appeal')) {
          appUrl ??= url;
        }
      }
    }

    if (isTos && appUrl == null) {
      appUrl = 'https://forms.gle/hGzM9MEUv2azZsrb9';
    }

    if (isVal && valUrl == null) {
      valUrl = 'https://accounts.google.com/v3/signin/continue';
    }

    return AccountErrorDetails(
      rawError: errorText,
      validationUrl: valUrl,
      appealUrl: appUrl,
      isValidationRequired: isVal,
      isTosViolation: isTos,
    );
  }
}
