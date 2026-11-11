//! The contract test of the cloud methods.
//!
//! The test starts the real listener with a real profile on disk and talks to
//! it over the private named pipe. It proves that the names of the
//! parameters and the names of the answers of the cloud methods are the ones
//! the Flutter client sends and expects.

use std::sync::Arc;
use std::time::Duration;

use antigravity_contract::{methods, Request, Response};
use antigravity_core::fakes::{FixedClock, StaticQuotaProvider};
use antigravity_core::repository::{AccountService, CloudRepository};
use antigravity_core::sqlite::SqliteAccountRepository;
use antigravity_google::GoogleClient;
use antigravity_host::cloud::{CloudService, HostModelCatalog, ProxyRuntime};
use antigravity_host::oauth::SessionStore;
use antigravity_host::server::Dispatcher;

use tokio::net::windows::named_pipe::ClientOptions;

/// Builds the dispatcher of the test on a profile of its own.
fn dispatcher(directory: &std::path::Path) -> Arc<Dispatcher> {
    let profile = directory.join("profile.sqlite3");
    let repository = Arc::new(
        SqliteAccountRepository::open(&profile.to_string_lossy()).expect("the profile opens"),
    );

    // The production host seeds an empty profile with the demo dataset, so the
    // test does the same to get the same catalog.
    antigravity_core::demo::seed_demo(&repository).expect("the demo data is written");

    let accounts = Arc::new(AccountService::new(
        repository.clone(),
        Box::new(StaticQuotaProvider),
        Box::new(FixedClock(0)),
    ));

    let google = Arc::new(GoogleClient::new().expect("the client of Google is built"));

    let service = Arc::new(CloudService {
        accounts: accounts.clone(),
        cloud: repository.clone(),
        google: google.clone(),
        sessions: Arc::new(SessionStore::default()),
        proxy: Arc::new(ProxyRuntime::default()),
        catalog: Arc::new(HostModelCatalog {
            accounts: accounts.clone(),
        }),
        config: Arc::new(tokio::sync::RwLock::new(
            repository.load_proxy_config().expect("the configuration is read"),
        )),
        // The test must not open a browser window.
        launch_browser: false,
    });

    Arc::new(Dispatcher {
        service: accounts,
        app_version: "0.1.0".to_string(),
        profile_path: profile.to_string_lossy().to_string(),
        cloud: Some(service),
    })
}

/// Opens a client connection, retrying while the listener starts.
async fn connect(pipe_name: &str) -> tokio::net::windows::named_pipe::NamedPipeClient {
    let path = format!(r"\\.\pipe\{pipe_name}");

    for _ in 0..50 {
        match ClientOptions::new().open(&path) {
            Ok(client) => return client,
            Err(_) => tokio::time::sleep(Duration::from_millis(50)).await,
        }
    }

    panic!("the pipe {path} never became available");
}

/// Sends a request and reads the answer.
async fn call(
    client: &mut tokio::net::windows::named_pipe::NamedPipeClient,
    method: &str,
    params: serde_json::Value,
) -> Response {
    let request = Request::new(Some(serde_json::json!(1)), method, params);
    let payload = serde_json::to_vec(&request).expect("the request is serializable");

    antigravity_host::frame::write_frame(client, &payload)
        .await
        .expect("the request is written");
    let answer = antigravity_host::frame::read_frame(client)
        .await
        .expect("the answer is read");

    serde_json::from_slice(&answer.expect("the host answered")).expect("the answer is valid")
}

