import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../app/controller/app_controller.dart';
import '../../core/data/mock_data.dart';
import '../../data/accounts_repository.dart';
import '../../data/cloud_models.dart';

/// State of the traffic request log screen.
///
/// The log itself is a flat list of [TrafficEntry] records. Every filter
/// narrows that list down, the remaining records are then paginated in pages
/// of [pageSize] rows.
class TrafficController extends GetXController {
  TrafficController({AccountsRepository? repository})
      : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;

  /// Number of rows shown on a single page of the log.
  static const int pageSize = 8;

  /// Account name used by the records that never reached a bound account.
  static const String unboundAccount = 'Unbound';

  /// The recorded requests.
  final RxList<TrafficEntry> entries = <TrafficEntry>[...MockData.traffic].obs;

  /// Search input of the filter panel.
  final TextEditingController searchController = TextEditingController();

  /// Free text search over model, account, endpoint and time.
  final RxString query = ''.obs;

  /// The category tab that is currently open.
  final Rx<TrafficCategory> category = TrafficCategory.modelRequests.obs;

  /// Account id filter, `all` keeps every account.
  final RxString accountFilter = 'all'.obs;

  /// Model family filter, `null` keeps every family.
  final Rx<ModelFamily?> familyFilter = Rx<ModelFamily?>(null);

  /// Output kind filter, `all` keeps every output.
  final RxString outputFilter = 'all'.obs;

  /// Result filter, `all` keeps every result.
  final RxString statusFilter = 'all'.obs;

  /// Whether the copied cURL carries the current proxy key.
  final RxBool includeKeyInCurl = false.obs;

  /// One based index of the visible page.
  final RxInt page = 1.obs;

  /// Every account id that appears in the log.
  List<String> get availableAccounts {
    final ids = entries.map((entry) => entry.account).toSet().toList()..sort();
    return ids;
  }

  /// Every output kind that appears in the log.
  List<String> get availableOutputs {
    final outputs = entries.map((entry) => entry.output).toSet().toList()..sort();
    return outputs;
  }

  /// Groups a record into one of the log categories.
  ///
  /// The records themselves do not carry a category, so it is derived from the
  /// shape of the request: work that never left the app is an app action, a
  /// settled model call is a model request, a failed sign in is a system
  /// event and everything else is an ordinary request.
  TrafficCategory categoryOf(TrafficEntry entry) {
    if (entry.account == unboundAccount) return TrafficCategory.appActions;
    return switch (entry.result) {
      TrafficResult.success => TrafficCategory.modelRequests,
      TrafficResult.timeout => TrafficCategory.otherRequests,
      TrafficResult.signInFailed => TrafficCategory.systemEvents,
      TrafficResult.appError => TrafficCategory.otherRequests,
    };
  }

  /// Records that pass every active filter.
  List<TrafficEntry> get filteredEntries {
    final needle = query.value.trim().toLowerCase();

    return entries.where((entry) {
      if (categoryOf(entry) != category.value) return false;
      if (accountFilter.value != 'all' &&
          entry.account != accountFilter.value) {
        return false;
      }
      if (familyFilter.value != null && entry.family != familyFilter.value) {
        return false;
      }
      if (outputFilter.value != 'all' && entry.output != outputFilter.value) {
        return false;
      }
      if (statusFilter.value != 'all' &&
          entry.result.name != statusFilter.value) {
        return false;
      }
      if (needle.isEmpty) return true;

      return entry.model.toLowerCase().contains(needle) ||
          entry.account.toLowerCase().contains(needle) ||
          entry.endpoint.toLowerCase().contains(needle) ||
          entry.output.toLowerCase().contains(needle) ||
          entry.time.toLowerCase().contains(needle) ||
          entry.result.label.toLowerCase().contains(needle);
    }).toList();
  }

  /// Number of records that pass every active filter.
  int get totalCount => filteredEntries.length;

  /// Number of records kept in the log, filters ignored.
  int get storedCount => entries.length;

