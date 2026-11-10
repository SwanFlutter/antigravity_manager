/// The models the cloud side of the contract exchanges with the UI.
library;

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
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
