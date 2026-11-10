//! The private Windows named pipe transport.
//!
//! The pipe carries length prefixed JSON-RPC frames: a four byte little
//! endian length followed by the UTF-8 payload. Byte mode is used on purpose,
//! so the framing does not depend on the message mode of the pipe.

use std::io;

use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// The maximum size of a single frame, 8 MiB.
pub const MAX_FRAME_BYTES: usize = 8 * 1024 * 1024;

/// Writes one length prefixed frame.
pub async fn write_frame<W>(writer: &mut W, payload: &[u8]) -> io::Result<()>
where
    W: AsyncWriteExt + Unpin,
{
    let length = (payload.len() as u32).to_le_bytes();
    writer.write_all(&length).await?;
    writer.write_all(payload).await?;
    writer.flush().await
}

/// Reads one length prefixed frame.
///
/// Returns `Ok(None)` when the peer closed the connection cleanly.
pub async fn read_frame<R>(reader: &mut R) -> io::Result<Option<Vec<u8>>>
where
    R: AsyncReadExt + Unpin,
{
    let mut length_bytes = [0u8; 4];
    match reader.read_exact(&mut length_bytes).await {
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(error) => return Err(error),
    }

    let length = u32::from_le_bytes(length_bytes) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("frame of {length} bytes exceeds the limit"),
        ));
    }

    let mut payload = vec![0u8; length];
    reader.read_exact(&mut payload).await?;
    Ok(Some(payload))
}
