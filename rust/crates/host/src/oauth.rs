//! The loopback listener that receives the OAuth callback.
//!
//! The listener binds to `127.0.0.1` on a free port and waits for a valid
//! callback. Nothing is exposed to the network.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::oneshot;

/// The answer of the browser to the authorization request.
#[derive(Debug, Clone, PartialEq)]
pub struct OAuthCallback {
    pub code: Option<String>,
    pub state: Option<String>,
    pub error: Option<String>,
}

/// The running OAuth sessions of the host.
#[derive(Default)]
pub struct SessionStore {
    sessions: Mutex<HashMap<String, Session>>,
}

#[derive(PartialEq)]
enum SessionState {
    Pending,
    Exchanging,
    Completed,
    Failed,
    Expired,
}

struct Session {
    redirect_uri: String,
    expires_at: i64,
    cancel: Option<oneshot::Sender<()>>,
    state: SessionState,
    email: Option<String>,
    error: Option<String>,
}

impl Session {
    fn cancel_listener(&mut self) {
        if let Some(cancel) = self.cancel.take() {
            let _ = cancel.send(());
        }
    }

    fn expire(&mut self, now: i64) {
        if self.state == SessionState::Pending && self.expires_at <= now {
            self.state = SessionState::Expired;
            self.cancel_listener();
        }
    }
}

impl SessionStore {
    pub fn insert(
        &self,
        id: String,
        redirect_uri: String,
        expires_at: i64,
        cancel: oneshot::Sender<()>,
    ) -> bool {
        let mut sessions = self.sessions.lock().expect("session store");
        let std::collections::hash_map::Entry::Vacant(entry) = sessions.entry(id) else {
            return false;
        };
        entry.insert(Session {
            redirect_uri,
            expires_at,
            cancel: Some(cancel),
            state: SessionState::Pending,
            email: None,
            error: None,
        });
        true
    }

    pub fn status(&self, id: &str) -> Option<(String, Option<String>, Option<String>)> {
        let mut sessions = self.sessions.lock().expect("session store");
        let session = sessions.get_mut(id)?;
        session.expire(crate::cloud::now_millis());
        let status = match session.state {
            SessionState::Pending | SessionState::Exchanging => "pending",
            SessionState::Completed => "completed",
            SessionState::Failed => "failed",
            SessionState::Expired => "expired",
        };
        Some((status.to_string(), session.email.clone(), session.error.clone()))
    }

    // Claim before spawning any exchange so manual and browser submissions cannot race.
    pub fn claim(&self, id: &str, now: i64) -> Option<String> {
        let mut sessions = self.sessions.lock().expect("session store");
        let session = sessions.get_mut(id)?;
        session.expire(now);
        if session.state != SessionState::Pending {
            return None;
        }
        session.state = SessionState::Exchanging;
        session.cancel_listener();
        Some(session.redirect_uri.clone())
    }

    pub fn finish(&self, id: &str, result: Result<String, String>) {
        let mut sessions = self.sessions.lock().expect("session store");
        if let Some(session) = sessions.get_mut(id) {
            if session.state != SessionState::Exchanging {
                return;
            }
            match result {
                Ok(email) => {
                    session.state = SessionState::Completed;
                    session.email = Some(email);
                }
                Err(error) => {
                    session.state = SessionState::Failed;
                    session.error = Some(error);
                }
            }
        }
    }

    pub fn expire(&self, id: &str, now: i64) {
        let mut sessions = self.sessions.lock().expect("session store");
        if let Some(session) = sessions.get_mut(id) {
            session.expire(now);
        }
    }
}

/// Dropping the receiver also closes the listener, including any idle connection.
pub async fn start_callback_listener(
    state: String,
) -> std::io::Result<(String, oneshot::Receiver<OAuthCallback>)> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();
    let redirect_uri = format!("http://127.0.0.1:{port}/oauth-callback");
    let (mut sender, receiver) = oneshot::channel();

    tokio::spawn(async move {
        tokio::select! {
            biased;
            _ = sender.closed() => {}
            result = accept_callback(listener, state) => {
                match result {
                    Ok(callback) => { let _ = sender.send(callback); }
                    Err(error) => eprintln!("[host] the OAuth listener stopped: {error}"),
                }
            }
        }
    });

    Ok((redirect_uri, receiver))
}

