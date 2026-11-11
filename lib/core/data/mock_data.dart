import 'package:flutter/material.dart';

/// Sample domain model for the UI. Every value below is synthetic.

enum ModelFamily { gemini, claude, openai }

extension ModelFamilyLabel on ModelFamily {
  String get label => switch (this) {
    ModelFamily.gemini => 'Google Gemini',
    ModelFamily.claude => 'Anthropic Claude',
    ModelFamily.openai => 'OpenAI',
  };

  String get shortLabel => switch (this) {
    ModelFamily.gemini => 'Gemini',
    ModelFamily.claude => 'Claude',
    ModelFamily.openai => 'OpenAI',
  };

  IconData get icon => switch (this) {
    ModelFamily.gemini => Icons.auto_awesome_rounded,
    ModelFamily.claude => Icons.brightness_7_rounded,
    ModelFamily.openai => Icons.blur_on_rounded,
  };
}

enum AccountStatus { active, idle, rateLimited, error }

extension AccountStatusLabel on AccountStatus {
  String get label => switch (this) {
    AccountStatus.active => 'Active',
    AccountStatus.idle => 'Idle',
    AccountStatus.rateLimited => 'Rate limited',
    AccountStatus.error => 'Error',
  };
}

class ModelQuota {
  const ModelQuota({
    required this.name,
    required this.family,
    required this.remaining,
    required this.resetLabel,
    this.hidden = false,
  });

  final String name;
  final ModelFamily family;
  final double remaining;
  final String resetLabel;
  final bool hidden;
}

/// A model the local gateway can serve.
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.label,
    required this.family,
  });

  /// The identifier a client sends inside the request body.
  final String id;

  /// The human readable name shown in the interface.
  final String label;

  final ModelFamily family;
}

/// A group of models that share one weekly allowance.
class ModelGroup {
  const ModelGroup({required this.id, required this.families});

  final String id;
  final List<ModelFamily> families;
}

/// The weekly allowance of one model group.
class WeeklyQuota {
  const WeeklyQuota({
    required this.groupId,
    required this.remaining,
    required this.resetLabel,
  });

  /// The id of the [ModelGroup] this allowance belongs to.
  final String groupId;

  /// Remaining share of the weekly allowance, 0.0 – 1.0.
  final double remaining;

  /// When the weekly window resets.
  final String resetLabel;
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.handle,
    required this.provider,
    required this.plan,
    required this.status,
    required this.credits,
    required this.inUse,
    required this.quotas,
    this.weeklyQuotas = const [],
    this.recommended = false,
    this.unbound = false,
    this.demo = false,
    this.quotaFetchedAt,
    this.quotaError,
  });

  final String id;
  final String name;
  final String handle;
  final String provider;
  final String plan;
  final AccountStatus status;
  final int credits;
  final bool inUse;
  final List<ModelQuota> quotas;

  /// The weekly allowance per model group.
  final List<WeeklyQuota> weeklyQuotas;

  final bool recommended;
  final bool unbound;

  /// Whether the account belongs to the synthetic dataset.
  ///
  /// The interface marks those accounts, so a real account is never confused
  /// with the sample data of a fresh profile.
  final bool demo;
  final int? quotaFetchedAt;
  final String? quotaError;

  List<ModelQuota> quotasOf(ModelFamily family) =>
      quotas.where((q) => q.family == family).toList();

  WeeklyQuota? weeklyOf(String groupId) {
    for (final quota in weeklyQuotas) {
      if (quota.groupId == groupId) return quota;
    }
    return null;
  }

  double get globalRemaining {
    if (quotas.isEmpty) return 0;
    final total = quotas.fold<double>(0, (sum, q) => sum + q.remaining);
    return total / quotas.length;
  }
}

enum WorkspaceState { idle, running, stopped }

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    required this.accountName,
    required this.plan,
    required this.projectFolder,
    required this.profileFolder,
    required this.lastActive,
    required this.state,
    this.unbound = false,
  });

  final String id;
  final String name;
  final String accountName;
  final String plan;
  final String projectFolder;
  final String profileFolder;
  final String lastActive;
  final WorkspaceState state;
  final bool unbound;
}

enum TrafficCategory { modelRequests, otherRequests, appActions, systemEvents }

