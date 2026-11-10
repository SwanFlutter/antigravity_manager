import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../core/data/mock_data.dart';
import '../../../data/accounts_repository.dart';
import 'app_controller.dart';

enum PlaygroundTab { single, compare, benchmark, dual }

/// One finished playground request.
class PlaygroundResult {
  const PlaygroundResult({
    this.text = '',
    this.error,
    this.latencyMs = 0,
    this.tokens = 0,
  });

  final String text;
  final String? error;
  final int latencyMs;
  final int tokens;

  bool get isError => error != null;
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

  final RxList<Account> accounts = MockData.accounts.obs;

  final RxList<String> models = MockData.catalogModelIds.obs;

  @override
  void onInit() {
    super.onInit();
    loadSources();
    // The host may still be starting; reload once it answers.
    ever(Get.find<AppController>().hostReady, (_) => loadSources());
  }

  /// Reads the account pool and the model catalog from the repository.
  Future<void> loadSources() async {
    try {
      final snapshot = await repository.load();
      if (snapshot.accounts.isNotEmpty) {
        accounts.assignAll(snapshot.accounts);
        compareAccounts.assignAll(snapshot.accounts.map((a) => a.id));
      }
    } catch (_) {
      // The screen keeps its placeholder state.
    }
    try {
      final catalog = await repository.modelCatalog();
      if (catalog.isNotEmpty) {
        models.assignAll([for (final model in catalog) model.id]);
      }
    } catch (_) {
      // The screen keeps its placeholder state.
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
    results.clear();

    try {
      final status = await repository.proxyStatus();
      if (!status.running) {
        throw 'The local gateway is offline. Start it in the API proxy tab.';
      }
      final key = status.apiKey;
      if (key == null || key.isEmpty) {
        throw 'The local gateway has no API key.';
      }

      switch (tab.value) {
        case PlaygroundTab.compare:
          await _runForAccounts(prompt, _targetAccounts(), status.baseUrl, key);
        case PlaygroundTab.benchmark:
          await _runForAccounts(
            prompt,
            accounts.map((a) => a.id).toSet(),
            status.baseUrl,
            key,
          );
        case PlaygroundTab.dual:
          await _useAccount();
          results[model.value] =
              await _call(status.baseUrl, key, model.value, prompt);
          results[secondModel.value] =
              await _call(status.baseUrl, key, secondModel.value, prompt);
        case PlaygroundTab.single:
          await _useAccount();
          lastResult.value =
              await _call(status.baseUrl, key, model.value, prompt);
      }
    } catch (error) {
      lastResult.value = PlaygroundResult(error: error.toString());
    } finally {
      running.value = false;
    }
  }

  /// The accounts the compare tab targets: the selection, or the whole pool.
  Set<String> _targetAccounts() {
    if (compareAccounts.isNotEmpty) return compareAccounts.toSet();
    return accounts.map((a) => a.id).toSet();
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
    try {
      final stopwatch = Stopwatch()..start();
      final request = await client.postUrl(
        Uri.parse('$baseUrl/v1/chat/completions'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(jsonEncode({
        'model': modelId,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': temperature.value,
        'top_p': topP.value,
        'max_tokens': maxTokens.value,
        'stream': stream.value,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      stopwatch.stop();

      if (response.statusCode == 200) {
        if (stream.value) {
          return PlaygroundResult(
            text: _streamedText(body),
            latencyMs: stopwatch.elapsedMilliseconds,
            tokens: _streamedTokens(body),
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
        );
      }

      final payload = jsonDecode(body) as Map;
      final error = payload['error'] as Map?;
      final message = error?['message'] as String?;
      return PlaygroundResult(
        error: 'HTTP ${response.statusCode}: ${message ?? body}',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on Exception catch (error) {
      return PlaygroundResult(error: error.toString());
    } finally {
      client.close(force: true);
    }
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
        final delta = (((payload as Map)['choices'] as List?)?.first
            as Map?)?['delta'] as Map?;
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
