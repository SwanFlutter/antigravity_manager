//! The end to end test of the private named pipe transport.
//!
//! The test starts the real listener, connects a real client and exchanges
//! JSON-RPC frames over the pipe. It is the proof that the contract works
//! between two processes, not only between two functions.

use std::sync::Arc;
use std::time::Duration;

use antigravity_contract::{methods, Request, Response};
use antigravity_core::domain::{
    Account, AccountStatus, Model, ModelFamily, ModelGroup, ModelQuota, WeeklyQuota,
};
use antigravity_core::fakes::{FixedClock, InMemoryAccountRepository, StaticQuotaProvider};
use antigravity_core::repository::{AccountRepository, AccountService};
use antigravity_host::frame::{read_frame, write_frame};
use antigravity_host::server::Dispatcher;

use tokio::net::windows::named_pipe::ClientOptions;

fn account() -> Account {
    Account {
        id: "acc-01".to_string(),
        name: "Northwind Studio".to_string(),
        handle: "northwind.studio@example.com".to_string(),
        provider: "Google".to_string(),
        plan: "Google AI Pro".to_string(),
        status: AccountStatus::Active,
        credits: 2400,
        in_use: true,
        recommended: true,
        selected: false,
        demo: false,
        quotas: vec![ModelQuota {
            name: "Gemini 3.8 Flash (High)".to_string(),
            family: ModelFamily::Gemini,
            remaining: 0.8,
            reset_label: "6d 21h".to_string(),
        }],
        weekly_quotas: vec![WeeklyQuota {
            group_id: "gemini".to_string(),
            group_label: "Gemini models".to_string(),
            remaining: 0.86,
            reset_label: "6d 23h".to_string(),
        }],
    }
}

fn dispatcher() -> Arc<Dispatcher> {
    let catalog = vec![Model {
        id: "gemini-3.8-flash-high".to_string(),
        label: "Gemini 3.8 Flash (High)".to_string(),
        family: ModelFamily::Gemini,
    }];
    let groups = vec![ModelGroup {
        id: "gemini".to_string(),
        label: "Gemini models".to_string(),
        families: vec![ModelFamily::Gemini],
    }];

    let repository: Arc<dyn AccountRepository> =
        Arc::new(InMemoryAccountRepository::new(vec![account()], catalog, groups));
    let service = AccountService::new(
        repository,
        Box::new(StaticQuotaProvider),
        Box::new(FixedClock(0)),
    );

    Arc::new(Dispatcher {
        service: Arc::new(service),
        app_version: "0.1.0".to_string(),
        profile_path: "memory.sqlite3".to_string(),
        cloud: None,
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

    write_frame(client, &payload).await.expect("the request is written");
    let answer = read_frame(client).await.expect("the answer is read");

    serde_json::from_slice(&answer.expect("the host answered")).expect("the answer is valid")
}

#[tokio::test]
async fn the_host_answers_over_the_pipe() {
    let pipe_name = format!("antigravity-host-test-{}", std::process::id());
    let dispatcher = dispatcher();

    let listener = {
        let dispatcher = dispatcher.clone();
        let pipe_name = pipe_name.clone();
        tokio::spawn(async move {
            let _ = antigravity_host::pipe::serve(dispatcher, &pipe_name).await;
        })
    };

    let mut client = connect(&pipe_name).await;

    let info = call(&mut client, methods::HOST_INFO, serde_json::json!({})).await;
    assert!(info.error.is_none(), "host.info failed: {:?}", info.error);
    let info = info.result.expect("host.info returns a result");
    assert_eq!(
        info["contractVersion"], antigravity_contract::CONTRACT_VERSION
    );

    let list = call(&mut client, methods::ACCOUNTS_LIST, serde_json::json!({})).await;
    assert!(list.error.is_none(), "accounts.list failed: {:?}", list.error);
    let list = list.result.expect("accounts.list returns a result");
    assert_eq!(list["accounts"].as_array().map(|items| items.len()), Some(1));
    assert_eq!(list["accounts"][0]["id"], "acc-01");
    assert_eq!(list["summary"]["active"], 1);

    let catalog = call(&mut client, methods::MODELS_CATALOG, serde_json::json!({})).await;
    assert!(catalog.error.is_none(), "models.catalog failed");
    let catalog = catalog.result.expect("models.catalog returns a result");
    assert_eq!(catalog.as_array().map(|items| items.len()), Some(1));

    listener.abort();
}

#[tokio::test]
async fn an_unknown_method_is_reported() {
    let pipe_name = format!("antigravity-host-test-unknown-{}", std::process::id());
    let dispatcher = dispatcher();

    let listener = {
        let dispatcher = dispatcher.clone();
        let pipe_name = pipe_name.clone();
        tokio::spawn(async move {
            let _ = antigravity_host::pipe::serve(dispatcher, &pipe_name).await;
        })
    };

    let mut client = connect(&pipe_name).await;
    let answer = call(&mut client, "does.not.exist", serde_json::json!({})).await;

    let error = answer.error.expect("the host reports an error");
    assert_eq!(error.code, antigravity_contract::error_codes::METHOD_NOT_FOUND);

    listener.abort();
}
