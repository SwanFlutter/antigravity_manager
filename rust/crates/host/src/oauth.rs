//! The loopback listener that receives the OAuth callback.
//!
//! The listener binds to `127.0.0.1` on a free port, waits for one request
//! and answers it with a small page. Nothing is exposed to the network.

use std::collections::HashMap;
use std::sync::Mutex;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
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

/// One OAuth session.
pub struct Session {
    pub redirect_uri: String,
    pub expires_at: i64,
    pub sender: Option<oneshot::Sender<OAuthCallback>>,
    pub status: String,
    pub email: Option<String>,
    pub error: Option<String>,
}

impl SessionStore {
    /// Stores a new session and returns its id.
    pub fn insert(
        &self,
        id: String,
        redirect_uri: String,
        expires_at: i64,
        sender: oneshot::Sender<OAuthCallback>,
    ) {
        let mut sessions = self.sessions.lock().expect("session store");
        sessions.insert(
            id,
            Session {
                redirect_uri,
                expires_at,
                sender: Some(sender),
                status: "pending".to_string(),
                email: None,
                error: None,
            },
        );
    }

    /// Reads the state of a session.
    pub fn status(&self, id: &str) -> Option<(String, Option<String>, Option<String>)> {
        let sessions = self.sessions.lock().expect("session store");
        let session = sessions.get(id)?;
        Some((
            session.status.clone(),
            session.email.clone(),
            session.error.clone(),
        ))
    }

    /// Reads the redirect URI of a session.
    pub fn redirect_uri(&self, id: &str) -> Option<String> {
        let sessions = self.sessions.lock().expect("session store");
        sessions.get(id).map(|session| session.redirect_uri.clone())
    }

    /// Marks a session as finished.
    pub fn finish(&self, id: &str, status: &str, email: Option<String>, error: Option<String>) {
        let mut sessions = self.sessions.lock().expect("session store");
        if let Some(session) = sessions.get_mut(id) {
            session.status = status.to_string();
            session.email = email;
            session.error = error;
        }
    }

    /// Takes the sender of a session, so only the first answer is used.
    pub fn take_sender(&self, id: &str) -> Option<oneshot::Sender<OAuthCallback>> {
        let mut sessions = self.sessions.lock().expect("session store");
        sessions.get_mut(id)?.sender.take()
    }

    /// Removes the finished sessions.
    pub fn prune(&self, now_millis: i64) {
        let mut sessions = self.sessions.lock().expect("session store");
        sessions.retain(|_, session| session.expires_at > now_millis);
    }
}

/// Starts the callback listener.
///
/// It returns the redirect URI the browser has to call and the receiver of the
/// answer of the browser.
pub async fn start_callback_listener(
    state: String,
) -> std::io::Result<(String, oneshot::Receiver<OAuthCallback>)> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();
    let redirect_uri = format!("http://127.0.0.1:{port}/oauth-callback");

    let (sender, receiver) = oneshot::channel();

    tokio::spawn(async move {
        if let Err(error) = accept_callback(listener, state, sender).await {
            eprintln!("[host] the OAuth listener stopped: {error}");
        }
    });

    Ok((redirect_uri, receiver))
}

/// Waits for one request and answers it.
async fn accept_callback(
    listener: TcpListener,
    expected_state: String,
    sender: oneshot::Sender<OAuthCallback>,
) -> std::io::Result<()> {
    loop {
        let (mut stream, _) = listener.accept().await?;
        let mut buffer = vec![0u8; 8192];
        let read = stream.read(&mut buffer).await?;
        let request = String::from_utf8_lossy(&buffer[..read]).to_string();

        let Some(query) = request.split_whitespace().nth(1) else {
            continue;
        };
        let query = query.split('?').nth(1).unwrap_or("");

        let callback = parse_callback(query);
        let matches = callback.state.as_deref() == Some(expected_state.as_str());

        let body = if matches && callback.error.is_none() {
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>Antigravity Manager</title></head>\
             <body style=\"font-family:system-ui;padding:40px\"><h2>Account connected</h2>\
             <p>You can close this tab and go back to Antigravity Manager.</p></body></html>"
        } else {
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>Antigravity Manager</title></head>\
             <body style=\"font-family:system-ui;padding:40px\"><h2>The request did not match</h2>\
             <p>Close this tab and start the connection again.</p></body></html>"
        };

        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        );
        let _ = stream.write_all(response.as_bytes()).await;
        let _ = stream.flush().await;

        if matches {
            let _ = sender.send(callback);
            return Ok(());
        }
    }
}

/// Reads the answer of the browser out of the query string.
fn parse_callback(query: &str) -> OAuthCallback {
    let mut code = None;
    let mut state = None;
    let mut error = None;

    for pair in query.split('&') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        let value = percent_decode(value);
        match key {
            "code" => code = Some(value),
            "state" => state = Some(value),
            "error" => error = Some(value),
            _ => {}
        }
    }

    OAuthCallback {
        code,
        state,
        error,
    }
}

/// Decodes the percent encoding of a query value.
fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;

    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(byte) => {
                        out.push(byte);
                        index += 3;
                    }
                    Err(_) => {
                        out.push(bytes[index]);
                        index += 1;
                    }
                }
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }

    String::from_utf8_lossy(&out).to_string()
}