extension TrafficCategoryLabel on TrafficCategory {
  String get label => switch (this) {
    TrafficCategory.modelRequests => 'Model requests',
    TrafficCategory.otherRequests => 'Other requests',
    TrafficCategory.appActions => 'App actions',
    TrafficCategory.systemEvents => 'System events',
  };
}

enum TrafficResult { success, appError, signInFailed, timeout }

extension TrafficResultLabel on TrafficResult {
  String get label => switch (this) {
    TrafficResult.success => 'OK',
    TrafficResult.appError => 'App error',
    TrafficResult.signInFailed => 'Sign-in failed',
    TrafficResult.timeout => 'Timed out',
  };
}

class TrafficEntry {
  const TrafficEntry({
    required this.time,
    required this.model,
    required this.family,
    required this.account,
    required this.tokensIn,
    required this.tokensOut,
    required this.output,
    required this.result,
    required this.statusCode,
    required this.durationMs,
    required this.endpoint,
  });

  final String time;
  final String model;
  final ModelFamily family;
  final String account;
  final int tokensIn;
  final int tokensOut;
  final String output;
  final TrafficResult result;
  final int statusCode;
  final int durationMs;
  final String endpoint;
}

class ModelMapping {
  const ModelMapping({
    required this.source,
    required this.target,
    this.enabled = true,
  });

  final String source;
  final String target;
  final bool enabled;
}

class ServiceEntry {
  const ServiceEntry({
    required this.name,
    required this.running,
    required this.description,
  });

  final String name;
  final bool running;
  final String description;
}

/// A ready made dataset so every screen renders with realistic content.
abstract final class MockData {
  /// Every model the gateway can route to.
  static const List<CatalogModel> modelCatalog = [
    CatalogModel(
      id: 'gemini-3.8-flash-high',
      label: 'Gemini 3.8 Flash (High)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.8-flash-medium',
      label: 'Gemini 3.8 Flash (Medium)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gpt-oss-120b-medium',
      label: 'GPT-OSS 120B (Medium)',
      family: ModelFamily.openai,
    ),
    CatalogModel(
      id: 'gemini-3.5-flash-lite',
      label: 'Gemini 3.5 Flash Lite (gemini-3.5-flash-lite)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'claude-sonnet-4-6',
      label: 'Claude Sonnet 4.6 (Thinking) (claude-sonnet-4-6)',
      family: ModelFamily.claude,
    ),
    CatalogModel(
      id: 'gemini-2.5-flash-lite',
      label: 'Gemini 3.5 Flash Lite (gemini-2.5-flash-lite)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.1-flash-image',
      label: 'Gemini 3.1 Flash Image',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'claude-opus-4-6-thinking',
      label: 'Claude Opus 4.6 (Thinking)',
      family: ModelFamily.claude,
    ),
    CatalogModel(
      id: 'gemini-3-flash',
      label: 'Gemini 3 Flash',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.1-flash-lite',
      label: 'Gemini 3.1 Flash Lite',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.8-flash-low',
      label: 'Gemini 3.8 Flash (Low)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-2.5-flash-thinking',
      label: 'Gemini 3.5 Flash Lite (gemini-2.5-flash-thinking)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.8-flash-tiered',
      label: 'gemini-3.8-flash-tiered',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-2.5-pro',
      label: 'Gemini 2.5 Pro',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-2.5-flash',
      label: 'Gemini 3.5 Flash Lite (gemini-2.5-flash)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-4-argon',
      label: 'Gemini 4 Argon',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-4-argon-high',
      label: 'Gemini 4 Argon (High)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.7-flash',
      label: 'Gemini 3.7 Flash',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.7-flash-low',
      label: 'Gemini 3.7 Flash (Low)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.7-flash-medium',
      label: 'Gemini 3.7 Flash (Medium)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.7-flash-high',
      label: 'Gemini 3.7 Flash (High)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.5-flash-low',
      label: 'Gemini 3.5 Flash (Low)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.5-flash-medium',
      label: 'Gemini 3.5 Flash (Medium)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.5-flash-high',
      label: 'Gemini 3.5 Flash (High)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.1-pro-low',
      label: 'Gemini 3.1 Pro (Low)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3.1-pro-high',
      label: 'Gemini 3.1 Pro (High)',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'gemini-3-pro-image',
      label: 'Gemini 3 Pro Image',
      family: ModelFamily.gemini,
    ),
    CatalogModel(
      id: 'claude-sonnet-4-6-thinking',
      label: 'Claude Sonnet 4.6 (Thinking) (claude-sonnet-4-6-thinking)',
      family: ModelFamily.claude,
    ),
    CatalogModel(
      id: 'gpt-5-1-codex',
      label: 'GPT 5.1 Codex',
      family: ModelFamily.openai,
    ),
    CatalogModel(id: 'gpt-5-1', label: 'GPT 5.1', family: ModelFamily.openai),
    CatalogModel(
      id: 'claude-haiku-4-5',
      label: 'Claude Haiku 4.5',
      family: ModelFamily.claude,
    ),
  ];

