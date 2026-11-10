//! The translation between the protocols of the coding tools and the internal
//! protocol of Google.
//!
//! The functions of this module are pure: they read a JSON body and build
//! another JSON body, so they can be tested without a network.

use serde_json::{json, Map, Value};

/// The identity the upstream application sends with every request.
pub const USER_AGENT: &str = "antigravity/0.1.0 windows/amd64";

/// The internal request of Google.
///
/// It carries the conversation, the model and the project of the account.
pub fn internal_request(
    body: &Value,
    model: &str,
    project: Option<&str>,
    request_id: &str,
) -> Value {
    let mut request = Map::new();

    let contents = match body.get("messages").and_then(Value::as_array) {
        Some(messages) => messages
            .iter()
            .filter_map(|message| {
                let role = message.get("role").and_then(Value::as_str).unwrap_or("user");
                // The system prompt of the OpenAI protocol travels inside the
                // messages. It belongs to the system instruction of the
                // internal protocol, not to the conversation.
                if is_system_role(role) {
                    return None;
                }
                let text = message_text(message.get("content"));
                if text.trim().is_empty() {
                    return None;
                }
                Some(json!({
                    "role": internal_role(role),
                    "parts": [{ "text": text }],
                }))
            })
            .collect::<Vec<Value>>(),
        None => Vec::new(),
    };

    request.insert("contents".to_string(), Value::Array(contents));

    if let Some(system) = system_text(body) {
        request.insert(
            "systemInstruction".to_string(),
            json!({ "role": "user", "parts": [{ "text": system }] }),
        );
    }

    if let Some(config) = generation_config(body) {
        request.insert("generationConfig".to_string(), config);
    }

    let mut envelope = Map::new();
    if let Some(project) = project.filter(|value| !value.trim().is_empty()) {
        envelope.insert("project".to_string(), Value::String(project.to_string()));
    }
    envelope.insert("requestId".to_string(), Value::String(request_id.to_string()));
    envelope.insert("request".to_string(), Value::Object(request));
    envelope.insert("model".to_string(), Value::String(model.to_string()));
    envelope.insert("userAgent".to_string(), Value::String(USER_AGENT.to_string()));
    envelope.insert("requestType".to_string(), Value::String("agent".to_string()));

    Value::Object(envelope)
}

/// The role of a message inside the internal protocol.
pub fn internal_role(role: &str) -> &'static str {
    match role {
        "assistant" | "model" => "model",
        _ => "user",
    }
}

/// Whether a role carries the system prompt of a request.
fn is_system_role(role: &str) -> bool {
    matches!(role, "system" | "developer")
}

/// The text of a message, whether it is a string or a list of blocks.
pub fn message_text(content: Option<&Value>) -> String {
    match content {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Array(blocks)) => blocks
            .iter()
            .filter_map(|block| {
                if block.get("type").and_then(Value::as_str) == Some("text") {
                    block.get("text").and_then(Value::as_str)
                } else {
                    None
                }
            })
            .collect::<Vec<&str>>()
            .join("\n"),
        _ => String::new(),
    }
}

/// The system instruction of a request.
///
/// The Anthropic protocol carries the system prompt next to the messages, the
/// OpenAI protocol inside the first message with the role `system`.
fn system_text(body: &Value) -> Option<String> {
    if let Some(system) = body.get("system").and_then(Value::as_str) {
        if !system.trim().is_empty() {
            return Some(system.to_string());
        }
    }

    let messages = body.get("messages").and_then(Value::as_array)?;
    let system = messages
        .iter()
        .filter(|message| {
            message
                .get("role")
                .and_then(Value::as_str)
                .map(is_system_role)
                .unwrap_or(false)
        })
        .map(|message| message_text(message.get("content")))
        .filter(|text| !text.trim().is_empty())
        .collect::<Vec<String>>();

    if system.is_empty() {
        None
    } else {
        Some(system.join("\n\n"))
    }
}