#[tokio::test]
async fn the_cloud_methods_speak_the_names_of_the_client() {
    let test_id = uuid::Uuid::new_v4();
    let pipe_name = format!("antigravity-host-cloud-{test_id}");
    let directory = std::env::temp_dir().join(format!("antigravity-cloud-{test_id}"));
    std::fs::create_dir_all(&directory).expect("the directory of the profile exists");

    let dispatcher = dispatcher(&directory);
    let listener = {
        let dispatcher = dispatcher.clone();
        let pipe_name = pipe_name.clone();
        tokio::spawn(async move {
            let _ = antigravity_host::pipe::serve(dispatcher, &pipe_name).await;
        })
    };

    let mut client = connect(&pipe_name).await;

    // --- accounts.startConnect ------------------------------------------
    let started = call(&mut client, methods::ACCOUNTS_START_CONNECT, serde_json::json!({})).await;
    assert!(started.error.is_none(), "startConnect failed: {:?}", started.error);
    let session = started.result.expect("startConnect returns a result");

    let session_id = session["sessionId"].as_str().expect("the session has an id");
    assert!(!session_id.is_empty());
    let redirect = session["redirectUri"].as_str().expect("the session has a redirect");
    assert!(redirect.starts_with("http://127.0.0.1:"), "{redirect}");
    assert!(redirect.ends_with("/oauth-callback"), "{redirect}");

    let url = session["authorizationUrl"].as_str().expect("the session has a url");
    assert!(url.starts_with("https://accounts.google.com/o/oauth2/v2/auth"), "{url}");
    assert!(url.contains("response_type=code"), "{url}");
    assert!(url.contains("client_id=1071006060591-"), "{url}");
    assert!(url.contains("access_type=offline"), "{url}");

    // --- accounts.connectStatus -----------------------------------------
    // The client sends the name of the session in camel case.
    let status = call(
        &mut client,
        methods::ACCOUNTS_CONNECT_STATUS,
        serde_json::json!({ "sessionId": session_id }),
    )
    .await;
    assert!(status.error.is_none(), "connectStatus failed: {:?}", status.error);
    let status = status.result.expect("connectStatus returns a result");
    assert_eq!(status["status"], "pending");

    let empty = call(
        &mut client,
        methods::ACCOUNTS_SUBMIT_CODE,
        serde_json::json!({ "sessionId": session_id, "code": " \r\n " }),
    ).await;
    assert!(empty.error.is_some());
    assert_eq!(dispatcher.cloud.as_ref().unwrap().sessions.status(session_id).unwrap().0, "pending");

    let state = reqwest::Url::parse(url).unwrap().query_pairs()
        .find(|(key, _)| key == "state").unwrap().1.into_owned();
    let http = reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(3)).build().unwrap();
    let mismatch = http.get(format!("{redirect}?state=wrong&error=access_denied"))
        .send().await.unwrap();
    assert_eq!(mismatch.status(), 400);
    assert_eq!(dispatcher.cloud.as_ref().unwrap().sessions.status(session_id).unwrap().0, "pending");
    let denied = http.get(format!("{redirect}?state={state}&error=access_denied"))
        .send().await.unwrap();
    assert!(denied.text().await.unwrap().contains("Authorization cancelled"));
    let failed = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            let response = call(
                &mut client,
                methods::ACCOUNTS_CONNECT_STATUS,
                serde_json::json!({ "sessionId": session_id }),
            ).await;
            let status = response.result.unwrap();
            if status["status"] != "pending" {
                break status;
            }
            tokio::task::yield_now().await;
        }
    }).await.unwrap();
    assert_eq!(failed["status"], "failed");
    assert!(failed["error"].as_str().unwrap().contains("cancelled"));
    for _ in 0..2 {
        let reused = call(
            &mut client,
            methods::ACCOUNTS_SUBMIT_CODE,
            serde_json::json!({ "sessionId": session_id, "code": "unused-test-code" }),
        ).await;
        assert!(reused.error.is_some());
    }
    let sessions = &dispatcher.cloud.as_ref().unwrap().sessions;
    sessions.expire(session_id, i64::MAX);
    assert_eq!(sessions.status(session_id).unwrap().0, "failed");

    // --- accounts.connected ---------------------------------------------
    let connected = call(&mut client, methods::ACCOUNTS_CONNECTED, serde_json::json!({})).await;
    assert!(connected.error.is_none(), "connected failed: {:?}", connected.error);
    let connected = connected.result.expect("connected returns a result");
    assert_eq!(connected.as_array().map(|items| items.len()), Some(0));

    // --- proxy.status ----------------------------------------------------
    let proxy = call(&mut client, methods::PROXY_STATUS, serde_json::json!({})).await;
    assert!(proxy.error.is_none(), "proxy.status failed: {:?}", proxy.error);
    let proxy = proxy.result.expect("proxy.status returns a result");
    assert_eq!(proxy["running"], false);
    assert_eq!(proxy["port"], 8045);
    assert_eq!(proxy["baseUrl"], "http://127.0.0.1:8045");
    assert!(proxy["models"].as_u64().unwrap_or(0) > 0);

    // --- traffic.list ----------------------------------------------------
    let traffic = call(&mut client, methods::TRAFFIC_LIST, serde_json::json!({})).await;
    assert!(traffic.error.is_none(), "traffic.list failed: {:?}", traffic.error);
    let traffic = traffic.result.expect("traffic.list returns a result");
    assert_eq!(traffic.as_array().map(|items| items.len()), Some(0));

    // --- proxy.rotateKey --------------------------------------------------
    // The key the running proxy checks is the key of the live configuration,
    // so a new key takes effect at once.
    let rotated = call(&mut client, methods::PROXY_ROTATE_KEY, serde_json::json!({})).await;
    assert!(rotated.error.is_none(), "rotateKey failed: {:?}", rotated.error);
    let rotated = rotated.result.expect("rotateKey returns a result");
    let key = rotated["apiKey"].as_str().expect("the proxy has a key");
    assert!(key.starts_with("sk-"), "{key}");
    assert_eq!(key.len(), 35, "{key}");

    let status = call(&mut client, methods::PROXY_STATUS, serde_json::json!({})).await;
    let status = status.result.expect("proxy.status returns a result");
    assert_eq!(status["apiKey"], key);

    listener.abort();
}

#[tokio::test]
async fn the_proxy_of_the_host_serves_the_models() {
    let pipe_name = format!("antigravity-host-proxy-{}", std::process::id());
    let directory = std::env::temp_dir().join(format!("antigravity-proxy-{}", std::process::id()));
    std::fs::create_dir_all(&directory).expect("the directory of the profile exists");

    let dispatcher = dispatcher(&directory);
    let listener = {
        let dispatcher = dispatcher.clone();
        let pipe_name = pipe_name.clone();
        tokio::spawn(async move {
            let _ = antigravity_host::pipe::serve(dispatcher, &pipe_name).await;
        })
    };

    let mut client = connect(&pipe_name).await;

    let started = call(
        &mut client,
        methods::PROXY_START,
        serde_json::json!({ "port": 0 }),
    )
    .await;
    assert!(started.error.is_none(), "proxy.start failed: {:?}", started.error);
    let started = started.result.expect("proxy.start returns a result");
    assert_eq!(started["running"], true);
    let port = started["port"].as_u64().expect("the proxy has a port");
    assert!(port > 0);

    // The gateway answers on the port it announced.
    let health = reqwest::get(format!("http://127.0.0.1:{port}/health"))
        .await
        .expect("the gateway answers");
    assert_eq!(health.status(), 200);

    let models = reqwest::get(format!("http://127.0.0.1:{port}/v1/models"))
        .await
        .expect("the catalog answers");
    assert_eq!(models.status(), 200);
    let payload = models.json::<serde_json::Value>().await.expect("the catalog is json");
    assert!(payload["data"].as_array().map(|items| items.len()).unwrap_or(0) > 0);

    listener.abort();
}
