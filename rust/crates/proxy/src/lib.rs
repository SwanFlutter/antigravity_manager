//! The local API proxy of Antigravity Manager.
//!
//! The proxy speaks the protocols of the coding tools (OpenAI and Anthropic)
//! and forwards the requests to the Google Cloud Code service with the
//! credentials of the connected account. It listens on the loopback
//! interface and checks the local key of the proxy.

pub mod convert;

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use antigravity_core::cloud::{LeaseProvider, ProxyConfig, TrafficEntry};
use antigravity_core::domain::Model;
use antigravity_google::{Generator, GoogleError};
use axum::body::{Body, Bytes};
use axum::extract::{Path, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use futures::stream::StreamExt;
use serde_json::{json, Value};
use tokio::sync::RwLock;

/// The models the gateway can route to.
pub trait ModelCatalog: Send + Sync {
    /// Every model of the catalog.
    fn models(&self) -> Vec<Model>;

    /// Maps a requested model id onto the model the upstream understands.
    fn resolve(&self, requested: &str) -> Option<String>;
}

/// Writes the traffic log.
pub trait TrafficRecorder: Send + Sync {
    /// Stores one entry and returns its id.
    fn record(&self, entry: TrafficEntry) -> i64;
}

/// The state of the proxy.
#[derive(Clone)]
pub struct ProxyState {
    pub lease: Arc<dyn LeaseProvider>,
    pub models: Arc<dyn ModelCatalog>,
    pub traffic: Arc<dyn TrafficRecorder>,
    pub google: Arc<dyn Generator>,
    pub config: Arc<RwLock<ProxyConfig>>,
}

/// The protocol a request used.
#[derive(Clone, Copy, PartialEq)]
enum Protocol {
    Openai,
    Anthropic,
}

impl Protocol {
    fn as_str(&self) -> &'static str {
        match self {
            Protocol::Openai => "openai",
            Protocol::Anthropic => "anthropic",
        }
    }
}

/// The whole proxy.
pub fn router(state: ProxyState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(list_models))
        .route("/v1/models/{model}", get(get_model))
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/messages", post(messages))
        .with_state(state)
}

/// The health of the proxy.
async fn health() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

/// The models of the catalog.
async fn list_models(State(state): State<ProxyState>) -> Json<Value> {
    let data = state
        .models
        .models()
        .iter()
        .map(|model| {
            json!({
                "id": model.id,
                "object": "model",
                "created": 0,
                "owned_by": "antigravity",
            })
        })
        .collect::<Vec<Value>>();

    Json(json!({ "object": "list", "data": data }))
}

/// One model of the catalog.
async fn get_model(
    State(state): State<ProxyState>,
    Path(model): Path<String>,
) -> Response {
    match state
        .models
        .models()
        .iter()
        .find(|entry| entry.id == model)
    {
        Some(entry) => Json(json!({
            "id": entry.id,
            "object": "model",
            "created": 0,
            "owned_by": "antigravity",
        }))
        .into_response(),
        None => Json(json!({
            "error": {
                "message": format!("the model {model} does not exist"),
                "code": "model_not_found",
            }
        }))
        .into_response(),
    }
}

/// The OpenAI protocol.
async fn chat_completions(
    State(state): State<ProxyState>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    handle(state, headers, body, Protocol::Openai).await
}

/// The Anthropic protocol.
async fn messages(
    State(state): State<ProxyState>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    handle(state, headers, body, Protocol::Anthropic).await
}

/// The current time in seconds since the Unix epoch.
fn now_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs() as i64)
        .unwrap_or(0)
}

/// The current time in milliseconds since the Unix epoch.
fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis() as i64)
        .unwrap_or(0)
}

/// Reads the key of a request.
fn request_key(headers: &HeaderMap) -> Option<String> {
    let pairs = headers
        .iter()
        .map(|(name, value)| {
            (
                name.as_str().to_lowercase(),
                value.to_str().unwrap_or_default().to_string(),
            )
        })
        .collect::<Vec<(String, String)>>();

    convert::extract_key(&pairs)
}

