# Decision record: the Rust core and its transport

Status: implemented — the vertical slice (accounts, quota, SQLite) is running
end to end between the Flutter UI and the Rust host. The second delivery (the
Google connection, the real quota and the local API gateway) is running as
well; see the sections below.

This note records the decisions the roadmap
[2026-11-07-flutter-rust-windows-replatform.md](2026-11-07-flutter-rust-windows-replatform.md)
requires to be settled before the core is written: how the Flutter UI talks to
the Rust core, and what the first delivery contains.

## Decisions

### 1. The transport is a private named pipe with a versioned JSON-RPC contract

The Flutter UI and the Rust core talk over the Windows named pipe
`\\.\pipe\antigravity-manager-host`.

Alternatives that were rejected:

| Alternative | Why it was rejected |
| --- | --- |
| FFI (Dart ↔ Rust through the C ABI) | Couples the release of the UI to the release of the core, keeps the domain rules on the Dart side of the boundary and makes a crash in the core crash the UI |
| A local TCP or WebSocket port | Reachable from the network, needs a port policy and a firewall story, and is not private to the machine |
| stdin/stdout of a child process | Works, but it ties the UI to the lifetime of one process and offers no way for a second client to share the profile |
| A shared file plus file watching | No request/response semantics, no versioned contract, and it invites half written state |

Why the named pipe wins here:

- it stays on the machine and is not exposed to the network;
- the profile has a single owner (the host), so several clients can share it;
- the host can be restarted independently of the UI;
- the boundary is a real process boundary, so it can be tested with an
  integration test that starts the listener and connects a real client.

Framing: every frame is a four byte little endian length followed by the UTF-8
JSON payload. The pipe runs in byte mode, so the framing does not depend on
the message mode of the pipe. The largest accepted frame is 8 MiB.

The contract is JSON-RPC 2.0 with a version, `CONTRACT_VERSION = 1`. The Dart
side refuses a host that reports another version, and both sides validate the
payload they receive instead of trusting the peer.

### 2. The first delivery is a vertical slice: accounts, quota and SQLite

The slice contains the account pool, the quota windows (the five hour windows
per model and the weekly allowance per model group) and the profile on disk.
It contains the read and write operations the account screen needs, the model
catalog and the host information.

It does not contain the proxy gateway, the workspaces, the traffic log, the
authentication flow or the updater. Those follow the same pattern once the
first slice is accepted.

### 3. The domain lives in Rust and stays free of the operating system

`rust/crates/core` has no Flutter, Windows or network dependency. Every
outside dependency is a trait (`AccountRepository`, `QuotaProvider`, `Clock`)
with a deterministic fake, so the rules are tested without a database, a
network or an operating system.

The crate layout:

| Crate | Responsibility |
| --- | --- |
| `antigravity-contract` | The versioned contract: DTOs, method names, stable error codes |
| `antigravity-core` | Domain, SQLite repository, service, mapping, fakes, demo dataset |
| `antigravity-host` | The named pipe listener, the framing and the JSON-RPC dispatch |

### 4. The profile is owned by the host, versioned and transactional

The profile lives in `%APPDATA%\AntigravityManager\profile.sqlite3`. The host
owns it; the UI only reads and writes through the contract. The schema is
versioned through `schema_version`, every migration runs inside a transaction,
and a profile written by a newer build is refused instead of being downgraded.

### 5. The UI keeps working while the host is not running

The Dart side uses `HostAccountsRepository`. When the host cannot be reached,
the repository falls back to the in-process fake, so the interface, the widget
tests and the golden tests never depend on a running Rust process. The
repository also reports whether the data came from the live host.

The demo dataset of the Rust core reproduces the values of the Flutter
prototype with a deterministic generator, so the switch between the fake and
the host does not change what is on screen.

The tests take the fake on purpose: `defaultAccountsRepository()` returns the
in-process fake when the process runs under `FLUTTER_TEST`. A host that
happens to run on the machine would otherwise change the golden files of the
screens from one machine to another.