/// The generation configuration of a request.
fn generation_config(body: &Value) -> Option<Value> {
    let mut config = Map::new();

    if let Some(temperature) = body.get("temperature").and_then(Value::as_f64) {
        config.insert("temperature".to_string(), json!(temperature));
    }
    if let Some(top_p) = body.get("top_p").and_then(Value::as_f64) {
        config.insert("topP".to_string(), json!(top_p));
    }
    if let Some(max_tokens) = body
        .get("max_tokens")
        .or_else(|| body.get("max_tokens_to_sample"))
        .and_then(Value::as_u64)
    {
        config.insert("maxOutputTokens".to_string(), json!(max_tokens));
    }

    if config.is_empty() {
        None
    } else {
        Some(Value::Object(config))
    }
}

/// The answer of Google, without the envelope the upstream adds.
pub fn unwrap_response(payload: &Value) -> Value {
    match payload.get("response") {
        Some(inner) if inner.is_object() => inner.clone(),
        _ => payload.clone(),
    }
}

/// The text of the answer.
pub fn answer_text(response: &Value) -> String {
    let response = unwrap_response(response);

    let Some(candidates) = response.get("candidates").and_then(Value::as_array) else {
        return String::new();
    };

    candidates
        .iter()
        .filter_map(|candidate| candidate.get("content"))
        .filter_map(|content| content.get("parts"))
        .filter_map(Value::as_array)
        .flatten()
        .filter_map(|part| part.get("text"))
        .filter_map(Value::as_str)
        .collect::<Vec<&str>>()
        .join("")
}

/// The reason the answer stopped.
pub fn finish_reason(response: &Value) -> Option<String> {
    let response = unwrap_response(response);
    let reason = response
        .get("candidates")
        .and_then(Value::as_array)
        .and_then(|candidates| candidates.first())
        .and_then(|candidate| candidate.get("finishReason"))
        .and_then(Value::as_str)?;

    match reason {
        "STOP" => Some("stop".to_string()),
        "MAX_TOKENS" => Some("length".to_string()),
        other => Some(other.to_lowercase()),
    }
}

/// The token counters of the answer.
pub fn usage(response: &Value) -> (u64, u64, u64) {
    let response = unwrap_response(response);
    let usage = response.get("usageMetadata");

    let prompt = usage
        .and_then(|usage| usage.get("promptTokenCount"))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let completion = usage
        .and_then(|usage| usage.get("candidatesTokenCount"))
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let total = usage
        .and_then(|usage| usage.get("totalTokenCount"))
        .and_then(Value::as_u64)
        .unwrap_or(prompt + completion);

    (prompt, completion, total)
}

/// The answer in the OpenAI format.
pub fn to_openai_answer(response: &Value, requested_model: &str, id: &str, created: i64) -> Value {
    let text = answer_text(response);
    let reason = finish_reason(response).unwrap_or_else(|| "stop".to_string());
    let (prompt, completion, total) = usage(response);

    json!({
        "id": format!("chatcmpl-{id}"),
        "object": "chat.completion",
        "created": created,
        "model": requested_model,
        "choices": [{
            "index": 0,
            "message": { "role": "assistant", "content": text },
            "finish_reason": reason,
        }],
        "usage": {
            "prompt_tokens": prompt,
            "completion_tokens": completion,
            "total_tokens": total,
        },
    })
}

/// The answer in the Anthropic format.
pub fn to_anthropic_answer(response: &Value, requested_model: &str, id: &str) -> Value {
    let text = answer_text(response);
    let (prompt, completion, _) = usage(response);

    let stop_reason = match finish_reason(response).as_deref() {
        Some("length") => "max_tokens",
        _ => "end_turn",
    };

    json!({
        "id": format!("msg_{id}"),
        "type": "message",
        "role": "assistant",
        "model": requested_model,
        "content": [{ "type": "text", "text": text }],
        "stop_reason": stop_reason,
        "usage": { "input_tokens": prompt, "output_tokens": completion },
    })
}

