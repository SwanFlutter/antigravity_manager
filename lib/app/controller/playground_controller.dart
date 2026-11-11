import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../I18n/messages.dart';
import '../../../core/data/mock_data.dart';
import '../../../data/accounts_repository.dart';
import '../../../data/cloud_models.dart';
import 'app_controller.dart';

enum PlaygroundTab { single, compare, benchmark, dual }

/// One finished playground request.
class PlaygroundResult {
  const PlaygroundResult({
    this.text = '',
    this.error,
    this.latencyMs = 0,
    this.tokens = 0,
    this.status = 0,
  });

  final String text;
  final String? error;
  final int latencyMs;
  final int tokens;

  /// The HTTP status of the answer, 0 when the request never completed.
  final int status;

  bool get isError => error != null;
  String get displayText => error ?? text;
}

/// State of the model playground.
class PlaygroundController extends GetXController {
  PlaygroundController({AccountsRepository? repository})
    : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;

  final Rx<PlaygroundTab> tab = PlaygroundTab.single.obs;
  final RxString account = 'auto'.obs;
  final RxString model = 'gemini-3.8-flash-high'.obs;
  final RxString secondModel = 'claude-sonnet-4-6'.obs;
  final RxBool advancedOpen = false.obs;
  final RxBool running = false.obs;
  final RxDouble temperature = 0.7.obs;
  final RxDouble topP = 0.95.obs;
  final RxInt maxTokens = 2048.obs;
  final RxBool stream = true.obs;

  /// The state of the local gateway, for the header badge and the run flow.
  final Rx<ProxyStatus> gateway = const ProxyStatus.empty().obs;

  /// Why the last run failed before any account was asked, if it did.
  final Rx<String?> runError = Rx<String?>(null);

  /// The accounts the compare and benchmark tabs send the prompt to.
  final RxSet<String> compareAccounts = <String>{}.obs;

  /// The answer of the last run in the single tab.
  final Rx<PlaygroundResult?> lastResult = Rx<PlaygroundResult?>(null);

  /// The answers of the compare, benchmark and dual tabs, keyed by account
  /// id or model id.
  final RxMap<String, PlaygroundResult> results =
      <String, PlaygroundResult>{}.obs;

  final TextEditingController promptController = TextEditingController(
    text: 'Say hello, state your exact model name, and tell me a short joke.',
  );

  final List<String> presets = [
    'Say hello',
    'Reasoning',
    'Identity',
    'TypeScript',
  ];

  final RxList<Account> accounts = <Account>[].obs;

  final RxList<String> models = <String>[].obs;

  final RxList<CatalogModel> catalog = <CatalogModel>[].obs;
  final RxnString sourceError = RxnString();

  /// The human readable name of a model id.
  String modelLabel(String id) {
    for (final model in catalog) {
      if (model.id == id) return model.label;
    }
    return id;
  }

  void toggleCompareAccount(String id) {
    if (compareAccounts.contains(id)) {
      compareAccounts.remove(id);
    } else {
      compareAccounts.add(id);
    }
  }

  void selectAllCompare() =>
      compareAccounts.assignAll(accounts.map((a) => a.id));

  void clearAllCompare() => compareAccounts.clear();

  @override
  void onInit() {
    super.onInit();
    loadSources();
    // The host may still be starting; reload once it answers.
    ever(Get.find<AppController>().hostReady, (_) => loadSources());
  }

  /// Reads the account pool and the model catalog from the repository.
  Future<void> loadSources() async {
    sourceError.value = null;
    try {
      final snapshot = await repository.load();
      final firstLoad = accounts.isEmpty;
      accounts.assignAll(snapshot.accounts);
      final ids = snapshot.accounts.map((a) => a.id).toSet();
      compareAccounts.assignAll(
        firstLoad ? ids : compareAccounts.intersection(ids),
      );
      if (account.value != 'auto' && !ids.contains(account.value)) {
        account.value = 'auto';
      }
    } catch (error) {
      accounts.clear();
      compareAccounts.clear();
      sourceError.value = error.toString();
    }
    try {
      final catalog = await repository.modelCatalog();
      this.catalog.assignAll(catalog);
      models.assignAll([for (final model in catalog) model.id]);
      if (!models.contains(model.value)) {
        model.value = models.isEmpty ? '' : models.first;
      }
      if (!models.contains(secondModel.value)) {
        secondModel.value = models.isEmpty
            ? ''
            : models.length > 1
            ? models[1]
            : models.first;
      }
    } catch (error) {
      catalog.clear();
      models.clear();
      model.value = '';
      secondModel.value = '';
      sourceError.value = error.toString();
    }
    try {
      gateway.value = await repository.proxyStatus();
    } catch (_) {
      gateway.value = const ProxyStatus.empty();
    }
  }