### 6. The Google adapter and the gateway are separate crates

The second delivery added two crates next to the core:

| Crate | Responsibility |
| --- | --- |
| `antigravity-google` | The adapter of the Google OAuth and Cloud Code endpoints, including the `Generator` trait of the generation |
| `antigravity-proxy` | The local gateway: the OpenAI and Anthropic compatible endpoints, the translation of the protocols and the streaming |

The gateway talks to the provider through the `Generator` trait, so it can be
tested against a fake generator without touching the network. The translation
between the protocols of the coding tools and the internal protocol of Google
is a pure function in `antigravity-proxy/src/convert.rs`, so it is tested
without a socket as well.

The key of the gateway is local, has the format `sk-<32 hex>` and is stored
in the profile. Without a key the gateway accepts every request and stays on
the loopback interface; with a key it listens on every interface. The default
port is `8045`, the port of the upstream application as well, so only one of
the two can use it at the same time.

### 7. The live configuration of the gateway is shared, not copied

The running gateway holds the configuration of the proxy, and the host holds
the same lock. A key that is rotated therefore takes effect on the running
gateway at once, without a restart of the process. The gateway is restarted
only when the bind address has to change, because a gateway with a key listens
on every interface and a gateway without a key stays on the loopback.

## Evidence

| Check | Command | Result |
| --- | --- | --- |
| Domain and persistence | `cargo test` in `rust/` | 15 tests pass (5 domain, 8 persistence, 2 pipe) |
| The transport between two processes | `rust/crates/host/tests/pipe_contract.rs` | The real listener answers a real client over the pipe; an unknown method is rejected with `-32601` |
| The UI against the running host | `dart run tool/ffi_probe.dart` | Contract version 1, 4 accounts, 31 models and the summary counters |
| The parity of the demo data | `the_demo_dataset_matches_the_flutter_prototype` and `the mock repository reports the same summary as the domain rules` | Both sides report `globalRemaining = 0.3905095967741935`, so the interface looks the same with and without a running host |
| The Dart side of the contract | `flutter test test/accounts_repository_test.dart` | 9 tests pass: the mapping, the fallback, the version refusal, the write operations, the session, the proxy state and the traffic log |
| The whole Flutter suite | `flutter test` | 22 tests pass, including the golden screenshots |
| Static analysis | `flutter analyze --no-pub` | No issues found |

### The evidence of the second delivery

| Check | Command | Result |
| --- | --- | --- |
| The whole Rust workspace | `cargo test --workspace` in `rust/` | 49 tests pass (5 domain, 8 persistence, 20 Google, 7 gateway unit, 7 gateway integration, 3 pipe and cloud contract) |
| The gateway against a real socket | `rust/crates/proxy/tests/gateway.rs` | The routing, the key guard, the OpenAI and the Anthropic protocol, the streaming and the traffic log are covered against a fake provider |
| The contract of the cloud methods | `rust/crates/host/tests/cloud_contract.rs` | The names of the parameters and of the answers of the cloud methods are the ones the Flutter client sends, and the gateway of the host answers on the port it announced |
| The cloud flow against the running host | `dart run tool/cloud_probe.dart` | The gateway starts on its port, the traffic log is filled, the OAuth session opens the loopback listener and the authorization URL carries the client and the scopes of the upstream application |
| The key guard of the running gateway | A request without a key and a request with a wrong key | Both are refused with `401` |
| The build of the application | `flutter build windows --debug` | The Rust host is compiled by the build and placed next to the application; the launcher of the UI starts it |

## What is still open

- The remaining modules of the roadmap: the workspaces, the thought store, the
  configuration of the agent tools and the updater.
- The shipping of the host with the installer.
- The end to end test with a real Google account. Google may refuse the
  redirect of the built-in client of the upstream application; the manual code
  path is implemented for that case, but neither path can be verified without
  an account of the user.