/// One chunk of a streamed OpenAI answer.
pub fn to_openai_chunk(
    id: &str,
    created: i64,
    model: &str,
    delta: Value,
    finish_reason: Value,
) -> Value {
    json!({
        "id": format!("chatcmpl-{id}"),
        "object": "chat.completion.chunk",
        "created": created,
        "model": model,
        "choices": [{
            "index": 0,
            "delta": delta,
            "finish_reason": finish_reason,
        }],
    })
}

/// The events of a streamed Anthropic answer.
pub fn to_anthropic_events(
    id: &str,
    model: &str,
    text: &str,
    prompt_tokens: u64,
    output_tokens: u64,
) -> Vec<String> {
    vec![
        anthropic_event(
            "message_start",
            json!({
                "type": "message_start",
                "message": {
                    "id": format!("msg_{id}"),
                    "type": "message",
                    "role": "assistant",
                    "model": model,
                    "content": [],
                    "stop_reason": Value::Null,
                    "usage": { "input_tokens": prompt_tokens, "output_tokens": 0 },
                },
            }),
        ),
        anthropic_event(
            "content_block_start",
            json!({
                "type": "content_block_start",
                "index": 0,
                "content_block": { "type": "text", "text": "" },
            }),
        ),
        anthropic_event(
            "content_block_delta",
            json!({
                "type": "content_block_delta",
                "index": 0,
                "delta": { "type": "text_delta", "text": text },
            }),
        ),
        anthropic_event(
            "content_block_stop",
            json!({ "type": "content_block_stop", "index": 0 }),
        ),
        anthropic_event(
            "message_delta",
            json!({
                "type": "message_delta",
                "delta": { "stop_reason": "end_turn" },
                "usage": { "output_tokens": output_tokens },
            }),
        ),
        anthropic_event("message_stop", json!({ "type": "message_stop" })),
    ]
}

