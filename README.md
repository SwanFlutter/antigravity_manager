# Antigravity Manager

A desktop application for Windows that manages the accounts of the AI coding
services, shows their quota and runs a local gateway so the coding tools can
use them through an API key.

The user interface is Flutter, the core is Rust. The two sides talk over a
private named pipe with a versioned JSON-RPC contract.

```
lib/          the Flutter application: the screens, the controllers and the client
rust/         the Rust workspace: the domain, the profile, the Google adapter
              and the local gateway
architecture/ the decision records of the project
test/         the widget tests and the golden screenshots of the screens
tool/         the diagnostics that talk to the running host
```

## Build and run

```powershell
flutter pub get
flutter build windows --debug
```

The build compiles the Rust host with cargo and places it next to the
application. The user interface starts the host when it is not running yet, so
the application always talks to the real profile instead of the sample data.

```powershell
cd rust
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
cargo test
```

## Connect an account

The accounts screen opens the authorization page of the provider in the browser
and stores the account with its credentials in the profile of the host. The
quota of the account is read from the provider and refreshed on demand.

The accounts of the sample data of a fresh profile are marked as `Sample`, so
a real account is never confused with them.

## The local gateway

The API proxy screen starts a gateway that speaks the OpenAI and the Anthropic
protocol and forwards the requests to the provider with the credentials of the
connected account. The key of the gateway is local, is stored in the profile
and has the format `sk-<32 hex>`.

```powershell
curl http://127.0.0.1:8045/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer YOUR_API_KEY" `
  -d '{"model": "gpt-5-1", "messages": [{"role": "user", "content": "Hello"}]}'
```

The default port is `8045`, the port of the upstream application as well, so
only one of the two can use it at the same time.

## Diagnostics

```powershell
dart run tool/ffi_probe.dart     # the state of the host
dart run tool/cloud_probe.dart    # the cloud flow: gateway, traffic and session
```

See [rust/README.md](rust/README.md) for the contract and
[architecture/](architecture) for the decisions behind it.
