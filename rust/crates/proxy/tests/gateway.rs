//! The end to end test of the local gateway.
//!
//! The test starts the real router on a real socket and talks to it with a
//! real HTTP client. Only the upstream service is replaced by a fake, so the
//! routing, the key guard, the translation of the protocols and the streaming
//! are all covered without touching the network.

use std::sync::{Arc, Mutex};

use antigravity_core::cloud::{AccountLease, LeaseProvider, ProxyConfig, TrafficEntry};
use antigravity_core::domain::{Model, ModelFamily};
use antigravity_google::{ByteStream, Generator, GoogleError};
use antigravity_proxy::{ModelCatalog, ProxyState, TrafficRecorder};
use futures::future::BoxFuture;
use serde_json::{json, Value};
use tokio::sync::RwLock;

// ---------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------

/// The account the fake lease hands out.
struct FakeLease {
    available: bool,
}

impl LeaseProvider for FakeLease {
    fn lease(&self) -> BoxFuture<'_, Result<AccountLease, antigravity_core::repository::RepositoryError>> {
        Box::pin(async move {
            if !self.available {
                return Err(antigravity_core::repository::RepositoryError::NotFound(
                    "no Google account is connected".to_string(),
                ));
            }

            Ok(AccountLease {
                account_id: "acc-01".to_string(),
                email: "user@example.com".to_string(),
                access_token: "token-1".to_string(),
                project_id: Some("project-1".to_string()),
            })
        })
    }
}

/// The catalog of the fake provider.
struct FakeCatalog;

impl ModelCatalog for FakeCatalog {
    fn models(&self) -> Vec<Model> {
        vec![Model {
            id: "gemini-3.8-flash-high".to_string(),
            label: "Gemini 3.8 Flash (High)".to_string(),
            family: ModelFamily::Gemini,
        }]
    }

    fn resolve(&self, requested: &str) -> Option<String> {
        if requested == "gemini-3.8-flash-high" {
            return Some(requested.to_string());
        }
        // The coding tools ask for their own model names.
        self.models().first().map(|model| model.id.clone())
    }
}

/// The traffic log of the fake provider.
#[derive(Default)]
struct FakeTraffic {
    entries: Mutex<Vec<TrafficEntry>>,
}

impl TrafficRecorder for FakeTraffic {
    fn record(&self, entry: TrafficEntry) -> i64 {
        let mut entries = self.entries.lock().expect("the log is not poisoned");
        entries.push(entry);
        entries.len() as i64
    }
}

/// The upstream service of the fake provider.
struct FakeGenerator {
    answer: Value,
    chunks: Vec<String>,
    fail: bool,
}

impl Generator for FakeGenerator {
    fn generate<'a>(
        &'a self,
        _access_token: &'a str,
        _project: Option<&'a str>,
        _body: &'a Value,
    ) -> BoxFuture<'a, Result<Value, GoogleError>> {
        Box::pin(async move {
            if self.fail {
                return Err(GoogleError::Upstream {
                    status: 503,
                    message: "the quota of the account is empty".to_string(),
                });
            }
            Ok(self.answer.clone())
        })
    }

    fn stream<'a>(
        &'a self,
        _access_token: &'a str,
        _project: Option<&'a str>,
        _body: &'a Value,
    ) -> BoxFuture<'a, Result<ByteStream, GoogleError>> {
        Box::pin(async move {
            if self.fail {
                return Err(GoogleError::Upstream {
                    status: 503,
                    message: "the quota of the account is empty".to_string(),
                });
            }

            let chunks: Vec<Result<Vec<u8>, std::io::Error>> = self
                .chunks
                .iter()
                .map(|chunk| Ok(chunk.as_bytes().to_vec()))
                .collect();
            let stream = futures::stream::iter(chunks);
            Ok(Box::pin(stream) as ByteStream)
        })
    }
}

/// The answer of the fake provider.
fn answer() -> Value {
    json!({
        "response": {
            "candidates": [{
                "content": { "role": "model", "parts": [{ "text": "Hello there" }] },
                "finishReason": "STOP",
            }],
            "usageMetadata": {
                "promptTokenCount": 12,
                "candidatesTokenCount": 34,
                "totalTokenCount": 46,
            },
        }
    })
}

/// Builds the state of the gateway.
fn state(
    api_key: Option<&str>,
    lease: FakeLease,
    generator: Arc<FakeGenerator>,
    traffic: Arc<FakeTraffic>,
) -> ProxyState {
    ProxyState {
        lease: Arc::new(lease),
        models: Arc::new(FakeCatalog),
        traffic,
        google: generator,
        config: Arc::new(RwLock::new(ProxyConfig {
            api_key: api_key.map(str::to_string),
            port: 0,
            auto_start: false,
            selected_account_id: None,
        })),
    }
}

/// Starts the gateway on a free port and returns its address.
async fn serve(state: ProxyState) -> String {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("the socket is free");
    let port = listener.local_addr().expect("the socket has an address").port();

    let router = antigravity_proxy::router(state);
    tokio::spawn(async move {
        let _ = axum::serve(listener, router).await;
    });

    format!("http://127.0.0.1:{port}")
}

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