async fn accept_callback(
    listener: TcpListener,
    expected_state: String,
) -> std::io::Result<OAuthCallback> {
    loop {
        let (mut stream, _) = listener.accept().await?;
        let request =
            match tokio::time::timeout(Duration::from_secs(5), read_request(&mut stream)).await {
                Ok(Ok(request)) => request,
                _ => continue,
            };
        let callback = validate_request(&request, &expected_state);
        let (status, heading, message) = match &callback {
            Some(OAuthCallback { error: Some(error), .. }) if error == "access_denied" => (
                "200 OK", "Authorization cancelled",
                "Google sign-in was cancelled. Return to Antigravity Manager and start Add account again to retry.",
            ),
            Some(OAuthCallback { error: Some(_), .. }) => (
                "200 OK", "Authorization failed",
                "Return to Antigravity Manager to check the error and try again.",
            ),
            Some(_) => (
                "200 OK", "Authorization received",
                "Return to Antigravity Manager to check the account connection status. You can close this tab.",
            ),
            None => (
                "400 Bad Request", "Authorization not accepted",
                "This callback is invalid or does not match. Continue sign-in in the original Google tab.",
            ),
        };
        let body = format!(
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>Antigravity Manager</title></head>\
             <body style=\"font-family:system-ui;padding:40px\"><h2>{heading}</h2><p>{message}</p></body></html>"
        );
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{body}",
            body.len(),
        );
        let _ = tokio::time::timeout(Duration::from_secs(5), stream.write_all(response.as_bytes())).await;
        if let Some(callback) = callback {
            return Ok(callback);
        }
    }
}

async fn read_request(stream: &mut TcpStream) -> std::io::Result<String> {
    let mut buffer = [0u8; 8192];
    let mut used = 0;
    while used < buffer.len() {
        let read = stream.read(&mut buffer[used..]).await?;
        if read == 0 {
            break;
        }
        used += read;
        if buffer[..used].windows(4).any(|part| part == b"\r\n\r\n") {
            return String::from_utf8(buffer[..used].to_vec())
                .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error));
        }
    }
    Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "invalid callback headers"))
}

fn validate_request(request: &str, expected_state: &str) -> Option<OAuthCallback> {
    let mut parts = request.lines().next()?.split_whitespace();
    if parts.next()? != "GET" {
        return None;
    }
    let (path, query) = parts.next()?.split_once('?')?;
    if path != "/oauth-callback"
        || !matches!(parts.next()?, "HTTP/1.0" | "HTTP/1.1")
        || parts.next().is_some()
    {
        return None;
    }
    let callback = parse_callback(query)?;
    if callback.state.as_deref() != Some(expected_state) || expected_state.is_empty() {
        return None;
    }
    match (&callback.code, &callback.error) {
        (Some(code), None) if !code.trim().is_empty() => Some(callback),
        (None, Some(error)) if !error.trim().is_empty() => Some(callback),
        _ => None,
    }
}

fn parse_callback(query: &str) -> Option<OAuthCallback> {
    let mut callback = OAuthCallback { code: None, state: None, error: None };
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        let key = percent_decode(key)?;
        let value = percent_decode(value)?;
        let slot = match key.as_str() {
            "code" => &mut callback.code,
            "state" => &mut callback.state,
            "error" => &mut callback.error,
            _ => continue,
        };
        if slot.replace(value).is_some() {
            return None;
        }
    }
    Some(callback)
}

