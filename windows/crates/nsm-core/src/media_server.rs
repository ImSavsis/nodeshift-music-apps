use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{bail, Result};
use axum::body::{Body, Bytes};
use axum::extract::{Path, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;
use tower::ServiceExt;
use tower_http::services::ServeFile;
use uuid::Uuid;

use crate::drm::{self, Grant, Header, HEADER_SIZE, KIND_LOSSLESS, KIND_LOSSY};
use crate::engine::Engine;
use crate::net::site;

#[derive(Clone)]
struct AppState {
    engine: Engine,
    token: String,
}

#[derive(Debug, Clone)]
pub struct MediaServer {
    pub port: u16,
    pub token: String,
}

impl MediaServer {
    pub fn base(&self) -> String {
        format!("http://127.0.0.1:{}/{}", self.port, self.token)
    }
}

fn plain_name(name: &str) -> bool {
    !name.is_empty() && !name.contains('/') && !name.contains('\\') && !name.contains("..")
}

async fn serve_file(path: PathBuf, request: Request, cache: &'static str) -> Response {
    match ServeFile::new(path).oneshot(request).await {
        Ok(response) => {
            let mut response = response.map(axum::body::Body::new).into_response();
            response.headers_mut().insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
            response.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static(cache));
            response
        }
        Err(_) => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

#[derive(Clone)]
enum Origin {
    File(PathBuf),
    Remote(String),
}

async fn read_encrypted(engine: &Engine, origin: &Origin, offset: u64, length: u64) -> Result<Vec<u8>> {
    match origin {
        Origin::File(path) => {
            let path = path.clone();
            tokio::task::spawn_blocking(move || {
                let mut file = std::fs::File::open(path)?;
                file.seek(SeekFrom::Start(offset))?;
                let mut buffer = vec![0u8; length as usize];
                file.read_exact(&mut buffer)?;
                Ok(buffer)
            })
            .await?
        }
        Origin::Remote(url) => {
            let response = engine.http().get(url).header(header::RANGE, format!("bytes={}-{}", offset, offset + length - 1)).send().await?;
            if response.status().as_u16() != 206 {
                bail!("the file host refused the range");
            }
            let bytes = response.bytes().await?;
            if bytes.len() as u64 != length {
                bail!("the file host sent a short range");
            }
            Ok(bytes.to_vec())
        }
    }
}

async fn load_header(engine: &Engine, origin: &Origin, name: &str) -> Result<Header> {
    if let Some(known) = engine.vault().header(name) {
        return Ok(known);
    }
    let parsed = Header::parse(&read_encrypted(engine, origin, 0, HEADER_SIZE as u64).await?)?;
    engine.vault().keep_header(name, &parsed);
    Ok(parsed)
}

fn parse_range(value: Option<&str>, total: u64) -> Option<(u64, u64)> {
    let text = value?.trim().strip_prefix("bytes=")?;
    let (from, to) = text.split_once('-')?;
    if from.is_empty() {
        let suffix: u64 = to.parse().ok()?;
        return Some((total.saturating_sub(suffix), total.checked_sub(1)?));
    }
    let start: u64 = from.parse().ok()?;
    let end: u64 = if to.is_empty() { total.checked_sub(1)? } else { to.parse::<u64>().ok()?.min(total.checked_sub(1)?) };
    (start <= end && start < total).then_some((start, end))
}

struct Reader {
    engine: Engine,
    origin: Origin,
    header: Header,
    key: [u8; 32],
}

impl Reader {
    async fn batch(&self, start: u64, end: u64) -> Result<Vec<u8>> {
        let span = self.header.span(start, end);
        let blob = read_encrypted(&self.engine, &self.origin, span.offset, span.length).await?;
        drm::decrypt_range(&self.key, &self.header, span, &blob, start, end)
    }
}

async fn serve_locked(engine: Engine, origin: Origin, grant: Grant, headers: HeaderMap) -> Response {
    let Ok(key) = grant.key() else {
        return StatusCode::FORBIDDEN.into_response();
    };
    let Ok(header) = load_header(&engine, &origin, &grant.name).await else {
        return StatusCode::BAD_GATEWAY.into_response();
    };
    if header.key_id != grant.key_id || header.plain_length == 0 {
        return StatusCode::CONFLICT.into_response();
    }
    let total = header.plain_length;
    let requested = headers.get(header::RANGE).and_then(|value| value.to_str().ok());
    let (start, end, partial) = match parse_range(requested, total) {
        Some((start, end)) => (start, end, true),
        None if requested.is_some() => return StatusCode::RANGE_NOT_SATISFIABLE.into_response(),
        None => (0, total - 1, false),
    };
    let size = header.chunk_size as u64;
    let mime = header.mime();
    let reader = Arc::new(Reader { engine, origin, header, key });
    let stream = futures_util::stream::unfold(start, move |cursor| {
        let reader = reader.clone();
        async move {
            if cursor > end {
                return None;
            }
            let last = end.min((cursor / size + drm::BATCH_CHUNKS) * size - 1);
            match reader.batch(cursor, last).await {
                Ok(bytes) => Some((Ok::<Bytes, std::io::Error>(Bytes::from(bytes)), last + 1)),
                Err(error) => Some((Err(std::io::Error::other(error.to_string())), end + 1)),
            }
        }
    });
    let mut builder = Response::builder()
        .status(if partial { StatusCode::PARTIAL_CONTENT } else { StatusCode::OK })
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CONTENT_LENGTH, end - start + 1)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .header(header::CACHE_CONTROL, "no-store");
    if partial {
        builder = builder.header(header::CONTENT_RANGE, format!("bytes {start}-{end}/{total}"));
    }
    builder.body(Body::from_stream(stream)).unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

async fn track(State(state): State<AppState>, Path((token, id)): Path<(String, String)>, headers: HeaderMap, request: Request) -> Response {
    if token != state.token {
        return StatusCode::NOT_FOUND.into_response();
    }
    let Ok(Some(track)) = state.engine.db().track(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !plain_name(&track.file_name) {
        return StatusCode::NOT_FOUND.into_response();
    }
    let path = state.engine.paths().track_file(&track.file_name);
    if !drm::is_locked_name(&track.file_name) {
        return serve_file(path, request, "no-cache").await;
    }
    let kind = if track.file_name.ends_with(".nlac") { KIND_LOSSLESS } else { KIND_LOSSY };
    let Some(site_id) = track.site_id.clone() else {
        return StatusCode::FORBIDDEN.into_response();
    };
    match state.engine.grant_for_playback(&site_id, kind).await {
        Ok(grant) => serve_locked(state.engine.clone(), Origin::File(path), grant, headers).await,
        Err(_) => StatusCode::FORBIDDEN.into_response(),
    }
}

async fn site_track(State(state): State<AppState>, Path((token, site_id)): Path<(String, String)>, headers: HeaderMap) -> Response {
    if token != state.token {
        return StatusCode::NOT_FOUND.into_response();
    }
    match state.engine.grant(&site_id, KIND_LOSSY, false).await {
        Ok(grant) => {
            let origin = Origin::Remote(site::locked_url(&grant.name));
            serve_locked(state.engine.clone(), origin, grant, headers).await
        }
        Err(_) => StatusCode::FORBIDDEN.into_response(),
    }
}

async fn cover(State(state): State<AppState>, Path((token, name)): Path<(String, String)>, request: Request) -> Response {
    if token != state.token || !plain_name(&name) {
        return StatusCode::NOT_FOUND.into_response();
    }
    serve_file(state.engine.paths().cover_file(&name), request, "public, max-age=86400").await
}

async fn motion(State(state): State<AppState>, Path((token, name)): Path<(String, String)>, request: Request) -> Response {
    if token != state.token || !plain_name(&name) {
        return StatusCode::NOT_FOUND.into_response();
    }
    serve_file(state.engine.paths().motion_file(&name), request, "public, max-age=86400").await
}

pub async fn start(engine: Engine) -> Result<MediaServer> {
    let token = Uuid::new_v4().simple().to_string();
    let state = AppState { engine, token: token.clone() };
    let app = Router::new()
        .route("/{token}/track/{id}", get(track))
        .route("/{token}/site/{site_id}", get(site_track))
        .route("/{token}/cover/{name}", get(cover))
        .route("/{token}/motion/{name}", get(motion))
        .with_state(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let port = listener.local_addr()?.port();
    tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });
    Ok(MediaServer { port, token })
}