  /// Sends the prompt through the local gateway.
  ///
  /// The single tab targets one account, the compare and benchmark tabs run
  /// the prompt on every selected account and the dual tab asks two models.
  Future<void> run() async {
    if (running.value) return;
    final prompt = promptController.text.trim();
    if (prompt.isEmpty) return;

    running.value = true;
    lastResult.value = null;
    runError.value = null;
    results.clear();

    try {
      if (model.value.isEmpty ||
          (tab.value == PlaygroundTab.dual && secondModel.value.isEmpty)) {
        throw sourceError.value ?? Messages.accountsQuotaUnavailable.tr;
      }
      if ((tab.value == PlaygroundTab.compare ||
              tab.value == PlaygroundTab.benchmark) &&
          compareAccounts.isEmpty) {
        throw Messages.playgroundSelectAccounts.tr;
      }
      final status = await repository.proxyStatus();
      gateway.value = status;
      if (!status.running) {
        throw 'The local gateway is offline. Start it in the API proxy tab.';
      }
      final key = status.apiKey;
      if (key == null || key.isEmpty) {
        throw 'The local gateway has no API key.';
      }

      switch (tab.value) {
        case PlaygroundTab.compare:
        case PlaygroundTab.benchmark:
          await _runForAccounts(
            prompt,
            compareAccounts.toSet(),
            status.baseUrl,
            key,
          );
        case PlaygroundTab.dual:
          await _useAccount();
          results[model.value] = await _call(
            status.baseUrl,
            key,
            model.value,
            prompt,
          );
          results[secondModel.value] = await _call(
            status.baseUrl,
            key,
            secondModel.value,
            prompt,
          );
        case PlaygroundTab.single:
          await _useAccount();
          lastResult.value = await _call(
            status.baseUrl,
            key,
            model.value,
            prompt,
          );
      }
    } catch (error) {
      runError.value = error.toString();
      lastResult.value = PlaygroundResult(error: error.toString());
    } finally {
      running.value = false;
    }
  }

  /// Points the gateway at the chosen account, unless the pool routes it.
  Future<void> _useAccount() async {
    if (account.value != 'auto') {
      await repository.setActive(account.value);
    }
  }

  /// Sends the prompt to each account one after another.
  Future<void> _runForAccounts(
    String prompt,
    Set<String> accountIds,
    String baseUrl,
    String key,
  ) async {
    for (final id in accountIds) {
      await repository.setActive(id);
      results[id] = await _call(baseUrl, key, model.value, prompt);
    }
  }

  /// Calls the chat completions endpoint of the local gateway.
  Future<PlaygroundResult> _call(
    String baseUrl,
    String key,
    String modelId,
    String prompt,
  ) async {
    final client = HttpClient();
    final stopwatch = Stopwatch()..start();
    final streaming = stream.value;
    var status = 0;
    try {
      final request = await client.postUrl(
        Uri.parse('$baseUrl/v1/chat/completions'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(
        jsonEncode({
          'model': modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': temperature.value,
          'top_p': topP.value,
          'max_tokens': maxTokens.value,
          'stream': streaming,
        }),
      );

      final response = await request.close();
      status = response.statusCode;
      final body = await response.transform(utf8.decoder).join();
      stopwatch.stop();

      if (response.statusCode == 200) {
        if (streaming) {
          return PlaygroundResult(
            text: _streamedText(body),
            latencyMs: stopwatch.elapsedMilliseconds,
            tokens: _streamedTokens(body),
            status: 200,
          );
        }
        final payload = jsonDecode(body) as Map;
        final choices = payload['choices'] as List?;
        final message = (choices?.first as Map?)?['message'] as Map?;
        final text = message?['content'] as String? ?? '';
        return PlaygroundResult(
          text: text,
          latencyMs: stopwatch.elapsedMilliseconds,
          tokens: _tokenCount(payload),
          status: 200,
        );
      }

      return PlaygroundResult(
        error: _httpError(status, body),
        latencyMs: stopwatch.elapsedMilliseconds,
        status: status,
      );
    } on Exception catch (error) {
      return PlaygroundResult(
        error: error.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
        status: status,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _httpError(int status, String body) {
    var detailsStr = body;
    try {
      final payload = jsonDecode(body);
      Object? provider = payload;
      if (payload is Map && payload['error'] is Map) {
        final message = (payload['error'] as Map)['message'];
        if (message is String && message.trim().startsWith('{')) {
          try {
            provider = jsonDecode(message);
          } on FormatException {
            provider = payload;
          }
        }
      }
      detailsStr = const JsonEncoder.withIndent('  ').convert(provider);
    } on FormatException {
      detailsStr = body;
    }

    final parsedDetails = AccountErrorDetails.parse(body);

    var guidance = '';
    if (parsedDetails.isValidationRequired) {
      guidance = '${Messages.playgroundValidationRequired.tr}\n\n';
    } else if (parsedDetails.isTosViolation) {
      guidance = '${Messages.playgroundProviderRestricted.tr}\n\n';
    }

    if (parsedDetails.primaryActionUrl != null) {
      guidance += 'Action URL: ${parsedDetails.primaryActionUrl}\n\n';
    }

    return 'HTTP $status\n$guidance$detailsStr';
  }

  /// Reads the text out of a server sent event body.
  static String _streamedText(String body) {
    final buffer = StringBuffer();
    for (final line in body.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]' || data.isEmpty) continue;
      try {
        final payload = jsonDecode(data);
        final delta =
            (((payload as Map)['choices'] as List?)?.first as Map?)?['delta']
                as Map?;
        final content = delta?['content'] as String?;
        if (content != null) buffer.write(content);
      } on FormatException {
        // A partial chunk at the end of the stream is ignored.
      }
    }
    return buffer.toString();
  }

  static int _tokenCount(Object? payload) {
    final usage = (payload as Map?)?['usage'] as Map?;
    return (usage?['total_tokens'] as num?)?.toInt() ?? 0;
  }

  /// Reads the usage out of the last server sent event that carries it.
  static int _streamedTokens(String body) {
    var tokens = 0;
    for (final line in body.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]' || data.isEmpty) continue;
      try {
        final count = _tokenCount(jsonDecode(data));
        if (count > 0) tokens = count;
      } on FormatException {
        // A partial chunk at the end of the stream is ignored.
      }
    }
    return tokens;
  }

  @override
  void onClose() {
    promptController.dispose();
    super.onClose();
  }
}