fn percent_decode(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' => {
                let hex = std::str::from_utf8(bytes.get(index + 1..index + 3)?).ok()?;
                out.push(u8::from_str_radix(hex, 16).ok()?);
                index += 3;
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    let decoded = String::from_utf8(out).ok()?;
    if decoded.chars().any(char::is_control) {
        return None;
    }
    Some(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn insert(store: &SessionStore, expires_at: i64) -> oneshot::Receiver<()> {
        let (cancel, cancelled) = oneshot::channel();
        assert!(store.insert("session".into(), "http://127.0.0.1:1234/oauth-callback".into(), expires_at, cancel));
        cancelled
    }

    #[test]
    fn only_one_consumer_can_claim_a_session() {
        let store = Arc::new(SessionStore::default());
        let mut cancelled = insert(&store, i64::MAX);
        let barrier = Arc::new(std::sync::Barrier::new(8));
        let threads: Vec<_> = (0..8).map(|_| {
            let store = store.clone();
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                barrier.wait();
                store.claim("session", 1)
            })
        }).collect();
        let claims: Vec<_> = threads.into_iter().filter_map(|thread| thread.join().unwrap()).collect();
        assert_eq!(claims, ["http://127.0.0.1:1234/oauth-callback"]);
        assert_eq!(cancelled.try_recv(), Ok(()));
        assert_eq!(store.status("session").unwrap().0, "pending");
    }

    #[test]
    fn completed_and_failed_sessions_cannot_be_overwritten_or_reused() {
        for result in [Ok("test@example.invalid".to_string()), Err("storage failed".to_string())] {
            let store = SessionStore::default();
            let _cancelled = insert(&store, i64::MAX);
            store.finish("session", result.clone());
            assert_eq!(store.status("session").unwrap().0, "pending");
            assert!(store.claim("session", 0).is_some());
            store.expire("session", i64::MAX);
            assert_eq!(store.status("session").unwrap().0, "pending");
            store.finish("session", result.clone());
            let expected = store.status("session").unwrap();
            assert_eq!(expected, match result {
                Ok(email) => ("completed".into(), Some(email), None),
                Err(error) => ("failed".into(), None, Some(error)),
            });
            store.expire("session", i64::MAX);
            store.finish("session", Err("late callback".into()));
            store.finish("session", Ok("late@example.invalid".into()));
            assert!(store.claim("session", 0).is_none());
            let (cancel, _) = oneshot::channel();
            assert!(!store.insert("session".into(), "different".into(), i64::MAX, cancel));
            assert_eq!(store.status("session").unwrap(), expected);
        }
    }

    #[test]
    fn expiration_cancels_the_listener_and_is_terminal() {
        let store = SessionStore::default();
        let mut cancelled = insert(&store, i64::MAX);
        store.expire("session", i64::MAX - 1);
        assert_eq!(cancelled.try_recv(), Err(oneshot::error::TryRecvError::Empty));
        store.expire("session", i64::MAX);
        assert_eq!(cancelled.try_recv(), Ok(()));
        assert!(store.claim("session", 0).is_none());
        store.finish("session", Ok("late@example.invalid".into()));
        store.finish("session", Err("late failure".into()));
        assert_eq!(store.status("session").unwrap(), ("expired".into(), None, None));
    }

    #[test]
    fn overdue_sessions_expire_even_before_the_timer_runs() {
        for claim_first in [true, false] {
            let store = SessionStore::default();
            let mut cancelled = insert(&store, 0);
            if claim_first {
                assert!(store.claim("session", 0).is_none());
            }
            assert_eq!(store.status("session").unwrap().0, "expired");
            assert_eq!(cancelled.try_recv(), Ok(()));
        }
    }

    #[test]
    fn callback_validation_rejects_malformed_or_ambiguous_parameters() {
        for target in [
            "/other?state=expected&code=code",
            "/oauth-callback?state=wrong&code=code",
            "/oauth-callback?code=code",
            "/oauth-callback?state=expected",
            "/oauth-callback?state=expected&code=",
            "/oauth-callback?state=expected&code=++",
            "/oauth-callback?state=expected&error=",
            "/oauth-callback?state=expected&code=code&error=access_denied",
            "/oauth-callback?state=wrong&state=expected&code=code",
            "/oauth-callback?state=expected&code=first&%63ode=second",
            "/oauth-callback?state=expected&code=%ZZ",
            "/oauth-callback?state=expected&code=%FF",
            "/oauth-callback?state=expected&code=%00",
            "/oauth-callback?state=expected&code=%",
        ] {
            let request = format!("GET {target} HTTP/1.1\r\n\r\n");
            assert!(validate_request(&request, "expected").is_none(), "{target}");
        }
        assert!(validate_request("POST /oauth-callback?state=expected&code=code HTTP/1.1\r\n\r\n", "expected").is_none());
    }

    #[tokio::test]
    async fn invalid_callbacks_do_not_consume_the_listener() {
        let (redirect, mut receiver) = start_callback_listener("expected".into()).await.unwrap();
        let client = reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(3)).build().unwrap();
        for url in [
            format!("{}?state=expected&code=ignored", redirect.replace("/oauth-callback", "/favicon.ico")),
            format!("{redirect}?state=wrong&code=ignored"),
            format!("{redirect}?state=expected&code="),
        ] {
            let response = client.get(url).send().await.unwrap();
            assert_eq!(response.status(), 400);
            assert!(response.text().await.unwrap().contains("Authorization not accepted"));
            assert_eq!(receiver.try_recv(), Err(oneshot::error::TryRecvError::Empty));
        }
        let response = client.get(format!("{redirect}?state=expected&code=4%2Ftest%2Bcode%26value"))
            .send().await.unwrap();
        assert_eq!(response.status(), 200);
        let body = response.text().await.unwrap();
        assert!(body.contains("Authorization received"));
        assert!(!body.contains("Account connected"));
        let callback = tokio::time::timeout(Duration::from_secs(3), receiver).await.unwrap().unwrap();
        assert_eq!(callback.code.as_deref(), Some("4/test+code&value"));
        assert!(callback.error.is_none());
    }

    #[tokio::test]
    async fn denial_has_a_readable_page_and_a_callback_error() {
        let (redirect, receiver) = start_callback_listener("expected".into()).await.unwrap();
        let client = reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(3)).build().unwrap();
        let response = client.get(format!("{redirect}?state=expected&error=access_denied"))
            .send().await.unwrap();
        assert!(response.text().await.unwrap().contains("Authorization cancelled"));
        let callback = tokio::time::timeout(Duration::from_secs(3), receiver).await.unwrap().unwrap();
        assert_eq!(callback.error.as_deref(), Some("access_denied"));
        assert!(callback.code.is_none());
    }

    #[tokio::test]
    async fn dropping_the_receiver_closes_an_idle_connection() {
        let (redirect, receiver) = start_callback_listener("expected".into()).await.unwrap();
        let address = redirect.trim_start_matches("http://").trim_end_matches("/oauth-callback");
        let mut stream = TcpStream::connect(address).await.unwrap();
        drop(receiver);
        let mut byte = [0];
        let read = tokio::time::timeout(Duration::from_secs(3), stream.read(&mut byte)).await.unwrap();
        assert!(matches!(read, Ok(0) | Err(_)));
        assert!(TcpStream::connect(address).await.is_err());
    }

    #[tokio::test]
    async fn disconnected_requests_do_not_stop_the_listener_and_headers_can_be_fragmented() {
        let (redirect, receiver) = start_callback_listener("expected".into()).await.unwrap();
        let address = redirect.trim_start_matches("http://").trim_end_matches("/oauth-callback");
        let mut disconnected = TcpStream::connect(address).await.unwrap();
        disconnected.write_all(b"GET /oauth").await.unwrap();
        drop(disconnected);
        let mut stream = TcpStream::connect(address).await.unwrap();
        stream.write_all(b"GET /oauth-callback?state=expected&code=test HTTP/1.1\r\nHost: localhost\r\n").await.unwrap();
        tokio::task::yield_now().await;
        stream.write_all(b"\r\n").await.unwrap();
        let callback = tokio::time::timeout(Duration::from_secs(3), receiver).await.unwrap().unwrap();
        assert_eq!(callback.code.as_deref(), Some("test"));
    }
}
