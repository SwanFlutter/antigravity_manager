//! The private named pipe listener.
//!
//! The pipe is the only channel between the Flutter UI and the Rust core. It
//! stays on the machine, is not reachable from the network, and carries the
//! versioned JSON-RPC contract.
//!
//! A pipe instance cannot be reused after its client disconnected, so every
//! instance replaces itself with a fresh one as soon as it is done. The pool
//! of instances keeps the pipe reachable for the next client and keeps
//! `ERROR_PIPE_BUSY` away.

#[cfg(windows)]
mod windows {
    use std::io;
    use std::sync::Arc;

    use antigravity_contract::Request;
    use tokio::net::windows::named_pipe::{NamedPipeServer, PipeMode, ServerOptions};

    use crate::frame::{read_frame, write_frame};
    use crate::server::{dispatch, Dispatcher};

    /// Tokio creates the pipe in byte mode with the wait mode enabled, which is
    /// exactly what the framing of the contract expects.
    const PIPE_MAX_INSTANCES: usize = 254;

    /// How many pipe instances are kept alive at the same time.
    ///
    /// A client that opens a connection while every instance is busy gets
    /// `ERROR_PIPE_BUSY`, so the host keeps a few spare instances around.
    const PIPE_INSTANCES: usize = 8;

    /// Creates one instance of the pipe.
    fn create_instance(full_name: &str, first: bool) -> io::Result<NamedPipeServer> {
        ServerOptions::new()
            .first_pipe_instance(first)
            .access_inbound(true)
            .access_outbound(true)
            .pipe_mode(PipeMode::Byte)
            .max_instances(PIPE_MAX_INSTANCES)
            .create(full_name)
    }

    /// Serves the contract on the given pipe until the process stops.
    pub async fn serve(dispatcher: Arc<Dispatcher>, pipe_name: &str) -> io::Result<()> {
        let full_name = format!(r"\\.\pipe\{pipe_name}");

        let mut servers = Vec::with_capacity(PIPE_INSTANCES);
        for index in 0..PIPE_INSTANCES {
            let server = create_instance(&full_name, index == 0)?;

            let dispatcher = dispatcher.clone();
            let full_name = full_name.clone();
            servers.push(tokio::spawn(async move {
                serve_instance(dispatcher, full_name, server).await;
            }));
        }

        for server in servers {
            let _ = server.await;
        }

        Ok(())
    }

    /// Accepts clients on one instance and replaces the instance after every
    /// client.
    async fn serve_instance(
        dispatcher: Arc<Dispatcher>,
        full_name: String,
        mut server: NamedPipeServer,
    ) {
        loop {
            if let Err(error) = server.connect().await {
                eprintln!("[host] pipe connect failed: {error}");
                return;
            }

            serve_client(&dispatcher, &mut server).await;

            // The instance cannot take another client, so it is replaced. The
            // replacement is created before the old one is dropped, so the pipe
            // never disappears for a moment.
            match create_instance(&full_name, false) {
                Ok(next) => server = next,
                Err(error) => {
                    eprintln!("[host] cannot replace the pipe instance: {error}");
                    return;
                }
            }
        }
    }

    /// Answers the requests of one client until it disconnects.
    async fn serve_client(dispatcher: &Dispatcher, server: &mut NamedPipeServer) {
        loop {
            let payload = match read_frame(server).await {
                Ok(Some(payload)) => payload,
                Ok(None) => return,
                Err(error) => {
                    eprintln!("[host] pipe read failed: {error}");
                    return;
                }
            };

            let response = match serde_json::from_slice::<Request>(&payload) {
                Ok(request) => {
                    eprintln!("[host] {}", request.method);
                    let response = dispatch(dispatcher, request).await;
                    serde_json::to_vec(&response).unwrap_or_else(|_| b"{}".to_vec())
                }
                Err(error) => {
                    let response = antigravity_contract::Response::err(
                        None,
                        antigravity_contract::RpcError::new(
                            antigravity_contract::error_codes::INVALID_REQUEST,
                            format!("invalid request: {error}"),
                        ),
                    );
                    serde_json::to_vec(&response).unwrap_or_else(|_| b"{}".to_vec())
                }
            };

            if let Err(error) = write_frame(server, &response).await {
                eprintln!("[host] pipe write failed: {error}");
                return;
            }
        }
    }
}

#[cfg(windows)]
pub use windows::serve;

#[cfg(not(windows))]
pub async fn serve(
    _dispatcher: std::sync::Arc<crate::server::Dispatcher>,
    _pipe_name: &str,
) -> std::io::Result<()> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "the desktop host is only available on Windows",
    ))
}