/// One server sent event of the Anthropic protocol.
pub fn anthropic_event(name: &str, payload: Value) -> String {
    format!("event: {name}\ndata: {payload}\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_anthropic_request_becomes_an_internal_request() {
        let body = json!({
            "model": "claude-sonnet-4-6",
            "system": "You are helpful.",
            "max_tokens": 1024,
            "temperature": 0.5,
            "messages": [
                { "role": "user", "content": "Hello" },
                { "role": "assistant", "content": "Hi" },
                { "role": "user", "content": "How are you?" },
            ],
        });

        let request = internal_request(&body, "gemini-3.8-flash-high", Some("project-1"), "req-1");

        assert_eq!(request["model"], "gemini-3.8-flash-high");
        assert_eq!(request["project"], "project-1");
        assert_eq!(request["requestId"], "req-1");
        assert_eq!(request["requestType"], "agent");
        assert_eq!(request["userAgent"], USER_AGENT);

        let contents = request["request"]["contents"].as_array().unwrap();
        assert_eq!(contents.len(), 3);
        assert_eq!(contents[0]["role"], "user");
        assert_eq!(contents[0]["parts"][0]["text"], "Hello");
        assert_eq!(contents[1]["role"], "model");

        assert_eq!(
            request["request"]["systemInstruction"]["parts"][0]["text"],
            "You are helpful."
        );
        assert_eq!(request["request"]["generationConfig"]["maxOutputTokens"], 1024);
        assert_eq!(request["request"]["generationConfig"]["temperature"], 0.5);
    }

    #[test]
    fn an_openai_request_becomes_an_internal_request() {
        let body = json!({
            "model": "gpt-5-1",
            "messages": [
                { "role": "system", "content": "Be brief." },
                { "role": "user", "content": [{ "type": "text", "text": "Hello" }] },
            ],
        });

        let request = internal_request(&body, "gemini-3.8-flash-high", None, "req-2");

        assert!(request.get("project").is_none());
        assert_eq!(
            request["request"]["systemInstruction"]["parts"][0]["text"],
            "Be brief."
        );
        let contents = request["request"]["contents"].as_array().unwrap();
        assert_eq!(contents.len(), 1);
        assert_eq!(contents[0]["parts"][0]["text"], "Hello");
    }

    #[test]
    fn the_answer_becomes_an_openai_answer() {
        let response = json!({
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
        });

        let answer = to_openai_answer(&response, "gpt-5-1", "abc", 1700000000);

        assert_eq!(answer["object"], "chat.completion");
        assert_eq!(answer["model"], "gpt-5-1");
        assert_eq!(answer["choices"][0]["message"]["content"], "Hello there");
        assert_eq!(answer["choices"][0]["finish_reason"], "stop");
        assert_eq!(answer["usage"]["prompt_tokens"], 12);
        assert_eq!(answer["usage"]["completion_tokens"], 34);
        assert_eq!(answer["usage"]["total_tokens"], 46);
    }

    #[test]
    fn the_answer_becomes_an_anthropic_answer() {
        let response = json!({
            "candidates": [{
                "content": { "parts": [{ "text": "Hi" }] },
                "finishReason": "MAX_TOKENS",
            }],
            "usageMetadata": { "promptTokenCount": 3, "candidatesTokenCount": 5 },
        });

        let answer = to_anthropic_answer(&response, "claude-sonnet-4-6", "abc");

        assert_eq!(answer["type"], "message");
        assert_eq!(answer["role"], "assistant");
        assert_eq!(answer["content"][0]["text"], "Hi");
        assert_eq!(answer["stop_reason"], "max_tokens");
        assert_eq!(answer["usage"]["input_tokens"], 3);
        assert_eq!(answer["usage"]["output_tokens"], 5);
    }

    #[test]
    fn an_answer_without_text_is_empty() {
        let response = json!({ "candidates": [] });
        assert_eq!(answer_text(&response), "");
        assert_eq!(finish_reason(&response), None);
    }

    #[test]
    fn the_anthropic_events_follow_the_protocol() {
        let events = to_anthropic_events("abc", "claude-sonnet-4-6", "Hi", 3, 5);

        assert_eq!(events.len(), 6);
        assert!(events[0].starts_with("event: message_start"));
        assert!(events[1].contains("content_block_start"));
        assert!(events[2].contains("\"text\":\"Hi\""));
        assert!(events[3].contains("content_block_stop"));
        assert!(events[4].contains("message_delta"));
        assert!(events[5].contains("message_stop"));
    }

    #[test]
    fn the_key_is_read_out_of_the_three_headers() {
        let mut headers = vec![
            ("authorization".to_string(), "Bearer sk-1234".to_string()),
            ("x-api-key".to_string(), "sk-5678".to_string()),
            ("x-goog-api-key".to_string(), "sk-9012".to_string()),
        ];
        headers.push(("authorization".to_string(), "Bearer sk-1234".to_string()));

        assert_eq!(extract_key(&headers), Some("sk-1234".to_string()));
    }
}

/// The key of a request.
///
/// The coding tools send it in different headers: the OpenAI tools use
/// `Authorization: Bearer`, the Anthropic tools `x-api-key` and the Gemini
/// tools `x-goog-api-key`.
pub fn extract_key(headers: &[(String, String)]) -> Option<String> {
    for (name, value) in headers {
        match name.as_str() {
            "authorization" => {
                let trimmed = value.trim();
                if let Some(token) = trimmed.strip_prefix("Bearer ") {
                    return Some(token.trim().to_string());
                }
                if let Some(token) = trimmed.strip_prefix("bearer ") {
                    return Some(token.trim().to_string());
                }
            }
            "x-api-key" | "x-goog-api-key" => {
                let trimmed = value.trim();
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
            _ => {}
        }
    }

    None
}
