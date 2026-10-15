use std::sync::Arc;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::{mpsc, watch, Mutex};
use tokio::task::JoinHandle;

use crate::presence::{decode_header, encode_frame, encode_raw, FrameError, OP_CLOSE, OP_FRAME, OP_HANDSHAKE, OP_PING, OP_PONG};
#[cfg(windows)]
use crate::presence::PIPE_PREFIX;

pub const IO_TIMEOUT: Duration = Duration::from_secs(5);
pub const PIPE_SLOTS: u32 = 10;
#[cfg(windows)]
const PIPE_BUSY_RETRY: Duration = Duration::from_millis(50);
#[cfg(windows)]
const PIPE_BUSY_ATTEMPTS: u32 = 6;
#[cfg(windows)]
const ERROR_PIPE_BUSY: i32 = 231;

type Writer = Box<dyn AsyncWrite + Send + Unpin>;

#[derive(Debug, thiserror::Error)]
pub enum IpcError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("timed out")]
    Timeout,
    #[error("connection closed: {0}")]
    Closed(String),
    #[error("handshake refused: {0}")]
    Refused(String),
    #[error("bad frame: {0}")]
    BadFrame(String),
    #[error("discord is not running")]
    NotRunning,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SetOutcome {
    Accepted,
    Rejected { code: i64, message: String },
}

enum Incoming {
    Frame(Value),
    Closed(String),
}

pub struct IpcClient {
    writer: Arc<Mutex<Writer>>,
    frames: mpsc::UnboundedReceiver<Incoming>,
    closed: watch::Receiver<Option<String>>,
    reader: JoinHandle<()>,
    app_id: String,
    nonce: u64,
    io_timeout: Duration,
}

impl Drop for IpcClient {
    fn drop(&mut self) {
        self.reader.abort();
    }
}

async fn read_frame<R: AsyncRead + Unpin>(reader: &mut R) -> Result<(u32, Vec<u8>), IpcError> {
    let mut header = [0u8; 8];
    reader.read_exact(&mut header).await?;
    let (opcode, length) = decode_header(header).map_err(|FrameError::TooLarge(size)| IpcError::BadFrame(format!("{size} bytes")))?;
    let mut body = vec![0u8; length];
    reader.read_exact(&mut body).await?;
    Ok((opcode, body))
}

async fn write_bytes(writer: &Mutex<Writer>, bytes: &[u8], limit: Duration) -> Result<(), IpcError> {
    let mut guard = writer.lock().await;
    let result = tokio::time::timeout(limit, async {
        guard.write_all(bytes).await?;
        guard.flush().await
    })
    .await;
    match result {
        Ok(outcome) => Ok(outcome?),
        Err(_) => Err(IpcError::Timeout),
    }
}

async fn read_loop<R: AsyncRead + Unpin>(
    mut reader: R,
    writer: Arc<Mutex<Writer>>,
    frames: mpsc::UnboundedSender<Incoming>,
    closed: watch::Sender<Option<String>>,
    io_timeout: Duration,
) {
    let reason = loop {
        let (opcode, body) = match read_frame(&mut reader).await {
            Ok(frame) => frame,
            Err(IpcError::Io(error)) => break format!("read failed: {error}"),
            Err(other) => break other.to_string(),
        };
        match opcode {
            OP_PING => {
                if let Err(error) = write_bytes(&writer, &encode_raw(OP_PONG, &body), io_timeout).await {
                    break format!("pong failed: {error}");
                }
            }
            OP_PONG => {}
            OP_CLOSE => break format!("peer closed: {}", String::from_utf8_lossy(&body).chars().take(200).collect::<String>()),
            _ => match serde_json::from_slice::<Value>(&body) {
                Ok(value) => {
                    let _ = frames.send(Incoming::Frame(value));
                }
                Err(error) => break format!("bad json: {error}"),
            },
        }
    };
    let _ = frames.send(Incoming::Closed(reason.clone()));
    let _ = closed.send(Some(reason));
}

fn handshake_reply(reply: &Value) -> Option<Result<(), IpcError>> {
    match reply.get("evt").and_then(Value::as_str) {
        Some("READY") => Some(Ok(())),
        Some("ERROR") => Some(Err(IpcError::Refused(reply["data"]["message"].as_str().unwrap_or("error").to_string()))),
        _ => None,
    }
}

fn outcome(reply: &Value) -> SetOutcome {
    if reply.get("evt").and_then(Value::as_str) != Some("ERROR") {
        return SetOutcome::Accepted;
    }
    SetOutcome::Rejected {
        code: reply["data"]["code"].as_i64().unwrap_or(0),
        message: reply["data"]["message"].as_str().unwrap_or("").to_string(),
    }
}