  /// Approximate size of the log on disk.
  String get storedSizeLabel {
    var bytes = 0;
    for (final entry in entries) {
      bytes += entry.time.length +
          entry.model.length +
          entry.account.length +
          entry.output.length +
          entry.endpoint.length +
          entry.statusCode.toString().length +
          entry.durationMs.toString().length +
          48;
    }
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Number of pages the filtered records span.
  int get pageCount {
    final pages = (totalCount / pageSize).ceil();
    return pages < 1 ? 1 : pages;
  }

  /// The records of the visible page.
  List<TrafficEntry> get pagedEntries {
    final items = filteredEntries;
    if (items.isEmpty) return const [];

    final start = ((page.value - 1) * pageSize).clamp(0, items.length).toInt();
    final end = (start + pageSize).clamp(0, items.length).toInt();
    return items.sublist(start, end);
  }

  void setQuery(String value) {
    query.value = value;
    page.value = 1;
  }

  void clearQuery() {
    searchController.clear();
    query.value = '';
    page.value = 1;
  }

  void setCategory(TrafficCategory value) {
    category.value = value;
    page.value = 1;
  }

  void setAccountFilter(String value) {
    accountFilter.value = value;
    page.value = 1;
  }

  void setFamilyFilter(ModelFamily? value) {
    familyFilter.value = value;
    page.value = 1;
  }

  void setOutputFilter(String value) {
    outputFilter.value = value;
    page.value = 1;
  }

  void setStatusFilter(String value) {
    statusFilter.value = value;
    page.value = 1;
  }

  void previousPage() {
    if (page.value > 1) page.value -= 1;
  }

  void nextPage() {
    if (page.value < pageCount) page.value += 1;
  }

  bool get canGoBack => page.value > 1;

  bool get canGoForward => page.value < pageCount;

  /// Puts every filter back to its default.
  void resetFilters() {
    accountFilter.value = 'all';
    familyFilter.value = null;
    outputFilter.value = 'all';
    statusFilter.value = 'all';
    clearQuery();
  }

  /// Drops every record of the open category from the log.
  void clearCategory() {
    final open = category.value;
    entries.removeWhere((entry) => categoryOf(entry) == open);
    page.value = 1;
  }

  /// Drops a single record from the log.
  void clearEntry(TrafficEntry entry) {
    entries.remove(entry);
    page.value = 1;
  }

  @override
  void onInit() {
    super.onInit();
    reload();
    // The host may still be starting; reload once it answers.
    ever(Get.find<AppController>().hostReady, (_) => reload());
  }

  /// Reloads the log from its source.
  Future<void> reload() async {
    try {
      final records = await repository.traffic();
      if (repository.isLive) {
        entries.assignAll(records.map(_mapRecord).toList());
      } else {
        entries.assignAll(MockData.traffic);
      }
    } catch (_) {
      entries.assignAll(MockData.traffic);
    }
    page.value = 1;
  }

  /// Converts one host record into the shape the log renders.
  static TrafficEntry _mapRecord(TrafficRecord record) {
    final status = record.status;
    final result = switch (status) {
      >= 200 && < 300 => TrafficResult.success,
      401 || 403 => TrafficResult.signInFailed,
      408 || 504 => TrafficResult.timeout,
      _ => TrafficResult.appError,
    };
    final model = record.model;
    final family = model.startsWith('claude')
        ? ModelFamily.claude
        : model.startsWith('gpt')
            ? ModelFamily.openai
            : ModelFamily.gemini;
    return TrafficEntry(
      time: formatEpochMillis(record.at, withSeconds: true),
      model: model,
      family: family,
      account: record.accountId ?? unboundAccount,
      tokensIn: 0,
      tokensOut: 0,
      output: record.error == null ? 'Text' : 'Error',
      result: result,
      statusCode: status,
      durationMs: record.durationMs,
      endpoint: record.protocol == 'anthropic'
          ? '/v1/messages'
          : '/v1/chat/completions',
    );
  }

  /// Copies the request as a cURL command.
  Future<void> copyCurl(TrafficEntry entry) async {
    final key = includeKeyInCurl.value ? await _currentKey() : 'YOUR_PROXY_KEY';
    final command = 'curl -X POST http://127.0.0.1:8045${entry.endpoint} '
        '-H "Content-Type: application/json" '
        '-H "Authorization: Bearer $key" '
        '-d \'{"model":"${entry.model}"}\'';

    Clipboard.setData(ClipboardData(text: command));
  }

  /// The key of the running proxy, or the placeholder when it is not live.
  Future<String> _currentKey() async {
    try {
      final status = await repository.proxyStatus();
      if (status.apiKey != null) return status.apiKey!;
    } catch (_) {
      // The host is not running.
    }
    return 'sk-ant-local-9f4c21ab7de30568';
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }
}