#[tokio::test]
async fn the_health_and_the_catalog_answer_without_a_key() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: false,
    });
    let base = serve(state(None, FakeLease { available: true }, generator, traffic)).await;

    let health = reqwest::get(format!("{base}/health"))
        .await
        .expect("the health answers");
    assert_eq!(health.status(), 200);
    assert_eq!(
        health.json::<Value>().await.expect("the health is json"),
        json!({ "status": "ok" })
    );

    let models = reqwest::get(format!("{base}/v1/models"))
        .await
        .expect("the catalog answers");
    assert_eq!(models.status(), 200);
    let payload = models.json::<Value>().await.expect("the catalog is json");
    assert_eq!(payload["object"], "list");
    assert_eq!(payload["data"][0]["id"], "gemini-3.8-flash-high");
}

#[tokio::test]
async fn a_request_without_the_key_is_refused() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: false,
    });
    let base = serve(state(
        Some("sk-0123456789abcdef0123456789abcdef"),
        FakeLease { available: true },
        generator,
        traffic,
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/chat/completions"))
        .json(&json!({
            "model": "gpt-5-1",
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 401);
    let payload = answer.json::<Value>().await.expect("the error is json");
    assert_eq!(payload["error"]["code"], "invalid_api_key");
}

#[tokio::test]
async fn the_openai_protocol_is_answered() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: false,
    });
    let base = serve(state(
        Some("sk-0123456789abcdef0123456789abcdef"),
        FakeLease { available: true },
        generator,
        traffic.clone(),
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/chat/completions"))
        .header("Authorization", "Bearer sk-0123456789abcdef0123456789abcdef")
        .json(&json!({
            "model": "gpt-5-1",
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 200);
    let payload = answer.json::<Value>().await.expect("the answer is json");
    assert_eq!(payload["object"], "chat.completion");
    assert_eq!(payload["choices"][0]["message"]["content"], "Hello there");
    assert_eq!(payload["usage"]["total_tokens"], 46);

    // The request is written into the traffic log.
    let entries = traffic.entries.lock().expect("the log is not poisoned");
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].protocol, "openai");
    assert_eq!(entries[0].status, 200);
    assert_eq!(entries[0].account_id.as_deref(), Some("acc-01"));
}

#[tokio::test]
async fn the_anthropic_protocol_is_answered() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: false,
    });
    let base = serve(state(
        Some("sk-0123456789abcdef0123456789abcdef"),
        FakeLease { available: true },
        generator,
        traffic,
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/messages"))
        .header("x-api-key", "sk-0123456789abcdef0123456789abcdef")
        .json(&json!({
            "model": "claude-sonnet-4-6",
            "max_tokens": 256,
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 200);
    let payload = answer.json::<Value>().await.expect("the answer is json");
    assert_eq!(payload["type"], "message");
    assert_eq!(payload["content"][0]["text"], "Hello there");
    assert_eq!(payload["stop_reason"], "end_turn");
    assert_eq!(payload["usage"]["input_tokens"], 12);
}

#[tokio::test]
async fn a_streaming_answer_is_forwarded_as_server_sent_events() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: vec![
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"}]}}]}\n\n".to_string(),
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" there\"}]}}]}\n\n".to_string(),
        ],
        fail: false,
    });
    let base = serve(state(
        Some("sk-0123456789abcdef0123456789abcdef"),
        FakeLease { available: true },
        generator,
        traffic,
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/chat/completions"))
        .header("Authorization", "Bearer sk-0123456789abcdef0123456789abcdef")
        .json(&json!({
            "model": "gpt-5-1",
            "stream": true,
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 200);
    assert_eq!(
        answer
            .headers()
            .get("content-type")
            .and_then(|value| value.to_str().ok()),
        Some("text/event-stream")
    );

    let body = answer.text().await.expect("the stream is text");
    assert!(body.contains("chat.completion.chunk"), "{body}");
    assert!(body.contains("Hello"), "{body}");
    assert!(body.contains("data: [DONE]"), "{body}");
}

#[tokio::test]
async fn a_request_without_a_connected_account_is_refused() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: false,
    });
    let base = serve(state(
        None,
        FakeLease { available: false },
        generator,
        traffic,
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/chat/completions"))
        .json(&json!({
            "model": "gpt-5-1",
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 503);
    let payload = answer.json::<Value>().await.expect("the error is json");
    assert_eq!(payload["error"]["code"], "no_account");
}

#[tokio::test]
async fn the_error_of_the_upstream_service_is_forwarded() {
    let traffic = Arc::new(FakeTraffic::default());
    let generator = Arc::new(FakeGenerator {
        answer: answer(),
        chunks: Vec::new(),
        fail: true,
    });
    let base = serve(state(
        None,
        FakeLease { available: true },
        generator,
        traffic,
    ))
    .await;

    let answer = reqwest::Client::new()
        .post(format!("{base}/v1/messages"))
        .json(&json!({
            "model": "claude-sonnet-4-6",
            "messages": [{ "role": "user", "content": "Hello" }],
        }))
        .send()
        .await
        .expect("the gateway answers");

    assert_eq!(answer.status(), 503);
    let payload = answer.json::<Value>().await.expect("the error is json");
    assert_eq!(payload["type"], "error");
    assert!(payload["error"]["message"]
        .as_str()
        .unwrap_or_default()
        .contains("quota"));
}