  /// The model groups that share one weekly allowance.
  static const List<ModelGroup> modelGroups = [
    ModelGroup(id: 'gemini', families: [ModelFamily.gemini]),
    ModelGroup(
      id: 'claudeGpt',
      families: [ModelFamily.claude, ModelFamily.openai],
    ),
  ];

  static final List<Account> accounts = [
    _buildAccount(
      id: 'acc-01',
      name: 'Northwind Studio',
      handle: 'northwind.studio@example.com',
      provider: 'Google',
      plan: 'Google AI Pro',
      status: AccountStatus.active,
      credits: 2400,
      inUse: true,
      recommended: true,
      overrides: const {
        'gemini-3.8-flash-high': (remaining: 1.0, reset: '6d 21h'),
        'gemini-3.5-flash-lite': (remaining: 0.82, reset: '4h 12m'),
        'gemini-3-flash': (remaining: 0.46, reset: '4h 12m'),
        'gemini-3.1-flash-image': (remaining: 0.64, reset: '6d 21h'),
        'claude-sonnet-4-6-thinking': (remaining: 0.71, reset: '6d 21h'),
        'claude-opus-4-6-thinking': (remaining: 0.28, reset: '2d 04h'),
      },
      weeklyOverrides: const {
        'gemini': (remaining: 0.86, reset: '6d 23h'),
        'claudeGpt': (remaining: 0.64, reset: '4d 02h'),
      },
    ),
    _buildAccount(
      id: 'acc-02',
      name: 'Atlas Labs',
      handle: 'atlas.labs@example.com',
      provider: 'Anthropic',
      plan: 'Claude Max',
      status: AccountStatus.rateLimited,
      credits: 860,
      inUse: false,
      overrides: const {
        'claude-sonnet-4-6-thinking': (remaining: 0.18, reset: '42m'),
        'claude-opus-4-6-thinking': (remaining: 0.05, reset: '42m'),
        'gemini-3.8-flash-medium': (remaining: 0.92, reset: '1d 08h'),
      },
      weeklyOverrides: const {
        'gemini': (remaining: 0.41, reset: '1d 08h'),
        'claudeGpt': (remaining: 0.12, reset: '18h 40m'),
      },
    ),
    _buildAccount(
      id: 'acc-03',
      name: 'Meridian Team',
      handle: 'meridian.team@example.com',
      provider: 'Google',
      plan: 'Google AI Ultra',
      status: AccountStatus.idle,
      credits: 1240,
      inUse: false,
      overrides: const {
        'gemini-3.8-flash-medium': (remaining: 0.55, reset: '9h 30m'),
        'gemini-3.5-flash-lite': (remaining: 0.97, reset: '9h 30m'),
        'gpt-oss-120b-medium': (remaining: 0.34, reset: '3d 11h'),
      },
      weeklyOverrides: const {
        'gemini': (remaining: 0.97, reset: '6d 23h'),
        'claudeGpt': (remaining: 0.88, reset: '5d 11h'),
      },
    ),
    _buildAccount(
      id: 'acc-04',
      name: 'Lumen Personal',
      handle: 'lumen.personal@example.com',
      provider: 'Google',
      plan: 'Google AI Pro',
      status: AccountStatus.error,
      credits: 0,
      inUse: false,
      seeded: false,
      overrides: const {
        'gemini-3.8-flash-low': (remaining: 0, reset: '—'),
        'gemini-3-flash': (remaining: 0, reset: '—'),
      },
      weeklyOverrides: const {
        'gemini': (remaining: 0, reset: '—'),
        'claudeGpt': (remaining: 0, reset: '—'),
      },
    ),
  ];

