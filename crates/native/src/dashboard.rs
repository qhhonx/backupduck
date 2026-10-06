//! Opt-in, receiver-local browser management. The web credential is private
//! and never shares the transfer pairing token or exposes photo bytes.
use super::dashboard_access::Access;
use super::*;
use axum::{
    extract::{DefaultBodyLimit, Query, Request, State},
    http::{header, HeaderMap, HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use backupduck_store::catalog::Catalog;
use serde::Serialize;

const HTML: &str = include_str!("dashboard/index.html");
const CSS: &str = include_str!("dashboard/style.css");
const TOKENS: &str = include_str!("dashboard/tokens.css");
const DUCK: &[u8] = include_bytes!("../../../assets/AppIcon.png");
const JS: &str = include_str!("dashboard/app.js");

#[derive(Clone, Serialize)]
pub(super) struct DeviceStatus {
    pub temperature_deci_celsius: Option<i32>,
    pub battery_percent: Option<u8>,
    pub charging: Option<bool>,
    pub thermal_held: bool,
    pub thermal_enabled: bool,
    pub thermal_threshold_celsius: u8,
}

#[derive(Clone)]
struct WebState {
    receiver: Arc<Mutex<Receiver>>,
    root: PathBuf,
    origin: String,
    access: Arc<Mutex<Access>>,
    device_status: Arc<Mutex<Option<DeviceStatus>>>,
}

pub(super) struct DashboardHost {
    address: SocketAddr,
    access: Arc<Mutex<Access>>,
    handle: axum_server::Handle,
    task: tokio::task::JoinHandle<()>,
    device_status: Arc<Mutex<Option<DeviceStatus>>>,
}

pub(super) fn random_hex() -> Result<String> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|_| Error::Storage("dashboard random source".into()))?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

pub(super) fn random_code() -> Result<String> {
    let mut bytes = [0u8; 8];
    getrandom::fill(&mut bytes).map_err(|_| Error::Storage("dashboard random source".into()))?;
    Ok(format!(
        "{:010}",
        u64::from_be_bytes(bytes) % 10_000_000_000
    ))
}

pub(super) fn equal_secret(a: &str, b: &str) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.bytes()
        .zip(b.bytes())
        .fold(0u8, |difference, (x, y)| difference | (x ^ y))
        == 0
}

async fn security(State(state): State<WebState>, request: Request, next: Next) -> Response {
    let host = request
        .headers()
        .get(header::HOST)
        .and_then(|h| h.to_str().ok());
    if host != Some(state.origin.trim_start_matches("http://")) {
        return StatusCode::MISDIRECTED_REQUEST.into_response();
    }
    if let Some(origin) = request
        .headers()
        .get(header::ORIGIN)
        .and_then(|h| h.to_str().ok())
    {
        if origin != state.origin {
            return StatusCode::FORBIDDEN.into_response();
        }
    }
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
    headers.insert(header::CONTENT_SECURITY_POLICY, HeaderValue::from_static(
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; form-action 'none'; frame-ancestors 'none'",
    ));
    response
}

fn authorized(headers: &HeaderMap, state: &WebState) -> bool {
    headers
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .is_some_and(|token| state.access.lock().is_ok_and(|a| a.authorized(token)))
}