impl IpcClient {
    pub async fn handshake<T>(transport: T, app_id: &str, io_timeout: Duration) -> Result<IpcClient, IpcError>
    where
        T: AsyncRead + AsyncWrite + Send + Unpin + 'static,
    {
        let (read_half, write_half) = tokio::io::split(transport);
        let writer: Arc<Mutex<Writer>> = Arc::new(Mutex::new(Box::new(write_half)));
        let (frames_tx, frames) = mpsc::unbounded_channel();
        let (closed_tx, closed) = watch::channel(None);
        let reader = tokio::spawn(read_loop(read_half, writer.clone(), frames_tx, closed_tx, io_timeout));
        let mut client = IpcClient { writer, frames, closed, reader, app_id: app_id.to_string(), nonce: 0, io_timeout };
        client.write(OP_HANDSHAKE, &json!({ "v": 1, "client_id": app_id })).await?;
        client.receive(handshake_reply).await?;
        Ok(client)
    }

    pub fn app_id(&self) -> &str {
        &self.app_id
    }

    pub fn is_closed(&self) -> bool {
        self.closed.borrow().is_some() || self.reader.is_finished()
    }

    pub async fn closed(&self) -> String {
        let mut watcher = self.closed.clone();
        let reason = watcher.wait_for(|reason| reason.is_some()).await.ok().and_then(|reason| reason.clone());
        reason.unwrap_or_else(|| "reader stopped".to_string())
    }

    async fn write(&self, opcode: u32, payload: &Value) -> Result<(), IpcError> {
        write_bytes(&self.writer, &encode_frame(opcode, payload), self.io_timeout).await
    }

    async fn receive<T>(&mut self, mut accept: impl FnMut(&Value) -> Option<Result<T, IpcError>>) -> Result<T, IpcError> {
        let wait = async {
            loop {
                match self.frames.recv().await {
                    Some(Incoming::Frame(value)) => {
                        if let Some(found) = accept(&value) {
                            return found;
                        }
                    }
                    Some(Incoming::Closed(reason)) => return Err(IpcError::Closed(reason)),
                    None => return Err(IpcError::Closed("reader stopped".to_string())),
                }
            }
        };
        tokio::time::timeout(self.io_timeout, wait).await.unwrap_or(Err(IpcError::Timeout))
    }

    pub async fn set_activity(&mut self, activity: Option<&Value>) -> Result<SetOutcome, IpcError> {
        let reason = self.closed.borrow().clone();
        if let Some(reason) = reason {
            return Err(IpcError::Closed(reason));
        }
        while let Ok(stale) = self.frames.try_recv() {
            if let Incoming::Closed(reason) = stale {
                return Err(IpcError::Closed(reason));
            }
        }
        self.nonce += 1;
        let nonce = format!("nsm-{}", self.nonce);
        let payload = json!({
            "cmd": "SET_ACTIVITY",
            "args": { "pid": std::process::id(), "activity": activity },
            "nonce": nonce,
        });
        self.write(OP_FRAME, &payload).await?;
        self.receive(|reply| (reply.get("nonce").and_then(Value::as_str) == Some(nonce.as_str())).then(|| Ok(outcome(reply)))).await
    }
}

#[cfg(windows)]
pub async fn open_pipe(name: &str) -> std::io::Result<tokio::net::windows::named_pipe::NamedPipeClient> {
    let mut attempts = 0;
    loop {
        match tokio::net::windows::named_pipe::ClientOptions::new().open(name) {
            Ok(pipe) => return Ok(pipe),
            Err(error) if error.raw_os_error() == Some(ERROR_PIPE_BUSY) && attempts < PIPE_BUSY_ATTEMPTS => {
                attempts += 1;
                tokio::time::sleep(PIPE_BUSY_RETRY).await;
            }
            Err(error) => return Err(error),
        }
    }
}

#[cfg(windows)]
pub async fn connect_pipe(name: &str, app_id: &str, io_timeout: Duration) -> Result<IpcClient, IpcError> {
    let pipe = open_pipe(name).await?;
    IpcClient::handshake(pipe, app_id, io_timeout).await
}

#[cfg(windows)]
pub async fn connect_slots(prefix: &str, app_id: &str, io_timeout: Duration) -> Result<IpcClient, IpcError> {
    let mut failure: Option<IpcError> = None;
    for index in 0..PIPE_SLOTS {
        match connect_pipe(&format!("{prefix}{index}"), app_id, io_timeout).await {
            Ok(client) => return Ok(client),
            Err(IpcError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                failure.get_or_insert(error);
            }
        }
    }
    Err(failure.unwrap_or(IpcError::NotRunning))
}

#[cfg(windows)]
pub async fn connect_discord(app_id: &str) -> Result<IpcClient, IpcError> {
    connect_slots(PIPE_PREFIX, app_id, IO_TIMEOUT).await
}