  /// Builds an account that exposes the full model catalog.
  ///
  /// [overrides] pins the quota of the models the narrative focuses on, the
  /// rest gets a deterministic value so every card lists the same models.
  static Account _buildAccount({
    required String id,
    required String name,
    required String handle,
    required String provider,
    required String plan,
    required AccountStatus status,
    required int credits,
    required bool inUse,
    Map<String, ({double remaining, String reset})> overrides = const {},
    Map<String, ({double remaining, String reset})> weeklyOverrides = const {},
    bool recommended = false,
    bool seeded = true,
  }) {
    return Account(
      id: id,
      name: name,
      handle: handle,
      provider: provider,
      plan: plan,
      status: status,
      credits: credits,
      inUse: inUse,
      recommended: recommended,
      // Every account of the synthetic dataset is a sample.
      demo: true,
      quotas: [
        for (final model in modelCatalog)
          ModelQuota(
            name: model.label,
            family: model.family,
            remaining:
                overrides[model.id]?.remaining ??
                (seeded ? _seededRemaining(id, model.id) : 0),
            resetLabel:
                overrides[model.id]?.reset ??
                (seeded ? _seededReset(id, model.id) : '—'),
          ),
      ],
      weeklyQuotas: [
        for (final group in modelGroups)
          WeeklyQuota(
            groupId: group.id,
            remaining:
                weeklyOverrides[group.id]?.remaining ??
                (seeded ? _seededWeeklyRemaining(id, group.id) : 0),
            resetLabel:
                weeklyOverrides[group.id]?.reset ??
                (seeded ? _seededWeeklyReset(id, group.id) : '—'),
          ),
      ],
    );
  }

  static double _seededWeeklyRemaining(String accountId, String groupId) {
    return 0.08 + (_seed(accountId, 'weekly|$groupId') % 1000) / 1000 * 0.9;
  }

  static String _seededWeeklyReset(String accountId, String groupId) {
    const windows = [
      '18h 40m',
      '1d 08h',
      '3d 04h',
      '4d 02h',
      '5d 11h',
      '6d 23h',
    ];
    return windows[_seed(accountId, 'weekly|$groupId') % windows.length];
  }

