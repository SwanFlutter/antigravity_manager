# Agent Note: Flutter and Rust Windows Replatform Roadmap

Status: proposed — the user selected a full Flutter and Rust rewrite for Windows; architecture contracts and migration evidence require review before implementation

Implementation note: the transport and the scope of the first delivery are
settled and implemented in
[2026-11-09-rust-core-decision-record.md](2026-11-09-rust-core-decision-record.md).
The Flutter UI is complete; the Rust core currently covers the accounts, the
quota and the SQLite profile.

## Problem

Antigravity Manager is currently an Electron desktop application with a React renderer, typed
preload/ORPC transport, SQLite and operating-system credential adapters, and an embedded
NestJS/Fastify proxy gateway. Its supported desktop releases currently include Windows, macOS,
and Linux. The existing app also has a standalone Node core and CLI that share profile ownership.

The user selected a complete replacement using Flutter for the Windows desktop UI and Rust for the
application core and gateway, with Windows as the target platform. Reimplementing only the visible
screens would omit account, credential, process, persistence, protocol, diagnostic, update, and
recovery behavior. A staged plan needs explicit parity, testability, data-compatibility, and
rollback gates before the old runtime can be retired.

This note records a proposed migration, not shipped behavior or approval to remove the existing
Electron application before the replacement passes the acceptance gates below.

## Proposal

Build a Windows desktop application with Flutter as the presentation layer and Rust as the
application/backend implementation, including a Rust replacement for the existing proxy gateway.
Preserve the product purpose, account-to-tool workflow, and feature inventory documented in
[PRODUCT.md](../../../../PRODUCT.md), while explicitly retiring macOS and Linux as target platforms
for this replacement. Do not remove or strand existing installations and user data until a
Windows-only release and recovery policy is approved.

Treat the current Signal Blue interface in [DESIGN.md](../../../../DESIGN.md) and current rendered
screens as evidence, not as the required final visual direction. Propose and approve a distinct
visual direction before creating Flutter UI or replacing the design contract.

Testability is a first-class architectural requirement. Keep domain behavior independent of Flutter,
Windows APIs, databases, network clients, and process execution. Put those dependencies behind
explicit interfaces/adapters, use deterministic fixtures for core tests, and exercise each native
or external boundary through a focused integration or Windows acceptance test.

### Proposed target architecture

The following is a starting architecture for a time-boxed technical spike, not a final choice of
IPC library, Rust web framework, or crate names:

```plaintext
Flutter Windows UI
    |
    | narrow, typed, versioned application contract
    v
Rust desktop host and application services
    |-- feature/domain services
    |-- SQLite repositories, codecs and migrations
    |-- Windows credential, file, process, startup and update adapters
    |-- Rust HTTP proxy gateway and protocol adapters
    `-- sanitized diagnostics and lifecycle management
