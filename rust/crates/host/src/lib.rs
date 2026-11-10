//! The transport layer of the Antigravity Manager desktop host.
//!
//! The crate carries the named pipe listener, the framing of the contract, the
//! JSON-RPC dispatch and the cloud side of the host: the OAuth session of a
//! Google account and the local API proxy. The binary in `main.rs` wires the
//! pipe to the profile on disk.

pub mod cloud;
pub mod frame;
pub mod oauth;
pub mod pipe;
pub mod server;
pub mod upstream;