async fn index() -> Html<&'static str> {
    Html(HTML)
}
async fn css() -> ([(header::HeaderName, &'static str); 1], &'static str) {
    ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], CSS)
}
async fn tokens() -> ([(header::HeaderName, &'static str); 1], &'static str) {
    ([(header::CONTENT_TYPE, "text/css; charset=utf-8")], TOKENS)
}
async fn duck() -> ([(header::HeaderName, &'static str); 1], &'static [u8]) {
    ([(header::CONTENT_TYPE, "image/png")], DUCK)
}
async fn js() -> ([(header::HeaderName, &'static str); 1], &'static str) {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        JS,
    )
}

#[derive(Deserialize)]
struct Login {
    code: String,
    #[serde(default)]
    remember: bool,
}
async fn login(State(state): State<WebState>, Json(input): Json<Login>) -> Response {
    let mut access = match state.access.lock() {
        Ok(a) => a,
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    match access.login(&input.code, input.remember) {
        Ok(token) => Json(json!({"token":token})).into_response(),
        Err(Error::Unauthorized) => StatusCode::UNAUTHORIZED.into_response(),
        Err(Error::Conflict(_)) => StatusCode::TOO_MANY_REQUESTS.into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}
async fn logout(State(state): State<WebState>, headers: HeaderMap) -> Response {
    let token = headers
        .get(header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "));
    match token.and_then(|token| state.access.lock().ok().map(|mut a| a.logout(token))) {
        Some(Ok(())) => StatusCode::NO_CONTENT.into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

async fn overview(State(state): State<WebState>, headers: HeaderMap) -> Response {
    if !authorized(&headers, &state) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let receiver = state.receiver.clone();
    let device_status = match state.device_status.lock() {
        Ok(value) => value.clone(),
        Err(_) => return StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    };
    let root = state.root.clone();
    match tokio::task::spawn_blocking(move || {
        Ok::<_, Error>((
            receiver.lock().map_err(lock)?.overview()?,
            fs2::total_space(root).ok(),
        ))
    })
    .await
    {
        Ok(Ok((value, total_space))) => Json(json!({
            "total": value["total"],
            "received": value["received"],
            "published": value["published"],
            "failed": value["failed"],
            "waiting": value["waiting"],
            "reserved_bytes": value["reserved_bytes"],
            "free_bytes": value["free_bytes"],
            "min_free_bytes": value["min_free_bytes"],
            "total_space_bytes": total_space,
            "device": device_status,
        }))
        .into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

#[derive(Deserialize)]
struct HistoryQuery {
    search: Option<String>,
    state: Option<String>,
    kind: Option<String>,
    before: Option<i64>,
    page: Option<u32>,
    per_page: Option<u32>,
}
async fn history(
    State(state): State<WebState>,
    headers: HeaderMap,
    Query(query): Query<HistoryQuery>,
) -> Response {
    if !authorized(&headers, &state) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let numbered = query.page.is_some() || query.per_page.is_some();
    if numbered && query.before.is_some() {
        return StatusCode::BAD_REQUEST.into_response();
    }
    let page = query.page.unwrap_or(1);
    let per_page = query.per_page.unwrap_or(20);
    let root = state.root.clone();
    let result = tokio::task::spawn_blocking(move || {
        let catalog = Catalog::open(&root.join("store"))?;
        let state = query.state.as_deref().unwrap_or("all");
        let kind = query.kind.as_deref().unwrap_or("all");
        if numbered {
            catalog.numbered_page_matching(
                state,
                kind,
                page,
                per_page,
                query.search.as_deref().unwrap_or(""),
            )
        } else {
            catalog.page(query.before, state, kind, 50)
        }
    })
    .await;
    match result {
        Ok(Ok(value)) => Json(json!({
            "next_cursor": value.next_cursor,
            "total": value.total,
            "page": if numbered { Some(page) } else { None },
            "per_page": if numbered { Some(per_page) } else { None },
            "pages": if numbered { Some(((value.total.max(1) - 1) / i64::from(per_page)) + 1) } else { None },
            "items": value.items.into_iter().map(|item| json!({
                "filename": item.filename,
                "kind": item.kind,
                "burst_primary": item.burst_primary,
                "total_bytes": item.total_bytes,
                "confirmed_bytes": item.confirmed_bytes,
                "receipt": item.receipt,
                "processing": item.processing,
                "processing_error": item.processing_error,
                "captured_at_ms": item.captured_at_ms,
                "received_at_ms": item.received_at_ms,
                "published_at_ms": item.published_at_ms,
                "originals_released": item.originals_released,
                "senders": item.senders.into_iter().map(|peer| peer.profile.name).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
        })).into_response(),
        Ok(Err(Error::Invalid(_))) => StatusCode::BAD_REQUEST.into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

#[derive(Deserialize)]
struct RetryQuery {
    id: Option<String>,
}
async fn retry(
    State(state): State<WebState>,
    headers: HeaderMap,
    Query(query): Query<RetryQuery>,
) -> Response {
    if !authorized(&headers, &state) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let receiver = state.receiver.clone();
    match tokio::task::spawn_blocking(move || {
        receiver
            .lock()
            .map_err(lock)?
            .retry_processing_item(query.id.as_deref())
    })
    .await
    {
        Ok(Ok(count)) => Json(json!({"count":count})).into_response(),
        _ => StatusCode::INTERNAL_SERVER_ERROR.into_response(),
    }
}

fn router(state: WebState) -> Router {
    Router::new()
        .route("/", get(index))
        .route("/style.css", get(css))
        .route("/tokens.css", get(tokens))
        .route("/duck.png", get(duck))
        .route("/app.js", get(js))
        .route("/api/login", post(login))
        .route("/api/logout", post(logout))
        .route("/api/overview", get(overview))
        .route("/api/history", get(history))
        .route("/api/retry", post(retry))
        .layer(DefaultBodyLimit::max(1024))
        .layer(middleware::from_fn_with_state(state.clone(), security))
        .with_state(state)
}

impl DashboardHost {
    pub(super) fn start(
        receiver: Arc<Mutex<Receiver>>,
        root: PathBuf,
        listen: SocketAddr,
    ) -> Result<Self> {
        if listen.ip().is_unspecified() {
            return Err(Error::Invalid("dashboard interface".into()));
        }
        let listener = std::net::TcpListener::bind(listen)?;
        listener.set_nonblocking(true)?;
        let address = listener.local_addr()?;
        let access = Arc::new(Mutex::new(Access::open(&root)?));
        let state = WebState {
            receiver,
            root,
            origin: format!("http://{address}"),
            access: access.clone(),
            device_status: Arc::new(Mutex::new(None)),
        };
        let device_status = state.device_status.clone();
        let handle = axum_server::Handle::new();
        let server = axum_server::from_tcp(listener).handle(handle.clone());
        let task = runtime().spawn(async move {
            let _ = server.serve(router(state).into_make_service()).await;
        });
        Ok(Self {
            address,
            access,
            handle,
            task,
            device_status,
        })
    }
    pub(super) fn update_device_status(&self, status: DeviceStatus) -> Result<()> {
        *self.device_status.lock().map_err(lock)? = Some(status);
        Ok(())
    }
    pub(super) fn change_access(
        &self,
        code: Option<String>,
        reset: bool,
        revoke: bool,
    ) -> Result<Value> {
        let mut access = self.access.lock().map_err(lock)?;
        access.change(code, reset, revoke)?;
        Ok(json!({"code":access.code()}))
    }
    pub(super) fn info(&self) -> Value {
        json!({"url":format!("http://{}",self.address),"code":self.access.lock().ok().map(|a| a.code().to_owned())})
    }
}

impl Drop for DashboardHost {
    fn drop(&mut self) {
        self.handle.shutdown();
        self.task.abort();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn browser_access_requires_phone_code_and_separate_session() {
        let root =
            std::env::temp_dir().join(format!("backupduck-dashboard-{}", random_hex().unwrap()));
        fs::create_dir_all(root.join("store")).unwrap();
        let receiver = Arc::new(Mutex::new(
            Receiver::open(root.join("store"), 1 << 20).unwrap(),
        ));
        let dashboard = DashboardHost::start(
            receiver,
            root.clone(),
            SocketAddr::from(([127, 0, 0, 1], 0)),
        )
        .unwrap();
        let info = dashboard.info();
        let base = info["url"].as_str().unwrap();
        let code = info["code"].as_str().unwrap();
        let client = reqwest::Client::new();
        let mut ready = false;
        for _ in 0..50 {
            if client.get(base).send().await.is_ok() {
                ready = true;
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert!(ready);
        assert_eq!(
            client
                .get(format!("{base}/api/overview"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            client
                .post(format!("{base}/api/retry"))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            client
                .get(base)
                .header(header::HOST, "elsewhere.example")
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::MISDIRECTED_REQUEST
        );
        let page = client.get(base).send().await.unwrap();
        assert_eq!(page.status(), StatusCode::OK);
        assert_eq!(page.headers()[header::CACHE_CONTROL], "no-store");
        assert!(!page.text().await.unwrap().contains(code));
        assert_eq!(
            client
                .post(format!("{base}/api/login"))
                .header(header::ORIGIN, "http://elsewhere.example")
                .json(&json!({"code":code}))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            client
                .post(format!("{base}/api/login"))
                .json(&json!({"code":"bad"}))
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        let response = client
            .post(format!("{base}/api/login"))
            .json(&json!({"code":code}))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let token = response.json::<Value>().await.unwrap()["token"]
            .as_str()
            .unwrap()
            .to_owned();
        assert_ne!(token, code);
        dashboard
            .update_device_status(DeviceStatus {
                temperature_deci_celsius: Some(397),
                battery_percent: Some(82),
                charging: Some(true),
                thermal_held: false,
                thermal_enabled: true,
                thermal_threshold_celsius: 40,
            })
            .unwrap();
        let overview = client
            .get(format!("{base}/api/overview"))
            .bearer_auth(&token)
            .send()
            .await
            .unwrap();
        assert_eq!(overview.status(), StatusCode::OK);
        let overview = overview.json::<Value>().await.unwrap();
        assert_eq!(overview["total"], 0);
        assert_eq!(overview["device"]["temperature_deci_celsius"], 397);
        assert_eq!(overview["device"]["battery_percent"], 82);
        assert_eq!(overview["device"]["thermal_threshold_celsius"], 40);
        let numbered = client
            .get(format!("{base}/api/history?page=1&per_page=20"))
            .bearer_auth(&token)
            .send()
            .await
            .unwrap();
        assert_eq!(numbered.status(), StatusCode::OK);
        let numbered = numbered.json::<Value>().await.unwrap();
        assert_eq!(numbered["page"], 1);
        assert_eq!(numbered["pages"], 1);
        assert_eq!(numbered["per_page"], 20);
        assert_eq!(numbered["total"], 0);
        assert_eq!(
            client
                .get(format!("{base}/api/history?page=0&per_page=20"))
                .bearer_auth(&token)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            client
                .get(format!("{base}/api/history?state=bogus"))
                .bearer_auth(&token)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::BAD_REQUEST
        );
        let retry = client
            .post(format!("{base}/api/retry"))
            .bearer_auth(&token)
            .send()
            .await
            .unwrap();
        assert_eq!(retry.status(), StatusCode::OK);
        assert_eq!(retry.json::<Value>().await.unwrap()["count"], 0);
        assert_eq!(
            client
                .post(format!("{base}/api/logout"))
                .bearer_auth(&token)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::NO_CONTENT
        );
        assert_eq!(
            client
                .get(format!("{base}/api/overview"))
                .bearer_auth(&token)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        let new_token = client
            .post(format!("{base}/api/login"))
            .json(&json!({"code":code,"remember":true}))
            .send()
            .await
            .unwrap()
            .json::<Value>()
            .await
            .unwrap()["token"]
            .as_str()
            .unwrap()
            .to_owned();
        assert_ne!(token, new_token);
        dashboard
            .change_access(Some("0123456789".into()), false, false)
            .unwrap();
        assert_eq!(
            client
                .get(format!("{base}/api/overview"))
                .bearer_auth(&new_token)
                .send()
                .await
                .unwrap()
                .status(),
            StatusCode::UNAUTHORIZED
        );
        drop(dashboard);
        // The aborted HTTP task can release its SQLite handles on the next runtime turn.
        // Windows does not permit unlinking a still-open database file.
        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn browser_code_locks_after_five_failures() {
        let root =
            std::env::temp_dir().join(format!("backupduck-dashboard-{}", random_hex().unwrap()));
        fs::create_dir_all(root.join("store")).unwrap();
        let receiver = Arc::new(Mutex::new(
            Receiver::open(root.join("store"), 1 << 20).unwrap(),
        ));
        let dashboard = DashboardHost::start(
            receiver,
            root.clone(),
            SocketAddr::from(([127, 0, 0, 1], 0)),
        )
        .unwrap();
        let info = dashboard.info();
        let base = info["url"].as_str().unwrap();
        let client = reqwest::Client::new();
        for _ in 0..5 {
            let response = client
                .post(format!("{base}/api/login"))
                .json(&json!({"code":"bad"}))
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        }
        let response = client
            .post(format!("{base}/api/login"))
            .json(&json!({"code":info["code"]}))
            .send()
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        drop(dashboard);
        let _ = fs::remove_dir_all(root);
    }
}