/// The error body of the OpenAI protocol.
fn openai_error(status: StatusCode, message: &str, code: &str) -> Response {
    (
        status,
        Json(json!({
            "error": {
                "message": message,
                "type": "invalid_request_error",
                "code": code,
            }
        })),
    )
        .into_response()
}

/// The error body of the Anthropic protocol.
fn anthropic_error(status: StatusCode, message: &str, kind: &str) -> Response {
    (
        status,
        Json(json!({
            "type": "error",
            "error": { "type": kind, "message": message },
        })),
    )
        .into_response()
}

/// The error body of a protocol.
fn error_of(protocol: Protocol, status: StatusCode, message: &str, code: &str) -> Response {
    match protocol {
        Protocol::Openai => openai_error(status, message, code),
        Protocol::Anthropic => anthropic_error(status, message, code),
    }
}

/// Checks the key of the proxy.
async fn authorize(
    state: &ProxyState,
    protocol: Protocol,
    headers: &HeaderMap,
) -> Result<(), Response> {
    let config = state.config.read().await;
    let Some(expected) = config.api_key.as_ref().filter(|key| !key.is_empty()) else {
        // Without a key the proxy accepts every request.
        return Ok(());
    };

    let presented = request_key(headers);
    if presented.as_deref() == Some(expected.as_str()) {
        return Ok(());
    }

    Err(error_of(
        protocol,
        StatusCode::UNAUTHORIZED,
        "the API key of the proxy is missing or wrong",
        "invalid_api_key",
    ))
}

/// Answers one request of a coding tool.
async fn handle(
    state: ProxyState,
    headers: HeaderMap,
    body: Bytes,
    protocol: Protocol,
) -> Response {
    let started = now_millis();

    if let Err(response) = authorize(&state, protocol, &headers).await {
        return response;
    }

    let request_bytes = body.len() as u64;
    let payload: Value = match serde_json::from_slice(&body) {
        Ok(payload) => payload,
        Err(error) => {
            let response = error_of(
                protocol,
                StatusCode::BAD_REQUEST,
                &format!("the body of the request is not valid JSON: {error}"),
                "invalid_request",
            );
            record(
                &state,
                protocol,
                "",
                None,
                StatusCode::BAD_REQUEST,
                started,
                request_bytes,
                0,
                Some(error.to_string()),
            );
            return response;
        }
    };

    let requested_model = payload
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    let Some(resolved) = state.models.resolve(&requested_model) else {
        let response = error_of(
            protocol,
            StatusCode::NOT_FOUND,
            &format!("the model {requested_model} does not exist"),
            "model_not_found",
        );
        record(
            &state,
            protocol,
            &requested_model,
            None,
            StatusCode::NOT_FOUND,
            started,
            request_bytes,
            0,
            Some("unknown model".to_string()),
        );
        return response;
    };

    let lease = match state.lease.lease().await {
        Ok(lease) => lease,
        Err(error) => {
            let response = error_of(
                protocol,
                StatusCode::SERVICE_UNAVAILABLE,
                &format!("no Google account is connected: {error}"),
                "no_account",
            );
            record(
                &state,
                protocol,
                &requested_model,
                None,
                StatusCode::SERVICE_UNAVAILABLE,
                started,
                request_bytes,
                0,
                Some(error.to_string()),
            );
            return response;
        }
    };

    let request_id = uuid::Uuid::new_v4().simple().to_string();
    let internal = convert::internal_request(
        &payload,
        &resolved,
        lease.project_id.as_deref(),
        &request_id,
    );

    let streaming = payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if streaming {
        return stream_answer(
            state,
            protocol,
            lease.account_id,
            requested_model,
            internal,
            lease.access_token,
            lease.project_id,
            request_bytes,
            started,
        )
        .await;
    }

    match state
        .google
        .generate(&lease.access_token, lease.project_id.as_deref(), &internal)
        .await
    {
        Ok(response) => {
            let answer = match protocol {
                Protocol::Openai => convert::to_openai_answer(
                    &response,
                    &requested_model,
                    &request_id,
                    now_seconds(),
                ),
                Protocol::Anthropic => {
                    convert::to_anthropic_answer(&response, &requested_model, &request_id)
                }
            };

            let encoded = serde_json::to_vec(&answer).unwrap_or_default();
            record(
                &state,
                protocol,
                &requested_model,
                Some(lease.account_id),
                StatusCode::OK,
                started,
                request_bytes,
                encoded.len() as u64,
                None,
            );

            Json(answer).into_response()
        }
        Err(error) => {
            let (status, message) = match &error {
                GoogleError::Upstream { status, message } => {
                    (StatusCode::from_u16(*status).unwrap_or(StatusCode::BAD_GATEWAY), message.clone())
                }
                _ => (StatusCode::BAD_GATEWAY, error.to_string()),
            };

            let response = error_of(protocol, status, &message, "upstream_error");
            record(
                &state,
                protocol,
                &requested_model,
                Some(lease.account_id),
                status,
                started,
                request_bytes,
                0,
                Some(message),
            );
            response
        }
    }
}

