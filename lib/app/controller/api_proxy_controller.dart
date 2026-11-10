import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../core/data/mock_data.dart';
import '../../../data/accounts_repository.dart';
import '../../../data/cloud_models.dart';
import 'app_controller.dart';

/// The wire protocol a client speaks with the local gateway.
enum ProxyProtocol { openai, anthropic }

/// State of the local API proxy screen.
class ApiProxyController extends GetXController {
  /// The service health is owned by the shell so the sidebar stays in sync.
  final AppController app = Get.find<AppController>();

  /// The source of the proxy state. The local proxy lives in the Rust host.
  final AccountsRepository repository = defaultAccountsRepository();

  /// The state of the local proxy.
  final Rx<ProxyStatus> proxy = const ProxyStatus.empty().obs;

  /// The newest requests that passed through the local proxy.
  final RxList<TrafficRecord> traffic = <TrafficRecord>[].obs;

  bool get running => proxy.value.running;

  final RxBool revealKey = false.obs;
  final RxBool autoStart = true.obs;
  final RxInt tab = 0.obs;
  final RxList<ModelMapping> mappings = MockData.modelMappings.obs;

  /// The catalog the gateway can route to.
  final RxList<CatalogModel> catalog = MockData.modelCatalog.obs;

  /// Every model id a client can send inside a request body.
  List<String> get modelIds => [for (final model in catalog) model.id];

  /// The model used inside the generated usage examples.
  final RxString selectedExampleModel = 'gemini-3.1-pro-high'.obs;

  /// The protocol the generated usage examples target.
  final Rx<ProxyProtocol> protocol = ProxyProtocol.openai.obs;

  /// The address the coding tools talk to.
  String get baseUrl => proxy.value.baseUrl;

  /// The key the coding tools have to send.
  String get apiKey => proxy.value.apiKey ?? keyController.text;

  /// The key with its middle hidden.
  String get maskedApiKey {
    if (revealKey.value) return apiKey;
    final key = apiKey;
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
  }

  String get chatEndpoint => '$baseUrl/v1/chat/completions';

  String get messagesEndpoint => '$baseUrl/v1/messages';

  String get exampleModel => selectedExampleModel.value;

  /// The curl snippet for the selected protocol and model.
  String get curlSnippet {
    if (protocol.value == ProxyProtocol.anthropic) {
      return '''curl $messagesEndpoint \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: YOUR_API_KEY" \\
  -H "anthropic-version: 2023-06-01" \\
  -d '{
    "model": "$exampleModel",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello"}]
  }\'''';
    }

    return '''curl $chatEndpoint \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -d '{
    "model": "$exampleModel",
    "messages": [{"role": "user", "content": "Hello"}]
  }\'''';
  }

  /// The python snippet for the selected protocol and model.
  String get pythonSnippet {
    if (protocol.value == ProxyProtocol.anthropic) {
      return '''import anthropic

client = anthropic.Anthropic(
    base_url="$baseUrl",
    api_key="YOUR_API_KEY"
)

message = client.messages.create(
    model="$exampleModel",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}]
)
print(message.content[0].text)''';
    }

    return '''from openai import OpenAI

client = OpenAI(
    base_url="$baseUrl/v1",
    api_key="YOUR_API_KEY"
)

response = client.chat.completions.create(
    model="$exampleModel",
    messages=[{"role": "user", "content": "Hello"}]
)
print(response.choices[0].message.content)''';
  }

  /// The javascript snippet for the selected protocol and model.
  String get nodeSnippet {
    if (protocol.value == ProxyProtocol.anthropic) {
      return '''const response = await fetch("$messagesEndpoint", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "x-api-key": "YOUR_API_KEY",
    "anthropic-version": "2023-06-01",
  },
  body: JSON.stringify({
    model: "$exampleModel",
    max_tokens: 1024,
    messages: [{ role: "user", content: "Hello" }],
  }),
});''';
    }

    return '''const response = await fetch("$chatEndpoint", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": "Bearer YOUR_API_KEY",
  },
  body: JSON.stringify({
    model: "$exampleModel",
    messages: [{ role: "user", content: "Hello" }],
  }),
});''';
  }

  final TextEditingController portController = TextEditingController(
    text: '8045',
  );
  final TextEditingController timeoutController = TextEditingController(
    text: '120',
  );
  final TextEditingController keyController = TextEditingController(
    text: 'sk-9f4c21ab7de305687f2a1c0b4e8d3a95',
  );

  final List<String> networks = [
    'Local network (Wi-Fi)',
    'Loopback only',
    'Virtual adapter',
  ];
  final RxString selectedNetwork = 'Local network (Wi-Fi)'.obs;

  static const String maskedKey = '•••• •••• •••• 5a2c';

  @override
  void onInit() {
    super.onInit();
    loadProxy();
  }

  /// Reads the state of the local proxy and its traffic.
  Future<void> loadProxy() async {
    try {
      final status = await repository.proxyStatus();
      proxy.value = status;
      app.proxyRunning.value = status.running;
      if (status.apiKey != null) keyController.text = status.apiKey!;
      // The port of the host is the truth: the field follows it.
      portController.text = status.port.toString();
    } catch (_) {
      // The host is not running, the screen keeps its placeholder state.
    }

    try {
      traffic.assignAll(await repository.traffic());
    } catch (_) {
      traffic.clear();
    }

    try {
      final models = await repository.modelCatalog();
      if (models.isNotEmpty) {
        catalog.assignAll(models);
        _alignToCatalog();
      }
    } catch (_) {
      // The screen keeps its placeholder catalog.
    }
  }

  /// Points the example model and the mapping targets at real catalog ids.
  void _alignToCatalog() {
    final ids = modelIds;
    if (ids.isEmpty) return;
    if (!ids.contains(selectedExampleModel.value)) {
      selectedExampleModel.value = ids.first;
    }
    for (var i = 0; i < mappings.length; i++) {
      final current = mappings[i];
      if (!ids.contains(current.target)) {
        mappings[i] = ModelMapping(
          source: current.source,
          target: ids.first,
          enabled: current.enabled,
        );
      }
    }
  }

  /// Starts the local proxy.
  Future<void> startProxy() async {
    final port = int.tryParse(portController.text.trim());
    final status = await repository.startProxy(port: port);
    proxy.value = status;
    app.proxyRunning.value = status.running;
    portController.text = status.port.toString();
  }

  /// Stops the local proxy.
  Future<void> stopProxy() async {
    final status = await repository.stopProxy();
    proxy.value = status;
    app.proxyRunning.value = status.running;
  }

  /// Replaces the key of the local proxy.
  Future<void> rotateKey() async {
    final status = await repository.rotateProxyKey();
    proxy.value = status;
    if (status.apiKey != null) keyController.text = status.apiKey!;
    revealKey.value = false;
  }

  @override
  void onClose() {
    portController.dispose();
    timeoutController.dispose();
    keyController.dispose();
    super.onClose();
  }

  void regenerateKey() {
    rotateKey();
  }

  void restoreDefaults() {
    mappings.assignAll(MockData.modelMappings);
  }

  void updateMapping(int index, String target) {
    final current = mappings[index];
    mappings[index] = ModelMapping(
      source: current.source,
      target: target,
      enabled: current.enabled,
    );
  }
}