  static int _seed(String accountId, String modelId) {
    var hash = 17;
    for (final unit in '$accountId|$modelId'.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  static double _seededRemaining(String accountId, String modelId) {
    return 0.12 + (_seed(accountId, modelId) % 1000) / 1000 * 0.83;
  }

  static String _seededReset(String accountId, String modelId) {
    const windows = [
      '42m',
      '4h 12m',
      '9h 30m',
      '1d 08h',
      '2d 04h',
      '3d 11h',
      '6d 21h',
    ];
    return windows[_seed(accountId, modelId) % windows.length];
  }

  static const List<Workspace> workspaces = [
    Workspace(
      id: 'ws-01',
      name: 'checkout-web',
      accountName: 'Northwind Studio',
      plan: 'Google AI Pro',
      projectFolder: 'projects / checkout-web',
      profileFolder: 'profiles / checkout-web',
      lastActive: 'Nov 7, 03:41',
      state: WorkspaceState.idle,
    ),
    Workspace(
      id: 'ws-02',
      name: 'ledger-service',
      accountName: 'Meridian Team',
      plan: 'Google AI Ultra',
      projectFolder: 'projects / ledger-service',
      profileFolder: 'profiles / ledger-service',
      lastActive: 'Nov 6, 11:42',
      state: WorkspaceState.running,
    ),
    Workspace(
      id: 'ws-03',
      name: 'design-explorer',
      accountName: 'Unbound',
      plan: '—',
      projectFolder: 'projects / design-explorer',
      profileFolder: 'profiles / design-explorer',
      lastActive: 'Nov 4, 19:07',
      state: WorkspaceState.stopped,
      unbound: true,
    ),
  ];

  static const List<TrafficEntry> traffic = [
    TrafficEntry(
      time: 'Nov 7, 06:41:38',
      model: 'gemini-3-flash-lite',
      family: ModelFamily.gemini,
      account: '7ce29ec0-10ba-45eb-89b8',
      tokensIn: 0,
      tokensOut: 0,
      output: 'Unknown',
      result: TrafficResult.signInFailed,
      statusCode: 40,
      durationMs: 6260,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 06:18:37',
      model: 'claude-opus-4-6-thinking',
      family: ModelFamily.claude,
      account: '7ce29ec0-10ba-45eb-89b8',
      tokensIn: 1840,
      tokensOut: 612,
      output: 'Text',
      result: TrafficResult.success,
      statusCode: 200,
      durationMs: 7472,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 06:01:14',
      model: 'gemini-3-8-flash-tiered',
      family: ModelFamily.gemini,
      account: '1cb6ba50-21ca-4065-a31d',
      tokensIn: 960,
      tokensOut: 288,
      output: 'Text',
      result: TrafficResult.signInFailed,
      statusCode: 40,
      durationMs: 51291,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 05:59:54',
      model: 'gemini-3-flash',
      family: ModelFamily.gemini,
      account: 'Unbound',
      tokensIn: 0,
      tokensOut: 0,
      output: 'Unknown',
      result: TrafficResult.appError,
      statusCode: 503,
      durationMs: 5,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 05:59:38',
      model: 'gemini-3-flash',
      family: ModelFamily.gemini,
      account: 'Unbound',
      tokensIn: 0,
      tokensOut: 0,
      output: 'Unknown',
      result: TrafficResult.appError,
      statusCode: 503,
      durationMs: 3,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 04:01:12',
      model: 'gemini-3-8-flash-high',
      family: ModelFamily.gemini,
      account: '1cb6ba50-21ca-4065-a31d',
      tokensIn: 2210,
      tokensOut: 740,
      output: 'Text',
      result: TrafficResult.success,
      statusCode: 200,
      durationMs: 2517,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 03:46:24',
      model: 'claude-sonnet-4-6',
      family: ModelFamily.claude,
      account: '1cb6ba50-21ca-4065-a31d',
      tokensIn: 1320,
      tokensOut: 455,
      output: 'Text',
      result: TrafficResult.success,
      statusCode: 200,
      durationMs: 3420,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 03:28:41',
      model: 'gemini-3-8-flash-tiered',
      family: ModelFamily.gemini,
      account: '1cb6ba50-21ca-4065-a31d',
      tokensIn: 880,
      tokensOut: 302,
      output: 'Text',
      result: TrafficResult.timeout,
      statusCode: 40,
      durationMs: 43839,
      endpoint: '/v1/chat/completions',
    ),
    TrafficEntry(
      time: 'Nov 7, 00:44:29',
      model: 'gemini-3-8-flash-tiered',
      family: ModelFamily.gemini,
      account: 'c4b11381-51e1-4ba8-a640',
      tokensIn: 640,
      tokensOut: 190,
      output: 'Text',
      result: TrafficResult.appError,
      statusCode: 500,
      durationMs: 12370,
      endpoint: '/v1/chat/completions',
    ),
  ];

  static const List<ModelMapping> modelMappings = [
    ModelMapping(
      source: 'Claude Sonnet 4.6 (Thinking)',
      target: 'claude-sonnet-4-6-thinking',
    ),
    ModelMapping(
      source: 'Claude Opus 4.6 (Thinking)',
      target: 'claude-opus-4-6-thinking',
    ),
    ModelMapping(source: 'Claude Haiku 4.5', target: 'claude-haiku-4-5'),
    ModelMapping(source: 'GPT 5.1', target: 'gpt-5-1'),
  ];

  static const List<String> availableModels = [
    'gemini-3-8-flash',
    'gemini-3-8-flash-tiered',
    'gemini-3-5-flash-lite',
    'gemini-3-flash',
    'gemini-3-1-flash-image',
    'claude-sonnet-4-6',
    'claude-sonnet-4-6-thinking',
    'claude-opus-4-6-thinking',
    'claude-haiku-4-5',
    'gpt-5-1',
    'gpt-5-1-codex',
  ];

  /// Every model id the gateway accepts, taken from the catalog.
  static List<String> get catalogModelIds => [
    for (final model in modelCatalog) model.id,
  ];

  static const List<ServiceEntry> services = [
    ServiceEntry(
      name: 'Antigravity Manager',
      running: true,
      description: 'Desktop shell and account pool',
    ),
    ServiceEntry(
      name: 'Local API Proxy',
      running: false,
      description: 'OpenAI compatible gateway',
    ),
  ];
}