/// The state of the streaming answer.
struct StreamState {
    buffer: Vec<u8>,
    started_events: bool,
    finished: bool,
    written: u64,
    prompt_tokens: u64,
    output_tokens: u64,
}

/// Streams the answer of the upstream service.
#[allow(clippy::too_many_arguments)]
async fn stream_answer(
    state: ProxyState,
    protocol: Protocol,
    account_id: String,
    requested_model: String,
    internal: Value,
    access_token: String,
    project: Option<String>,
    request_bytes: u64,
    started: i64,
) -> Response {
    let upstream = match state
        .google
        .stream(&access_token, project.as_deref(), &internal)
        .await
    {
        Ok(upstream) => upstream,
        Err(error) => {
            let (status, message) = match &error {
                GoogleError::Upstream { status, message } => {
                    (StatusCode::from_u16(*status).unwrap_or(StatusCode::BAD_GATEWAY), message.clone())
                }
                _ => (StatusCode::BAD_GATEWAY, error.to_string()),
            };

            let response = error_of(protocol, status, &message, "upstream_error");
            record(
                &state,
                protocol,
                &requested_model,
                Some(account_id),
                status,
                started,
                request_bytes,
                0,
                Some(message),
            );
            return response;
        }
    };

    let id = uuid::Uuid::new_v4().simple().to_string();
    let created = now_seconds();
    let traffic = state.traffic.clone();
    let recorder = state.traffic.clone();
    let model_for_traffic = requested_model.clone();
    // The closing events of the stream need the id and the model again.
    let closing_id = id.clone();
    let closing_model = requested_model.clone();

    let stream = futures::stream::unfold(
        (
            upstream,
            StreamState {
                buffer: Vec::new(),
                started_events: false,
                finished: false,
                written: 0,
                prompt_tokens: 0,
                output_tokens: 0,
            },
        ),
        move |(mut upstream, mut stream_state)| {
            let traffic = traffic.clone();
            let recorder = recorder.clone();
            let model_for_traffic = model_for_traffic.clone();
            let account_id = account_id.clone();
            let requested_model = requested_model.clone();
            let id = id.clone();

            async move {
                loop {
                    if stream_state.finished {
                        let duration = now_millis() - started;
                        recorder.record(TrafficEntry {
                            id: 0,
                            at: started,
                            protocol: protocol.as_str().to_string(),
                            model: model_for_traffic,
                            account_id: Some(account_id),
                            status: 200,
                            duration_ms: duration as u64,
                            request_bytes,
                            response_bytes: stream_state.written,
                            error: None,
                        });
                        return None;
                    }

                    let chunk = match upstream.next().await {
                        Some(Ok(chunk)) => chunk,
                        Some(Err(_)) | None => {
                            stream_state.finished = true;
                            continue;
                        }
                    };

                    stream_state.buffer.extend_from_slice(&chunk);
                    let text = String::from_utf8_lossy(&stream_state.buffer).to_string();
                    let mut pieces = Vec::new();

                    for line in text.split('\n') {
                        let line = line.trim();
                        if !line.starts_with("data:") {
                            continue;
                        }
                        let payload = line.trim_start_matches("data:").trim();
                        if payload.is_empty() || payload == "[DONE]" {
                            continue;
                        }
                        let Ok(value) = serde_json::from_str::<Value>(payload) else {
                            continue;
                        };
                        pieces.push(value);
                    }

                    // Everything up to the last newline was consumed.
                    if let Some(position) = text.rfind('\n') {
                        stream_state.buffer = text[position + 1..].as_bytes().to_vec();
                    } else {
                        stream_state.buffer.clear();
                    }

                    if pieces.is_empty() {
                        continue;
                    }

                    let mut out = Vec::new();

                    for piece in &pieces {
                        let (prompt, completion, _) = convert::usage(piece);
                        stream_state.prompt_tokens = stream_state.prompt_tokens.max(prompt);
                        stream_state.output_tokens = stream_state.output_tokens.max(completion);

                        let text = convert::answer_text(piece);
                        if text.is_empty() {
                            continue;
                        }

                        match protocol {
                            Protocol::Openai => {
                                let chunk = convert::to_openai_chunk(
                                    &id,
                                    created,
                                    &requested_model,
                                    json!({ "content": text }),
                                    Value::Null,
                                );
                                out.extend_from_slice(
                                    format!("data: {chunk}\n\n").as_bytes(),
                                );
                            }
                            Protocol::Anthropic => {
                                if !stream_state.started_events {
                                    stream_state.started_events = true;
                                    let events = convert::to_anthropic_events(
                                        &id,
                                        &requested_model,
                                        "",
                                        0,
                                        0,
                                    );
                                    // The start of the message and the start of
                                    // the block are sent once.
                                    for event in events.iter().take(2) {
                                        out.extend_from_slice(event.as_bytes());
                                    }
                                }

                                let event = format!(
                                    "event: content_block_delta\ndata: {}\n\n",
                                    json!({
                                        "type": "content_block_delta",
                                        "index": 0,
                                        "delta": { "type": "text_delta", "text": text },
                                    })
                                );
                                out.extend_from_slice(event.as_bytes());
                            }
                        }
                    }

                    if out.is_empty() {
                        continue;
                    }

                    stream_state.written += out.len() as u64;

                    let _ = traffic;
                    return Some((
                        Ok::<Bytes, std::io::Error>(Bytes::from(out)),
                        (upstream, stream_state),
                    ));
                }
            }
        },
    );

    let closing = futures::stream::once(async move {
        Ok::<Bytes, std::io::Error>(Bytes::from(match protocol {
            Protocol::Openai => {
                let chunk = convert::to_openai_chunk(
                    &closing_id,
                    created,
                    &closing_model,
                    json!({}),
                    json!("stop"),
                );
                format!("data: {chunk}\n\ndata: [DONE]\n\n")
            }
            Protocol::Anthropic => {
                let events = convert::to_anthropic_events(
                    &closing_id,
                    &closing_model,
                    "",
                    0,
                    0,
                );
                // The closing events of the message.
                events[2..].concat()
            }
        }))
    });

    let body = Body::from_stream(stream.chain(closing));

    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "text/event-stream")
        .header(header::CACHE_CONTROL, "no-cache")
        .header(header::CONNECTION, "keep-alive")
        .body(body)
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

/// Writes one entry into the traffic log.
fn record(
    state: &ProxyState,
    protocol: Protocol,
    model: &str,
    account_id: Option<String>,
    status: StatusCode,
    started: i64,
    request_bytes: u64,
    response_bytes: u64,
    error: Option<String>,
) {
    state.traffic.record(TrafficEntry {
        id: 0,
        at: started,
        protocol: protocol.as_str().to_string(),
        model: model.to_string(),
        account_id,
        status: status.as_u16(),
        duration_ms: (now_millis() - started) as u64,
        request_bytes,
        response_bytes,
        error,
    });
}
