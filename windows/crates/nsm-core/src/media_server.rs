use std::path::PathBuf;

use anyhow::Result;
use axum::extract::{Path, Request, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;
use tower::ServiceExt;
use tower_http::services::ServeFile;
use uuid::Uuid;

use crate::engine::Engine;

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

async fn track(State(state): State<AppState>, Path((token, id)): Path<(String, String)>, request: Request) -> Response {
    if token != state.token {
        return StatusCode::NOT_FOUND.into_response();
    }
    let Ok(Some(track)) = state.engine.db().track(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if !plain_name(&track.file_name) {
        return StatusCode::NOT_FOUND.into_response();
    }
    serve_file(state.engine.paths().track_file(&track.file_name), request, "no-cache").await
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
