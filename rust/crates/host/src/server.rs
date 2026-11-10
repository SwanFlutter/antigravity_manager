//! JSON-RPC dispatch for the application contract.

use std::sync::Arc;

use antigravity_contract::dto::{
    ConnectSessionDto, ConnectStatusDto, ConnectedAccountDto, HostInfoDto, ProxyStatusDto,
    TrafficEntryDto, WorkspaceDto,
};
use antigravity_contract::methods;
use antigravity_contract::{error_codes, Request, Response, RpcError};
use antigravity_core::mapping;
use antigravity_core::repository::{AccountService, RepositoryError, ServiceError};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::cloud::{self, CloudError, CloudService};

/// The context the dispatcher needs to answer a request.
pub struct Dispatcher {
    pub service: Arc<AccountService>,
    pub app_version: String,
    pub profile_path: String,
    /// The cloud side of the host. It is missing in the tests that only cover
    /// the account pool.
    pub cloud: Option<Arc<CloudService>>,
}

/// Parameters of `accounts.setActive`.
#[derive(Debug, Deserialize)]
struct SetActiveParams {
    id: String,
}

/// Parameters of `accounts.setSelected`.
#[derive(Debug, Deserialize)]
struct SetSelectedParams {
    id: String,
    selected: bool,
}

/// Parameters of the methods that address one account.
#[derive(Debug, Deserialize)]
struct IdParams {
    id: String,
}

/// Parameters of `accounts.connectStatus` and `accounts.submitCode`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SessionParams {
    session_id: String,
}

/// Parameters of `accounts.submitCode`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SubmitCodeParams {
    session_id: String,
    code: String,
}

/// Parameters of `proxy.start`.
#[derive(Debug, Deserialize)]
struct StartProxyParams {
    #[serde(default)]
    port: Option<u16>,
}

/// Parameters of `traffic.list`.
#[derive(Debug, Deserialize)]
struct TrafficParams {
    #[serde(default)]
    limit: Option<u32>,
}

fn invalid_params(message: &str) -> RpcError {
    RpcError::new(error_codes::INVALID_PARAMS, message)
}

fn service_error(error: ServiceError) -> RpcError {
    match error {
        ServiceError::Validation(message) => {
            RpcError::new(error_codes::VALIDATION, message)
        }
        ServiceError::Repository(repository) => {
            RpcError::new(error_codes::PERSISTENCE, repository.to_string())
        }
    }
}

fn repository_error(error: RepositoryError) -> RpcError {
    RpcError::new(error_codes::PERSISTENCE, error.to_string())
}

fn cloud_error(error: CloudError) -> RpcError {
    match error {
        CloudError::Invalid(message) => RpcError::new(error_codes::INVALID_PARAMS, message),
        CloudError::UnknownSession => RpcError::new(error_codes::INVALID_PARAMS, error.to_string()),
        CloudError::Provider(message) => RpcError::new(error_codes::UNAVAILABLE, message),
        CloudError::Repository(message) => RpcError::new(error_codes::PERSISTENCE, message),
    }
}

/// Answers one JSON-RPC request.
pub async fn dispatch(dispatcher: &Dispatcher, request: Request) -> Response {
    let id = request.id.clone();
    let result = handle(dispatcher, request).await;

    match result {
        Ok(value) => Response::ok(id, value),
        Err(error) => Response::err(id, error),
    }
}

/// The cloud service of the dispatcher.
fn cloud_of(dispatcher: &Dispatcher) -> Result<&Arc<CloudService>, RpcError> {
    dispatcher
        .cloud
        .as_ref()
        .ok_or_else(|| RpcError::new(error_codes::UNAVAILABLE, "the cloud service is not running"))
}

/// The state of the local proxy.
async fn proxy_status(service: &CloudService) -> Result<Value, RpcError> {
    let config = service.config.read().await.clone();

    let running = service.proxy.is_running().await;
    let port = service.proxy.current_port().await.unwrap_or(config.port);

    let status = ProxyStatusDto {
        running,
        port,
        base_url: format!("http://127.0.0.1:{port}"),
        api_key: config.api_key.clone(),
        selected_account_id: config.selected_account_id.clone(),
        models: service.catalog.models().len(),
    };

    Ok(serde_json::to_value(status).unwrap_or(Value::Null))
}

/// Builds the state of the proxy.
///
/// The state shares the live configuration with the host, so a new key takes
/// effect on the running proxy.
fn proxy_state(service: &CloudService) -> antigravity_proxy::ProxyState {
    antigravity_proxy::ProxyState {
        lease: Arc::new(cloud::HostLeaseProvider {
            accounts: service.accounts.clone(),
            cloud: service.cloud.clone(),
            google: service.google.clone(),
        }),
        models: service.catalog.clone(),
        traffic: Arc::new(cloud::HostTrafficRecorder {
            cloud: service.cloud.clone(),
        }),
        google: service.google.clone(),
        config: service.config.clone(),
    }
}

