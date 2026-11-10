# The Rust core of Antigravity Manager

This directory holds the Rust implementation of the application core: the
domain rules, the SQLite profile, the adapter of the Google Cloud Code
endpoints, the local API gateway and the private transport the Flutter UI
talks to.

```
rust/
  crates/
    contract/   the versioned contract shared by both sides (DTOs, error codes)
    core/       the domain, the SQLite repository, the service and the fakes
    google/     the adapter of the Google OAuth and Cloud Code endpoints
    proxy/      the local gateway: OpenAI and Anthropic compatible endpoints
    host/       the named pipe listener, the OAuth session and the dispatch
```

## Build, test and run

```powershell
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
cd rust
cargo test                      # 49 tests: domain, persistence, gateway and the pipe
cargo run --bin antigravity-host
```

The host accepts four options:

| Option | Meaning |
| --- | --- |
| `--profile <path>` | Location of the profile database (default: `%APPDATA%\AntigravityManager\profile.sqlite3`) |
| `--pipe <name>` | Name of the named pipe (default: `antigravity-manager-host`) |
| `--seed-demo` | Writes the synthetic dataset into the profile |
| `--reseed` | Replaces the data of the profile with the synthetic dataset |

An empty profile is seeded automatically, so the first run always has data.

The Flutter build compiles the host with cargo and places it next to the
application, so the launcher of the UI always finds it.

## The contract

The pipe carries JSON-RPC 2.0. Every frame is a four byte little endian
length followed by the UTF-8 JSON payload, and the pipe runs in byte mode, so
the framing does not depend on the message mode of the pipe.

The current contract version is `1` (`CONTRACT_VERSION` in
`crates/contract`). The Dart side refuses to talk to a host that reports a
different version. The names of the parameters and of the answers are in
camel case.

| Method | Purpose |
| --- | --- |
| `host.info` | Contract version, app version and the active profile path |
| `accounts.list` | Every account with its quota windows and the aggregate counters |
| `accounts.setActive` | Marks the account used by the desktop clients |
| `accounts.setSelected` | Adds or removes an account from the selection |
| `models.catalog` | The models the gateway can route to |
| `accounts.startConnect` | Starts an OAuth session and returns the authorization URL |
| `accounts.connectStatus` | The state of a running session (`pending`, `completed`, `failed`, `expired`) |
| `accounts.submitCode` | Finishes a session with a code the user copied by hand |
| `accounts.refreshQuota` | Reads the quota of one account from the provider |
| `accounts.remove` | Removes an account together with its credentials |
| `accounts.connected` | The accounts that are connected with real credentials |
| `proxy.status` | The state of the local gateway |
| `proxy.start` | Starts the local gateway |
| `proxy.stop` | Stops the local gateway |
| `proxy.rotateKey` | Replaces the key of the local gateway |
| `traffic.list` | The newest requests that passed through the gateway |

Error codes are stable: `-32600` invalid request, `-32601` unknown method,
`-32602` invalid parameters, `-32000` version mismatch, `-32001` validation,
`-32002` persistence, `-32003` dependency unavailable, `-32004` cancelled.

## Connecting a Google account

`accounts.startConnect` opens a listener on the loopback interface, builds the
authorization URL of the built-in Antigravity client and opens the browser.
Google sends the answer back to `http://127.0.0.1:<port>/oauth-callback`,
where the host reads the code, exchanges it for the tokens and stores the
account with its credentials.

The session expires after five minutes. When Google refuses the redirect of
the built-in client, the user can open the authorization URL by hand and paste
the code of the answer into the screen; `accounts.submitCode` finishes the same
session.

The credentials are stored in the `account_credentials` table of the profile.
The access token is refreshed automatically when it expires.

## The local gateway

The gateway speaks the protocols of the coding tools and forwards the requests
to Google with the credentials of the connected account.

| Endpoint | Protocol |
| --- | --- |
| `GET /health` | The health of the gateway |
| `GET /v1/models` | The catalog of the models |
| `GET /v1/models/{model}` | One model of the catalog |
| `POST /v1/chat/completions` | OpenAI, with and without streaming |
| `POST /v1/messages` | Anthropic, with and without streaming |

The key of the gateway is local and has the format `sk-<32 hex>`. It is sent
as `Authorization: Bearer`, as `x-api-key` or as `x-goog-api-key`. Without a
key the gateway accepts every request and stays on the loopback interface; with
a key it listens on every interface.

The default port is `8045`, the port of the upstream application as well, so
only one of the two can use it at the same time.

## Rules of the core

- The core never talks to Flutter or to Windows. Every dependency is a trait
  (`AccountRepository`, `CloudRepository`, `QuotaProvider`, `Clock`,
  `LeaseProvider`, `ModelCatalog`, `TrafficRecorder`, `Generator`) with a
  deterministic fake for the tests.
- The adapter of Google and the gateway are the only crates that use the
  network. The gateway talks to the provider through the `Generator` trait, so
  it can be tested without the network.
- The profile is versioned through `schema_version` and every migration runs
  inside a transaction. A profile written by a newer build is refused instead
  of being downgraded.
- The demo dataset reproduces the values of the Flutter prototype with a
  deterministic generator, so switching between the in process fake and the
  running host does not change what is on screen.

## Talking to the host from Dart

```powershell
dart run tool/ffi_probe.dart      # the state of the host
dart run tool/cloud_probe.dart     # the cloud flow: proxy, traffic and session
```

The probes print the contract version, the account count, the model count and
the state of the local gateway of the running host. The Flutter side uses the
same client through `lib/data/host/`.