```

- Flutter owns rendering, navigation, accessibility, localization, and presentation state. It
  calls application capabilities through narrow, typed interfaces; it does not access SQLite,
  credentials, arbitrary files, or processes directly.
- Rust owns domain rules, persistence, sensitive operations, external requests, process lifecycle,
  and gateway behavior. Pure application/domain services must be testable without launching
  Flutter or depending on Windows.
- Define one versioned contract source for commands, events, request/result shapes, and public
  errors. Generate or mechanically verify both Dart and Rust bindings where practical. Validate
  data at the process boundary; never trust generated types alone for untrusted serialized input.
- In Phase 0, compare Flutter-to-Rust FFI with a private local IPC transport against lifecycle,
  streaming, cancellation, Windows packaging, isolation, test-fixture, and failure-recovery
  requirements. Select and record one transport before production implementation.
- Keep the HTTP proxy gateway interface distinct from the private Flutter-to-Rust application
  contract. The gateway must bind and authenticate according to the existing public contract and
  must not expose administrative operations on its client-facing listener.
- Keep Rust crates/modules cohesive and feature-owned. An illustrative split is domain/application
  logic, Windows/platform adapters, persistence, gateway/protocol adapters, and desktop transport;
  final boundaries follow the architecture spike and actual tests, not this list verbatim.
- Use explicit application composition so unit tests can substitute clocks, HTTP clients, storage,
  process observation, and credential providers without weakening production validation.

### Confirmed scope and decisions still open

The following scope is confirmed for this proposal:

- Flutter is the Windows desktop UI.
- Rust replaces the application backend and the embedded Node/NestJS gateway.
- The new application targets Windows only.
- Existing user-facing features and important failure/recovery behavior require parity unless
  their removal is explicitly reviewed.
- Testability is a primary design goal, not a final-phase cleanup task.

The following decisions remain open and must be recorded before the corresponding implementation
begins:

- Flutter/Rust transport: FFI or private IPC, including versioning, permissions, streaming,
  cancellation, startup, shutdown, and recovery behavior.
- Rust gateway framework and composition with the desktop host, including binding, authentication,
  lifecycle isolation, and resource limits.
- Whether the Windows replacement reads the existing SQLite/profile formats directly or uses a
  versioned migration; exact backup, rollback, and downgrade behavior.
- Windows credential-provider mapping and how the existing OAuth-in-SQLite and other
  keyring/encrypted-storage contracts are preserved.
- Whether existing standalone-core and CLI commands are ported to Rust or explicitly retired.
- Minimum supported Windows versions/architectures, installer format, signing, update channel,
  and support policy for existing macOS/Linux users and releases.
- Locale inventory, including whether Persian/RTL is in scope; do not infer it from the current
  locale mismatch.
- The replacement visual direction and its approval.

### Testability design and evidence matrix

Testability means that each behavior can be run in isolation, has an observable result, and has a
credible check that fails when the behavior is broken. A passing test at one layer does not prove a
different native, process, package, or provider boundary.

| Layer                               | What it proves                                                                                  | Required seams and observables                                                                                                       | Negative control                                                                                                                      |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| Rust domain/application unit        | Business rules and state transitions without desktop or network startup                         | Injected clock, repositories, HTTP, process, and credential interfaces; assert complete result values, events, and partial effects   | Invalid state or failed dependency produces the specified error and does not report success                                           |
| Rust persistence/codec              | SQLite queries, schema validation, config codecs, and migration behavior                        | Temporary SQLite file/profile; inspect persisted rows, version, backup, and reopen result                                            | Corrupt/unsupported input or injected write failure is rejected without deleting the last recoverable copy                            |
| Rust adapter contract               | Windows-specific credential, filesystem, process, and network adapter behavior                  | Narrow adapter interfaces; sanitized isolated OS resources; verify actual calls and resulting state                                  | Permission denied, unavailable provider, malformed process observation, or occupied port fails closed                                 |
| Dart/Rust contract                  | Serialization, versioning, errors, events, cancellation, and generated binding consistency      | Contract fixtures run through both language bindings and the selected real transport                                                 | Wrong version, malformed payload, closed peer, and unknown error variant are rejected explicitly                                      |
| Rust gateway protocol               | HTTP endpoints, protocol mapping, streaming, usage, tool calls, errors, auth, and limits        | Start gateway on an isolated loopback port with synthetic adapters; inspect wire-level responses and event order                     | Invalid API key, malformed request, client disconnect, timeout, and bounded-body violations do not leak secrets or emit false success |
| Flutter unit/widget                 | Presentation state, accessibility semantics, navigation, and user interactions                  | Fake repositories/services; assert rendered accessible labels, actions, dialogs, state transitions, and focus                        | Read failure, cancellation, invalid input, and partial result show the correct state and retry/recovery action                        |
| Windows application integration     | Real Flutter-to-Rust startup, request/response transport, lifecycle, and process ownership      | Launch both built components against a dedicated temporary profile; observe UI, contract results, process exit, and cleanup          | Missing runtime, stale owner, concurrent owner, transport loss, and forced shutdown never mutate another profile                      |
| Packaged Windows acceptance         | Installed artifact behavior, signing/update integration, native dependencies, and profile paths | Install the exact candidate artifact on declared Windows versions/architectures; inspect version, signature, logs, and profile state | Interrupted install/update, invalid artifact, denied permissions, or rollback leaves the prior recoverable state usable               |
| Migration/recovery acceptance       | Existing Electron profile compatibility, backup, migration, downgrade, and restore              | Disposable copies of supported profile versions; compare pre/post logical state and verify reopening each supported version          | Interrupted, repeated, corrupt, and downgraded migrations are rejected or recovered without silent data loss                          |
| Authorized live-provider acceptance | Real OAuth, quota, client setup, gateway generation, and Traffic Monitor verification           | Dedicated authorized test account and client; verify identity, safe request result, and sanitized traffic record                     | Expired authorization, unavailable quota, provider rejection, and client configuration failure remain visible and recoverable         |

Use synthetic accounts and fixed HTTP fixtures by default. Keep provider tests opt-in and separate.
All tests that create profiles, database files, listeners, child processes, or installed artifacts
must own isolated locations, have bounded timeouts, expose readiness/completion, and clean up even
after failure.

The Windows CI gate should pin Rust and Flutter toolchains and run formatting, static analysis,
domain tests, codec/persistence tests, contract drift checks, Flutter unit/widget tests, and
Windows integration tests. Packaged, updater, credential-provider, and live-provider acceptance
must run in explicitly identified lanes; they are not replaced by mocks or counted as passing
when unavailable.

Do not use aggregate line-coverage percentage as sole proof. Every parity-matrix behavior must
link to an owning test or explicitly documented acceptance procedure, and each security,
migration, protocol, and partial-failure boundary must include a representative rejection or
failure-path check.

### Existing surface inventory

#### Application shell

- Provide navigation for Accounts, Workspaces, API Proxy, Playground, Traffic, and Settings.
- Keep expanded and collapsed sidebar behavior, selected-route indication, keyboard navigation,
  tooltips where labels are hidden, and persistence of the collapsed preference.
- Retain the service-status area for Antigravity Classic and Antigravity IDE, including loading,
  running, stopped, pending, start, stop, and operation-error states.
- Define consistent page headers, content widths, scrolling, dialogs, toasts, error boundaries,
  and window-size behavior.
- Keep light and dark themes complete, including semantic success, warning, information, and
  destructive states.

#### Standalone service and CLI

- Inventory and decide the fate of the existing standalone core and CLI, including service
  status/start/stop and account login commands.
- Preserve shared-profile ownership between desktop and service processes, readiness and shutdown
  semantics, safe account summaries, and credential-free process arguments.
- If CLI behavior is retained, provide a Rust-owned command-line entry point or an explicitly
  reviewed alternative; do not leave it dependent on a removed Node core or silently drop it.

#### Accounts

- Support account authorization, add-account, import from local account data, file import,
  export, and the existing confirmation and error flows.
- Show account totals and useful aggregate status, including active, rate-limited, and quota
  summaries where available.
- Present account identity, provider/tier information, client status, quota windows, and account
  actions without exposing credentials.
- Retain quota refresh, automatic client-account switching, manual account switching, account
  recommendations, selection, batch operations, and deletion.
- Retain tier filtering, sorting, quota-window selection, quota-group visibility, minimal mode,
  and the supported account grid/list layouts.
- Design loading, refresh-in-progress, empty, no-filter-results, stale or unavailable quota,
  account error, rate-limited, and confirmation states.

#### Workspaces

- List and search workspace profiles by name, project path, or bound account.
- Create and edit a profile with its name, Google account, project folder, and isolated user-data
  directory information.
- Show running, idle, unknown, and unavailable status distinctly.
- Support launch, stop, copy-path, edit, refresh, and delete actions.
- Explain the existing restart warning when changing an account or project for a running
  workspace. Preserve the explicit choice to remove workspace login and session data on deletion.
- Design first-use, no-accounts, empty-list, no-search-results, loading, failure, busy, and
  destructive-confirmation states.

#### API Proxy

- Make local proxy service state, start/stop control, local address, configured port, request
  timeout, and applicable network-address selection easy to understand.
- Keep API keys masked by default. Preserve reveal, copy, regenerate, and the existing
  regeneration confirmation.
- Retain the first-use proxy risk acknowledgement and make its consequence clear before service
  startup.
- Preserve account-selection and routing strategy controls, automatic startup, and all current
  gateway configuration options.
- Keep the Tools, Models, Records, and Examples areas:
  - Claude Code, Codex, and OpenCode configuration cards, installation detection, configuration
    status, saved-versus-verified distinction, view/update/remove actions, and backup recovery.
  - Model visibility and Anthropic model mapping controls, including restore-default behavior.
  - Request audit and thought-storage controls and their retention implications.
  - OpenAI-compatible, Anthropic, and other currently supported examples and protocol selection.
- Preserve global system-prompt, audit, thought diagnostics, and OpenCode-specific configuration
  surfaces where currently available.
- Design service unavailable, port conflict, invalid configuration, configuration-read failure,
  not-installed, saved-but-unverified, running, stopped, and recovery states.

#### Playground

- Keep Single, Compare, Benchmark, and Dual modes.
- Retain account and model selection, the visible-model filter, prompt and system prompt, and the
  current request parameters such as temperature, token limit, and reasoning effort.
- Make gateway connectivity and the existing startup/risk-confirmation path visible.
- Show request progress, cancellation, per-account comparison results, benchmark outcomes, and
  actionable failures without implying that a configured model or account guarantees upstream
  availability.
- Design empty-input, no-account, no-model, gateway-offline, running, cancelled, partial-result,
  success, and request-error states.

#### Traffic Monitor

- Keep the Model requests, Other requests, App actions, and System events categories.
- Retain account, model-family, modality, status, date-range, and free-text search filters, as
  applicable to each category.
- Present the existing paginated request data with readable model, account, token, output, result,
  duration, and service-address information.
- Preserve record count, storage usage, dropped-record indicators, refresh, request-detail
  inspection, and clear-category confirmation.
- Keep cURL copying behavior, including the explicit opt-in involved when copied output can
  include credentials.
- Design empty results, loading, filtering, storage/dropped-record warnings, unavailable details,
  copy success/failure, pagination boundaries, and clear confirmation.

#### Settings

- Keep General, Models, and Proxy sections and all currently implemented settings:
  - Appearance: light/dark theme and language.
  - Accounts: automatic quota refresh, account synchronization, and client executable paths for
    Antigravity IDE, Antigravity Classic, and agy CLI, including detection and browse/clear
    actions.
  - Startup: launch at system startup and start in tray, with existing platform-specific behavior.
  - Antigravity cache controls.
  - About: application version, platform, license, update check, and log-directory access.
  - Privacy and reporting: error reporting, telemetry, Clarity availability, and restart guidance.
  - Notifications: quota alerts and their threshold and policy controls.
  - Models: model visibility, automatic model-switch settings, and weekly warmup settings.
  - Proxy: gateway port, automatic start, upstream proxy, and existing experimental options.
- Retain disabled/unavailable settings behavior, persistence feedback, retry paths, and platform
  conditions.
- Design saved, saving, invalid, unavailable, restart-required, permission-limited, and update
  states.

#### Shared dialogs and feedback

Include every dialog and global feedback flow encountered in the current routes and feature
modules, including account authorization/login, local account import, import/export file handling,
identity-profile editing, workspace create/edit/delete, proxy risk acknowledgement, API-key
regeneration, traffic details, release notes, update notifications, and diagnostic-log attachment.
Keep cancellation, focus return, keyboard behavior, clear destructive consequences, and
localized errors consistent.

### Phased migration roadmap

#### Phase 0 — Baseline, parity inventory, and design approval

1. Inventory all current routes, feature services, IPC/ORPC operations, gateway endpoints,
   persistence formats, client integrations, standalone-core/CLI commands, dialogs, settings,
   process operations, diagnostics, update flows, and platform-specific behavior. Use the existing
   module references linked from
   [the module index](../../../../docs/modules/README.md).
2. Convert the UI inventory above into a feature-parity matrix. For each behavior record its
   current input, observable result, failure/partial-effect behavior, persistent state, owner, and
   current test/acceptance evidence.
3. Capture sanitized, deterministic compatibility fixtures from representative current behavior
   and published protocol expectations. Do not treat fixtures copied from implementation as
   independent proof of external protocol compatibility.
4. Approve the new visual direction and Flutter first-use workflow before building pages. Record
   final design decisions in the owning design artifacts after approval.
5. Record the confirmed Windows-only target; decide supported Windows versions and architectures,
   update channel, signing/installer expectations, and policy for existing macOS/Linux releases and
   users.
6. Resolve the current locale documentation mismatch: the renderer currently lists `en`, `zh-CN`,
   `ru`, `vi`, `tr`, `fr`, and `pt-BR`, while [PRODUCT.md](../../../../PRODUCT.md) describes fewer
   languages. Confirm which locales ship in the Windows replacement.

**Exit criteria:** approved migration and release scope; complete parity and risk inventories;
baseline evidence owners identified; open decisions about data compatibility, transport, Windows
support, and release transition explicitly tracked.

#### Phase 1 — Testability architecture spike and migration design

1. Create a minimal Flutter Windows host and Rust service/core spike without connecting real
   accounts or modifying a user's profile.
2. Compare FFI and private IPC for typed contract generation, process ownership, streaming,
   cancellation, startup/shutdown, error propagation, Windows packaging, isolation in tests, and
   recovery from either side exiting unexpectedly.
3. Define test seams: Rust domain/application interfaces for time, HTTP, persistence, credentials,
   process observation and filesystem operations; Flutter interfaces for repositories, navigation
   and platform interactions.
4. Define the contract versioning and compatibility policy for Dart/Rust calls, events, public
   errors, and the HTTP gateway.
5. Produce a data/profile compatibility plan. Inventory current profile paths, SQLite databases,
   schemas, config payloads, backups, OAuth data, keyring entries, client configuration, and
   workspace state. Specify backup, migration, interruption recovery, downgrade, and single-owner
   rules before a migration implementation.
6. Define test harnesses and CI prerequisites for Rust and Flutter on Windows, including pinned
   toolchains, deterministic test profiles, fixture locations, artifact retention, and cleanup.

**Exit criteria:** reviewed architecture and protocol decisions; executable spike demonstrates
unit-test substitution and a real Flutter-to-Rust round trip; migration/recovery design has an
independently reviewable compatibility matrix; no test requires production credentials or shared
user state.

#### Phase 2 — Rust domain, persistence, credentials, and runtime parity

1. Implement independently testable Rust domain/application services for accounts, quota,
   configuration, account selection, workspaces, client switching, cache/settings operations,
   diagnostics, and any approved CLI/service operations, following the parity matrix.
2. Implement Windows adapters for SQLite, filesystem access, OS credential storage, OAuth
   callback handling, process observation/launch/shutdown, file selection, startup/tray, and
   update integration as owned boundaries.
3. Preserve the current account and workspace behavior, including partial completion, uncertain
   process observations, confirmed shutdown/startup, cancellation and actionable errors.
4. Keep current data and credential policies unless a separately reviewed migration changes them.
   Cloud OAuth tokens currently exist as plaintext JSON in the local SQLite profile; other
   credentials use their existing keyring/encrypted-storage policy. Never emit real values in
   logs, IPC, fixtures, or diagnostics.
5. Implement explicit profile ownership so the replacement and legacy application cannot
   concurrently mutate the same profile. Test busy-owner, stale-owner and unexpected-shutdown
   recovery.
6. For any required durable-format change, add versioned migrations, pre-migration backup,
   interruption-safe execution, validation, rollback/downgrade policy, and tests for corrupt,
   unsupported, unavailable, and partially migrated data. Do not silently fall back to empty data.

**Exit criteria:** feature services pass deterministic unit tests; each Windows adapter has
boundary-focused tests; persistence and credentials pass compatibility and failure/recovery
tests; no concurrent runtime can claim one profile; parity rows are backed by observable evidence.

#### Phase 3 — Rust gateway and protocol compatibility

1. Reimplement the current local gateway lifecycle and Windows loopback/network binding behavior
   in Rust with an explicit authenticated client-facing boundary and separate private management
   contract.
2. Port and verify currently supported OpenAI, Anthropic, and Gemini interfaces, including model
   discovery/mapping, request/response conversion, streaming event order, tool calls, usage
   accounting, errors, retries, cancellation, account selection, and supported media/thought
   behavior.
3. Port audit and thought storage, retention controls, coding-tool configuration for Claude Code,
   Codex and OpenCode, model examples, and Playground execution according to the existing feature
   and security references.
4. Run old/new differential tests on sanitized fixtures where meaningful. Add independent
   protocol vectors and malformed/untrusted-input tests; do not make a passing mock the only
   evidence for streaming or real HTTP boundaries.
5. Verify the gateway is not exposed before authentication/configuration is ready, rejects invalid
   credentials, bounds bodies/timeouts/storage, redacts secrets, and shuts down without losing
   admitted-operation state.

**Exit criteria:** all required compatibility-matrix entries pass unit and gateway integration
tests; streaming, cancellation, error envelopes and account-routing decisions match the approved
contract; Windows localhost exposure and authentication have real-process evidence.

#### Phase 4 — Flutter design system and application shell

1. Implement approved theme tokens, typography, navigation, page frames, responsive layouts,
   accessible controls, dialogs, notifications, and shared loading/empty/error states.
2. Provide dependency-injected feature repositories/state controllers so Flutter widget tests can
   drive success, loading, empty, retry, cancellation, validation, and partial-result states
   without launching the Rust runtime.
3. Provide localization for the approved language set, long translated content, RTL readiness if
   Persian/Arabic is added, keyboard operation, visible focus, screen-reader semantics, and
   reduced motion.
4. Add stable component/widget tests and selected golden tests for shared primitives and key
   page states. Golden tests supplement behavior assertions; they do not replace them.

**Exit criteria:** the full route/navigation skeleton works with fake repositories; tests cover both
themes, narrow and desktop windows, keyboard flows, localization overflow and shared feedback
states; the visual direction is approved.

#### Phase 5 — Feature parity in Flutter

Implement all feature surfaces in this order, without changing their domain contracts:

1. **Accounts and first-use workflow:** authorization, add/import/export/local import, quota,
   filtering/sorting/layouts, manual/automatic switching, selection/batch operations, privacy,
   errors and recovery.
2. **API Proxy and coding tools:** service control, local address, port/timeout, protected key
   actions, risk acknowledgement, account strategy, tools, models, records, examples, backup and
   restore.
3. **Traffic Monitor:** all request/event categories, filters, search, pagination, details,
   storage/dropped-record states, credential-aware cURL copy, clear confirmation and retries.
4. **Playground:** Single, Compare, Benchmark and Dual modes; request controls, gateway state,
   progress, cancellation, partial/success/error results.
5. **Workspaces and process controls:** profile CRUD, account/project binding, isolated state,
   process status, launch/stop, restart warning, deletion and cleanup recovery.
6. **Settings and secondary dialogs:** general/models/proxy settings, executable paths, startup,
   cache, updates, notifications, privacy, diagnostic attachments, release notes and every
   existing shared confirmation flow.

**Exit criteria:** every route and user action in the parity matrix has a Flutter implementation
and a passing widget/contract test; high-impact flows have integration evidence; no feature is
removed as an incidental layout simplification.

#### Phase 6 — Windows end-to-end, native, packaged, and recovery acceptance

1. Run isolated Windows application integration tests using temporary profile/database roots and
   synthetic accounts. Verify the actual Flutter-to-Rust boundary and the built gateway process.
2. Run native Windows acceptance for credential providers, SQLite/WAL behavior, file dialogs,
   process-tree observation, client switching and workspace isolation, startup/tray, network
   binding, installer, signing, update and uninstall behavior as applicable.
3. Exercise the first-use path with an authorized test account: add account, refresh/inspect
   quota, configure one tool, reopen it, send a small request, and observe it in Traffic Monitor.
   Never include production credentials or private payloads in reports.
4. Test migration from supported existing Electron profile versions using disposable backups.
   Include interrupted migration, corrupt database/config, unavailable credential source,
   insufficient permissions, downgrade, and recovery/restore cases.
5. Verify installer upgrade, clean installation, update integrity, rollback instructions, and that
   an interrupted or failed replacement never deletes the last recoverable profile.

**Exit criteria:** all Windows-native and packaged acceptance tests pass on the declared Windows
versions/architectures; live-provider checks pass where authorized; migration and recovery are
demonstrated on disposable profiles; unresolved platform or provider limits are documented.

#### Phase 7 — Controlled Windows release and legacy retirement

1. Ship the Flutter/Rust Windows build only after all previous exit criteria pass and the
   installation, signing, update, support and data-recovery policy is approved.
2. Keep the existing Electron releases and their supported platform policy intact until users of
   those builds have a documented support path. Do not describe the new Windows-only build as a
   replacement for macOS/Linux.
3. Observe sanitized migration failures and user-visible diagnostics through the existing privacy
   policy; provide a safe retry/restore path.
4. Remove Electron, React, Node-core, and NestJS gateway implementation only in a separately
   reviewed change after the replacement is established and historical profile recovery is
   accounted for.

**Exit criteria:** approved Windows support and migration policy is published; rollback does not
depend on deleting or manually reconstructing user data; legacy retirement has a separate
authorization and evidence review.

### Non-goals

- Do not add provider guarantees, endorsements, performance claims, or upstream-availability
  claims as part of the migration.
- Do not change account-selection policy, proxy protocol semantics, data-retention semantics, or
  credential exposure policy merely to simplify the rewrite.
- Do not silently drop current features, stored data, client configuration, or recovery behavior.
- Do not allow Flutter presentation code to become the authority for security-sensitive decisions.
- Do not use production account data, credentials, private request bodies, or unredacted logs in
  committed tests, golden images, screenshots, or diagnostics.
- Do not make macOS or Linux support commitments for the new Flutter/Rust application. Do not
  retire those platforms' existing releases until a separate support and user-migration decision
  is approved.
- Do not switch production users to the replacement or remove the Electron/Node implementation
  before migration, packaged Windows acceptance, and rollback criteria pass.
- Do not treat screenshots in `docs/assets/` as a complete or necessarily current behavior
  inventory.

### Implementation and evidence expectations

- Follow the repository's [root instructions](../../../../AGENTS.md), relevant deeper `AGENTS.md`
  files, [architecture](../../../../docs/architecture.md), [security](../../../../docs/security.md),
  [testing strategy](../../../../docs/testing.md),
  [desktop-interface guidance](../../../../docs/modules/app-shell/desktop-interface.md),
  [desktop testing guidance](../../../../docs/modules/app-shell/testing.md), and feature-owned
  module references. These documents describe the Electron/Node system being replaced; update
  their current-behavior claims only when the corresponding replacement is implemented and
  verified.
- Keep Flutter presentation, Rust domain/application logic, Windows adapters, and gateway
  responsibilities separate. UI widgets do not directly own persistence, credentials, raw
  process execution, or protocol behavior.
- Use a versioned, narrow Dart/Rust contract and validate runtime input at every serialized
  process, file, database, HTTP, or external-client boundary.
- Use test-only temporary profiles and deterministic fakes. Real-account, native Windows,
  packaged-installer, and provider evidence are separate evidence classes and must not be inferred
  from unit or mock tests.
- For each changed behavior, record its trigger, observable acceptance result, current behavior
  to preserve, test entry point, substituted boundaries, and a negative control where practical,
  following the
  [behavioral evidence contract](../../../../docs/testing.md#behavioral-evidence-contract).
- Build a migration matrix from the exact profile formats and credential owners. Use transactional
  or otherwise interruption-safe migrations, backups, explicit error reporting, and independently
  verified restore/downgrade procedures. Never delete or overwrite the only recoverable source.
- Proposed Rust/Flutter commands in this note are not current repository scripts. Add and document
  owned commands only after the toolchain and test harness are selected; do not report proposed
  checks as executed evidence.
- Update current architecture, security, testing, development, module, and upgrade documentation
  in the same changes that ship their new behavior. Keep this note proposed until decisions are
  reviewed; record shipped decisions and verification in an implemented note.

## Alternatives considered

- **Keep Electron/React and only refresh the UI:** rejected for this roadmap because the user
  selected Flutter and Rust, and UI-only changes do not achieve that platform rewrite.
- **Keep the NestJS/Fastify gateway permanently:** rejected because the user selected a full rewrite
  including the gateway; retain the old gateway only as a temporary compatibility/test oracle
  during migration.
- **Rewrite without a parity or migration phase:** rejected because existing behavior, user
  profiles, credentials, client files, and proxy protocol compatibility could be lost.
- **Retire macOS/Linux releases with the first Windows build:** not selected. The new application
  is Windows-only, but existing supported installations need a separately approved support and
  data-recovery policy.
- **Make Flutter widgets call platform APIs and storage directly:** rejected because it couples
  UI tests to native state and widens sensitive boundaries.
- **Use only mocked tests:** rejected because mocks do not establish Windows credential, process,
  installer, migration, network, or provider behavior.

## Acceptance criteria

- The shipped Windows application uses Flutter for UI and Rust for core services and proxy
  gateway; Electron/React/Node/NestJS are not required at runtime after separately approved legacy
  retirement.
- Every existing route, feature, important dialog, status, failure mode, confirmation, and recovery
  behavior in the parity matrix is implemented or explicitly approved as removed.
- Existing standalone-core and CLI behavior is preserved or explicitly reviewed and approved for
  retirement; desktop and service runtimes retain safe single-owner profile semantics.
- A new user can add an account, inspect quota, connect a supported coding tool, reopen it, send a
  request, and verify that request in Traffic Monitor.
- Existing supported profile data, account and workspace state, client configuration, and
  recoverable credentials survive the documented migration, or a reviewed explicit rejection
  leaves the original installation usable and data intact.
- Migration is idempotent or safely refuses a repeat; interrupted, corrupt, unsupported,
  permission-denied, and rollback cases produce clear observable results without success-shaped
  fallbacks or loss of the last recoverable copy.
- Only one app runtime can mutate a profile at a time; shutdown, crash, stale lock, and restart
  recovery are covered.
- All public gateway protocols preserve the approved compatibility behavior for requests,
  streaming, tools, usage, errors, retries, cancellation, routing, storage, and authentication.
- Rust domain/application tests run without Windows or Flutter dependencies; Windows adapters,
  Flutter presentation, Dart/Rust contracts, gateway integration, process lifecycle, migration,
  and packaged delivery each have their own focused test suites.
- CI exercises pinned Rust and Flutter toolchains on Windows and provides deterministic,
  isolated, repeatable test results. Unit, contract, integration, native, packaged, and live
  results are reported separately.
- Both themes, the approved locale set, keyboard and screen-reader access, focus return,
  responsive desktop-window layouts, and error/empty/loading/busy states are verified.
- Credentials remain absent from logs, fixtures, reports, golden images, IPC traces, and ordinary
  diagnostics. Existing keyring/encrypted storage policies remain intact unless a separately
  reviewed migration proves equivalent or stronger protection.
- The Windows-only product target is explicit, and existing macOS/Linux release support is not
  silently represented as migrated or retired.

## Risks

- Reimplementing authentication, quota, process switching, workspace isolation, OAuth callbacks,
  credential adapters, and updater behavior can create data loss or account-control failures even
  when the Flutter UI appears correct.
- SQLite migration, WAL handling, config normalization, OS credential APIs, file permissions, and
  client-owned files have platform-specific behavior; format compatibility cannot be assumed from
  source-level model similarity.
- Reimplementing a mature streaming gateway can change event ordering, protocol errors, retries,
  tool calls, usage accounting, cancellation, or durable response semantics.
- FFI can make process lifecycle and streaming harder to isolate; IPC can add serialization,
  versioning, startup, access-control, and shutdown failure modes. The Phase 1 spike must resolve
  this with measured acceptance evidence.
- The current codebase already has a standalone core, local RPC, profile ownership, and shared
  adapters. Ignoring those designs could duplicate proven lifecycle rules or create competing
  owners during migration.
- Mock-only confidence can overstate security or compatibility. Windows process, keyring,
  installer, updater, loopback listener, and live-provider evidence needs real boundary checks.
- A new Windows-only build may be confused with the current cross-platform product. Release
  naming, support, update channels, and macOS/Linux migration policy need explicit communication.
- An interrupted conversion can strand a user's profile or break downgrade. Keep backups until
  restore is tested and migration success is independently verified.
- CI needs Windows capacity, pinned Rust/Flutter SDKs, and native build prerequisites; flaky
  timing-sensitive UI or process tests can erode confidence unless isolated and observable.
- The locale inventory in code and PRODUCT.md differs; language support and RTL expectations need
  an explicit decision before localization parity is declared.
- A large rewrite can appear complete while edge-case behaviors are missing. Every phase is gated
  by observable parity evidence, not by percentage of screens ported.