/// Runs the method behind a request and returns its result.
async fn handle(dispatcher: &Dispatcher, request: Request) -> Result<Value, RpcError> {
    match request.method.as_str() {
        methods::HOST_INFO => {
            let info = HostInfoDto {
                contract_version: antigravity_contract::CONTRACT_VERSION,
                app_version: dispatcher.app_version.clone(),
                profile_path: dispatcher.profile_path.clone(),
            };
            Ok(serde_json::to_value(info).unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_LIST => {
            let (accounts, summary) = dispatcher
                .service
                .list_accounts()
                .map_err(service_error)?;
            Ok(serde_json::to_value(mapping::account_list_to_dto(
                &accounts, &summary,
            ))
            .unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_SET_ACTIVE => {
            let params: SetActiveParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;
            dispatcher
                .service
                .set_active_account(&params.id)
                .map_err(service_error)?;
            // The proxy routes through the active account as well, so the
            // playground and the desktop clients share one account.
            if let Some(service) = dispatcher.cloud.as_ref() {
                let mut config = service.config.write().await.clone();
                config.selected_account_id = Some(params.id.clone());
                *service.config.write().await = config.clone();
                service
                    .cloud
                    .save_proxy_config(&config)
                    .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;
            }
            Ok(json!({ "ok": true }))
        }
        methods::ACCOUNTS_SET_SELECTED => {
            let params: SetSelectedParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;
            dispatcher
                .service
                .set_selected(&params.id, params.selected)
                .map_err(service_error)?;
            Ok(json!({ "ok": true }))
        }
        methods::MODELS_CATALOG => {
            let models = dispatcher.service.model_catalog().map_err(service_error)?;
            Ok(serde_json::to_value(
                models.iter().map(mapping::model_to_dto).collect::<Vec<_>>(),
            )
            .unwrap_or(Value::Null))
        }

        // --- Cloud accounts ---------------------------------------------

        methods::ACCOUNTS_START_CONNECT => {
            let service = cloud_of(dispatcher)?;
            let session_id = uuid::Uuid::new_v4().simple().to_string();
            let (authorization_url, redirect_uri, expires_at) =
                cloud::start_connect(service.clone(), session_id.clone())
                    .await
                    .map_err(cloud_error)?;

            let session = ConnectSessionDto {
                session_id,
                authorization_url,
                redirect_uri,
                expires_at,
            };
            Ok(serde_json::to_value(session).unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_CONNECT_STATUS => {
            let service = cloud_of(dispatcher)?;
            let params: SessionParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;

            let (status, email, error) = service
                .sessions
                .status(&params.session_id)
                .ok_or_else(|| invalid_params("unknown session"))?;

            let status = ConnectStatusDto {
                status,
                email,
                error,
            };
            Ok(serde_json::to_value(status).unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_SUBMIT_CODE => {
            let service = cloud_of(dispatcher)?;
            let params: SubmitCodeParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;

            cloud::submit_code(service.clone(), &params.session_id, &params.code)
                .await
                .map_err(cloud_error)?;

            let status = ConnectStatusDto {
                status: "pending".to_string(),
                email: None,
                error: None,
            };
            Ok(serde_json::to_value(status).unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_REFRESH_QUOTA => {
            let service = cloud_of(dispatcher)?;
            let params: IdParams =
                serde_json::from_value(request.params).map_err(|error| invalid_params(&error.to_string()))?;

            let (accounts, _) = dispatcher
                .service
                .list_accounts()
                .map_err(service_error)?;
            let account = accounts
                .into_iter()
                .find(|account| account.id == params.id)
                .ok_or_else(|| invalid_params("unknown account"))?;

            let updated = cloud::refresh_quota(service, &account)
                .await
                .map_err(cloud_error)?;
            Ok(serde_json::to_value(mapping::account_to_dto(&updated)).unwrap_or(Value::Null))
        }
        methods::ACCOUNTS_REMOVE => {
            let service = cloud_of(dispatcher)?;
            let params: IdParams =
                serde_json::from_value(request.params).map_err(|error| invalid_params(&error.to_string()))?;

            service
                .cloud
                .delete_credentials(&params.id)
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            let (accounts, _) = dispatcher.service.list_accounts().map_err(service_error)?;
            if let Some(account) = accounts.iter().find(|account| account.id == params.id) {
                let mut without = account.clone();
                without.quotas.clear();
                without.weekly_quotas.clear();
                dispatcher
                    .service
                    .repository()
                    .save_account(&without)
                    .map_err(repository_error)?;
            }

            Ok(json!({ "ok": true }))
        }
        methods::ACCOUNTS_CONNECTED => {
            let service = cloud_of(dispatcher)?;
            let ids = service
                .cloud
                .list_credential_accounts()
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            let mut connected = Vec::with_capacity(ids.len());
            for id in ids {
                if let Some(credentials) = service
                    .cloud
                    .load_credentials(&id)
                    .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?
                {
                    connected.push(ConnectedAccountDto {
                        account_id: credentials.account_id,
                        email: credentials.email,
                        plan: credentials.plan,
                        project_id: credentials.project_id,
                    });
                }
            }

            Ok(serde_json::to_value(connected).unwrap_or(Value::Null))
        }

        // --- Local proxy ------------------------------------------------

        methods::PROXY_STATUS => {
            let service = cloud_of(dispatcher)?;
            proxy_status(service).await
        }
        methods::PROXY_START => {
            let service = cloud_of(dispatcher)?;
            let params: StartProxyParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;

            let mut config = service.config.read().await.clone();
            if let Some(port) = params.port {
                config.port = port;
            }

            // A proxy with a key listens on every interface, a proxy without a
            // key stays on the loopback of the machine.
            let bind_all = config.api_key.is_some();
            *service.config.write().await = config.clone();

            let bound = service
                .proxy
                .start(proxy_state(service), config.port, bind_all)
                .await
                .map_err(cloud_error)?;
            config.port = bound;

            *service.config.write().await = config.clone();
            service
                .cloud
                .save_proxy_config(&config)
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            proxy_status(service).await
        }
        methods::PROXY_STOP => {
            let service = cloud_of(dispatcher)?;
            service.proxy.stop().await;
            proxy_status(service).await
        }
        methods::PROXY_ROTATE_KEY => {
            let service = cloud_of(dispatcher)?;
            let mut config = service.config.read().await.clone();
            config.api_key = Some(antigravity_core::cloud::ProxyConfig::generate_key());

            *service.config.write().await = config.clone();
            service
                .cloud
                .save_proxy_config(&config)
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            // The proxy listens on every interface as soon as it has a key,
            // so the running proxy is restarted.
            if service.proxy.is_running().await {
                let bind_all = config.api_key.is_some();
                let bound = service
                    .proxy
                    .restart(proxy_state(service), config.port, bind_all)
                    .await
                    .map_err(cloud_error)?;
                config.port = bound;
                *service.config.write().await = config.clone();
                service
                    .cloud
                    .save_proxy_config(&config)
                    .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;
            }

            proxy_status(service).await
        }

        // --- Workspaces ---------------------------------------------------

        methods::WORKSPACES_LIST => {
            let service = cloud_of(dispatcher)?;
            let workspaces = service
                .cloud
                .list_workspaces()
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;
            let (accounts, _) = dispatcher.service.list_accounts().map_err(service_error)?;
            let connected = service
                .cloud
                .list_credential_accounts()
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            let entries: Vec<WorkspaceDto> = workspaces
                .iter()
                .map(|workspace| {
                    let account = accounts
                        .iter()
                        .find(|account| account.id == workspace.account_id);
                    mapping::workspace_to_dto(
                        workspace,
                        account.map(|account| account.name.clone()).unwrap_or_default(),
                        account.map(|account| account.plan.clone()).unwrap_or_default(),
                        !connected.contains(&workspace.account_id),
                    )
                })
                .collect();

            Ok(serde_json::to_value(entries).unwrap_or(Value::Null))
        }

        // --- Traffic ----------------------------------------------------

        methods::TRAFFIC_LIST => {
            let service = cloud_of(dispatcher)?;
            let params: TrafficParams = serde_json::from_value(request.params)
                .map_err(|error| invalid_params(&error.to_string()))?;

            let entries = service
                .cloud
                .list_traffic(params.limit.unwrap_or(100))
                .map_err(|error| RpcError::new(error_codes::PERSISTENCE, error.to_string()))?;

            let entries: Vec<TrafficEntryDto> = entries
                .into_iter()
                .map(|entry| TrafficEntryDto {
                    id: entry.id,
                    at: entry.at,
                    protocol: entry.protocol,
                    model: entry.model,
                    account_id: entry.account_id,
                    status: entry.status,
                    duration_ms: entry.duration_ms,
                    request_bytes: entry.request_bytes,
                    response_bytes: entry.response_bytes,
                    error: entry.error,
                })
                .collect();

            Ok(serde_json::to_value(entries).unwrap_or(Value::Null))
        }

        other => Err(RpcError::new(
            error_codes::METHOD_NOT_FOUND,
            format!("unknown method: {other}"),
        )),
    }
}
