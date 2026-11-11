//! The Antigravity Manager desktop host.
//!
//! The process owns the profile on disk and exposes the application contract
//! on a private named pipe. The Flutter UI is a client of that contract; it
//! never touches the database directly.

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;

use antigravity_contract::PIPE_NAME;
use antigravity_core::demo;
use antigravity_core::repository::{AccountRepository, AccountService, Clock, CloudRepository};
use antigravity_core::sqlite::SqliteAccountRepository;
use antigravity_google::GoogleClient;
use antigravity_host::cloud::{
    CloudService, HostLeaseProvider, HostModelCatalog, HostTrafficRecorder, ProxyRuntime,
};
use antigravity_host::oauth::SessionStore;
use antigravity_host::pipe;
use antigravity_host::server::Dispatcher;
use antigravity_host::upstream;

/// The application version reported by `host.info`.
const APP_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The options accepted on the command line.
struct Options {
    profile: PathBuf,
    pipe_name: String,
    seed_demo: bool,
    reseed: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            profile: default_profile_path(),
            pipe_name: PIPE_NAME.to_string(),
            seed_demo: false,
            reseed: false,
        }
    }
}

/// The default location of the profile database.
///
/// The profile belongs to the host, not to the UI: every client of the pipe
/// reads the same file.
fn default_profile_path() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("."));

    base.join("AntigravityManager").join("profile.sqlite3")
}

/// A clock that reports the real time.
struct SystemClock;

impl Clock for SystemClock {
    fn now_millis(&self) -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.as_millis() as i64)
            .unwrap_or(0)
    }
}

fn print_usage() {
    println!(
        "antigravity-host {APP_VERSION}\n\n\
         Usage: antigravity-host [options]\n\n\
         Options:\n  \
         --profile <path>  Location of the profile database\n  \
         --pipe <name>     Name of the named pipe (default: {PIPE_NAME})\n  \
         --seed-demo       Writes the synthetic dataset into the profile\n  \
         --reseed          Reseeds a demo-only profile (refuses real accounts)\n  \
         -h, --help        Shows this message"
    );
}

/// Parses the command line.
fn parse_options() -> Result<Options, String> {
    let mut options = Options::default();
    let mut arguments = std::env::args().skip(1);

    while let Some(argument) = arguments.next() {
        match argument.as_str() {
            "--profile" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--profile requires a path".to_string())?;
                options.profile = PathBuf::from(value);
            }
            "--pipe" => {
                let value = arguments
                    .next()
                    .ok_or_else(|| "--pipe requires a name".to_string())?;
                options.pipe_name = value;
            }
            "--seed-demo" => options.seed_demo = true,
            "--reseed" => options.reseed = true,
            "-h" | "--help" => {
                print_usage();
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    Ok(options)
}

/// Opens the profile and imports missing accounts. Demo data is opt-in only.
fn open_repository(options: &Options) -> Result<Arc<SqliteAccountRepository>, String> {
    if let Some(parent) = options.profile.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|error| format!("cannot create {}: {error}", parent.display()))?;
        }
    }

    let repository = SqliteAccountRepository::open(&options.profile.to_string_lossy())
        .map_err(|error| format!("cannot open the profile: {error}"))?;

    initialize_repository(&repository, options.seed_demo || options.reseed, || {
        upstream::import_upstream(&repository, SystemClock.now_millis())
    })?;
    Ok(Arc::new(repository))
}

fn initialize_repository(
    repository: &SqliteAccountRepository,
    explicit_demo: bool,
    import: impl FnOnce() -> Result<usize, String>,
) -> Result<(), String> {
    let accounts = repository.list_accounts().map_err(|error| error.to_string())?;
    if explicit_demo {
        // Do not import into, or wipe, a profile explicitly opened for demos.
        // seed_demo also checks credentials, including partially saved identities.
        demo::seed_demo(repository).map_err(|error| error.to_string())?;
        return Ok(());
    }

    // Recognize the exact undated stock catalog left by older demo startup.
    // Account and quota rows are untouched; only imported/fetched models may
    // repopulate this production catalog.
    let catalog = repository.model_catalog().map_err(|error| error.to_string())?;
    let stock = demo::model_catalog();
    if !accounts.iter().any(|account| account.quota_fetched_at.is_some())
        && catalog.len() == stock.len()
        && stock.iter().all(|model| catalog.contains(model))
    {
        repository.clear_catalog().map_err(|error| error.to_string())?;
    }
    let imported = import()?;
    if imported > 0 {
        println!("[host] imported {imported} missing account(s) from the upstream installation");
    }
    Ok(())
}

#[tokio::main]
async fn main() -> ExitCode {
    let options = match parse_options() {
        Ok(options) => options,
        Err(error) => {
            eprintln!("[host] {error}");
            print_usage();
            return ExitCode::from(2);
        }
    };

    let repository = match open_repository(&options) {
        Ok(repository) => repository,
        Err(error) => {
            eprintln!("[host] {error}");
            return ExitCode::from(1);
        }
    };

    let google = match GoogleClient::new() {
        Ok(client) => Arc::new(client),
        Err(error) => {
            eprintln!("[host] cannot reach the provider: {error}");
            return ExitCode::from(1);
        }
    };

    let accounts = Arc::new(AccountService::new(
        repository.clone(),
        Box::new(antigravity_core::fakes::StaticQuotaProvider),
        Box::new(SystemClock),
    ));

    // The live configuration of the proxy starts with the one of the profile.
    let config = repository.load_proxy_config().unwrap_or_default();

    let service = Arc::new(CloudService {
        accounts: accounts.clone(),
        cloud: repository.clone(),
        google: google.clone(),
        sessions: Arc::new(SessionStore::default()),
        proxy: Arc::new(ProxyRuntime::default()),
        catalog: Arc::new(HostModelCatalog {
            accounts: accounts.clone(),
        }),
        config: Arc::new(tokio::sync::RwLock::new(config.clone())),
        // The interface opens the authorization URL itself, so the host must
        // not open a second browser window on top of it.
        launch_browser: false,
    });

    // The proxy starts with the host when it is configured that way.
    if config.auto_start {
        let bind_all = config.api_key.is_some();
        match service
            .proxy
            .start(
                antigravity_proxy::ProxyState {
                    lease: Arc::new(HostLeaseProvider {
                        accounts: accounts.clone(),
                        cloud: repository.clone(),
                        google: google.clone(),
                    }),
                    models: service.catalog.clone(),
                    traffic: Arc::new(HostTrafficRecorder {
                        cloud: repository.clone(),
                    }),
                    google: google.clone(),
                    config: service.config.clone(),
                },
                config.port,
                bind_all,
            )
            .await
        {
            Ok(port) => println!("[host] the local proxy listens on port {port}"),
            Err(error) => eprintln!("[host] the local proxy did not start: {error}"),
        }
    }

    let dispatcher = Arc::new(Dispatcher {
        service: accounts.clone(),
        app_version: APP_VERSION.to_string(),
        profile_path: options.profile.to_string_lossy().to_string(),
        cloud: Some(service.clone()),
    });

    println!(
        "[host] listening on \\\\.\\pipe\\{} (contract version {})",
        options.pipe_name,
        antigravity_contract::CONTRACT_VERSION
    );

    match pipe::serve(dispatcher, &options.pipe_name).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("[host] pipe stopped: {error}");
            ExitCode::from(1)
        }
    }
}
