# نقشه‌ی پروژه‌ی upstream: AntigravityManager

مسیر مرجع: `G:\AI\AntigravityManager` (کلون محلی مخزن `Draculabo/AntigravityManager`)

این سند، مرجع رفتاریِ پیاده‌سازی ماست: اپ Flutter+Rust ما (`G:\Windows\antigravity_manager`)
قابلیت‌های خود را از این پروژه الگو گرفته است. اینجا فهرست می‌شود که پروژه‌ی upstream
**واقعاً چه چیزی دارد** — بر پایه‌ی خواندن مستقیم فایل‌ها، نه حدس.

> این سند فقط **توصیف** است؛ در پروژه‌ی upstream هیچ فایلی تغییر نکرد.

---

## ۱. نمای کلی

| مورد | مقدار |
| --- | --- |
| نام / نسخه | `antigravity-manager` / **0.29.0** |
| نوع | اپ دسکتاپ **Electron 37** + **React 19** + **TypeScript** + **NestJS/Fastify** |
| ساخت | `electron-forge` + `electron-builder` + `vite` (۶ کانفیگ جدا) |
| لایسنس | CC-BY-NC-SA-4.0 |
| Node / pnpm | `>=24.22.0 <25` / `10.34.6` |
| اندازه | `src` = ۱۳۴۶ فایل · `docs` = ۷۰ · `scripts` = ۲۰۲ · `openspec` = ۲۸ |

پروژه **سه‌گانه‌ی runtime** دارد که برای ما مهم است:

| بخش | مسیر | نقش |
| --- | --- | --- |
| دسکتاپ | `src/main` (implicit) | پنجره، IPC، به‌روزرسانی، گیت‌وی |
| **Core مستقل** | `src/core` | runtime جدا از Electron؛ RPC/مدیریت؛ workerهای ممیزی و thought-store |
| **CLI** | `src/cli` | همان قابلیت‌ها بدون Electron (مدیریت حساب، ابزارهای agent) |

کانفیگ‌های Vite: `main`, `preload`, `renderer`, `core`, `cli`, `worker`.

---

## ۲. راه‌اندازی و اسکریپت‌های مهم

```powershell
pnpm start          # electron-forge start
pnpm test           # vitest run  (فقط src/tests/unit)
pnpm run test:e2e   # playwright
pnpm run lint / format / type-check
pnpm run check:ci  # governance + static + quality
pnpm run make       # build بسته‌های نصب
pnpm run verify:boundaries   # بررسی مرزهای runtime
```

اسکریپت‌های کنترل کیفیتِ اختصاصی: `check:agent-contracts`، `check:change-scope`،
`verify:boundaries`، `verify:type-boundaries`، `analyze:imports`، `review:eval`،
`audit:size:win32:x64`.

---

## ۳. معماری و مرزهای runtime

- `src/server` فقط **bootstrap/lifecycle** دارد (۳ فایل): `main.ts`، `app.module.ts`، `server-config.ts`.
  طبق `AGENTS.md` هر منطق دامنه‌ای باید در `src/modules` باشد، نه در `src/server`.
- `src/ipc` — لایه‌ی IPC دسکتاپ: `router.ts`، `admission.ts`، `context.ts`، `manager.ts`.
- `src/core` — runtime مستقل Node + لایه‌ی `rpc/` و `management/` برای گفت‌وگو با دسکتاپ.
- `src/shared` — ۶۱ فایل مشترک: `persistence/`، `security/`، `observability/`، `logging/`، `http/`، `packaging/`.

مستند مرجع معماری: `docs/architecture.md`.

---

## ۴. نقشه‌ی ماژول‌ها (`src/modules`)

| ماژول | فایل | محتوا |
| --- | --- | --- |
| `proxy-gateway` | ۳۱۷ | **هسته‌ی گیت‌وی**: سرور، mapperها، ممیزی ترافیک، playground، thought-store، ابزارهای agent |
| `cloud-account` | ۱۵۳ | **حساب‌های ابری گوگل**: OAuth، quota، پایش، تعویض حساب، warmup هفتگی |
| `app-shell` | ۶۸ | پوسته‌ی دسکتاپ: مسیرها، تم، زبان، به‌روزرسانی، لاگ تشخیصی |
| `antigravity-runtime` | ۵۴ | اجرای اپ Antigravity، سوییچ داغ حساب، ذخیره‌ی credential، patch باینری |
| `account` | ۲۰ | حساب‌های محلی IDE، ایندکس، بکاپ، پایگاه‌داده‌ی state |
| `config` | ۱۶ | تنظیمات سرویس، alias مدل‌ها، پروکسی upstream، گزارش خطا |
| `workspace` | ۱۶ | پروفایل workspace، اشتراک فایل/gemini/history |
| `identity-profile` | ۵ | دیالوگ identity profile |

سایر زیرپوشه‌های `src`: `assets` (فونت‌ها)، `cli`، `components` (۲۷، مبتنی بر Radix)، `core` (۲۰)، `ipc` (۶)، `localization` (۸)، `mocks` (۶)، `routes` (۷، TanStack Router)، `server` (۳)، `shared` (۶۱)، `styles`، `tests` (۵۳۶).

---

## ۵. سرور گیت‌وی — قلب پروژه

### ۵.۱ پروتکل‌ها

سه خانواده‌ی پروتکل ورودی + یک سطح تشخیصی اختیاری:

- **OpenAI** — Chat Completions، Completions، Responses (+ WebSocket)، Images، Audio، Uploads، Models
- **Anthropic** — Messages، count_tokens، complete، Files، Batches
- **Gemini بومی** — `/v1beta/models/...`، generateContent/streamGenerateContent، countTokens، files، batches
- **v1internal passthrough** — فقط با `AGM_V1INTERNAL_PASSTHROUGH=1` **قبل** از استارت پروکسی

### ۵.۲ endpointها

| Controller | Base | مسیرها |
| --- | --- | --- |
| openai-chat | `v1` | `POST chat/completions`، `GET chat/completions/:id`، `POST completions` |
| openai-models | `v1/models` | `GET /`، `GET /:model` |
| openai-media | `v1` | `POST images/generations`، `POST images/edits`، `POST audio/transcriptions`، `POST audio/translations` |
| openai-responses | `v1/responses` | `POST /`، `GET :id`، `DELETE :id` |
| anthropic | `v1` | `POST messages`، `POST messages/count_tokens` |
| anthropic-complete | `v1/complete` | `POST /` |
| gemini | `v1beta` | `GET models`، `GET models/:model`، `POST models/:modelAction`، `POST models/:model/countTokens` |
| files | `v1/files` | `POST /`، `GET /`، `GET :id`، `GET :id/content`، `DELETE :id` |
| batches | `v1/batches`، `v1/messages/batches`، `v1beta/batches` | ساخت/خواندن/لغو/نتیجه |
| uploads | `v1/uploads` | `POST /`، `POST :id/parts`، `POST :id/complete`، `POST :id/cancel` |
| thinking | `v1/thinking` | `POST end`، `GET/DELETE sessions/:id` |
| observability | `internal/audit`، `internal/thinking` | stats، requests، filter-options، body chunks، delete، repair |
| v1internal | `v1internal` | `countTokens`، `embedContent`، `generateChat` |

### ۵.۳ پورت، bind و کلید

| مورد | رفتار |
| --- | --- |
| پورت پیش‌فرض | **8045** (`config.port \|\| 8045`؛ محدوده‌ی معتبر ۱۰۲۴–۶۵۵۳۵) |
| bind بدون کلید | `127.0.0.1` |
| bind با کلید | `0.0.0.0` + CORS |
| تعارض پورت | به `reason: 'address-in-use'` تبدیل می‌شود |
| خواندن کلید | `Authorization: Bearer` / `x-api-key` / `x-goog-api-key` |
| بدون کلید | **Open Mode** — همه‌ی درخواست‌ها مجاز |
| تولید کلید | `sk-${randomUUID().replace(/-/g,'')}` |
| گاردها | `ProxyGuard` (کلید پروکسی + توکن OpenCode) و `AdminGuard` برای `/internal/*` |
| سقف body | ۶۴ MiB برای مسیرهای مدل، ۱ MiB برای بقیه |

### ۵.۴ مسیر کردن مدل

`server/shared/services/model-routing.service.ts` — تابع `resolveModelRoute(model)` با ترتیب اولویت:

1. wildcard پیکربندی‌شده (`*` → regex)
2. dynamic-legacy forwarding
3. مدل دقیقِ پیکربندی‌شده
4. نگاشت خانوادگی Anthropic
5. نگاشت built-in
6. `miss` (ثبت در `model-route-misses.json`، ۵۰ آیتم / ۳۰ روز)

منبع نگاشت: `antigravity/model-specs.json` + `model-variant-registry.ts`؛ aliasهای کاربر در `config/model-aliases.ts`.
`GET /v1/models` علاوه بر فیلدهای استاندارد، `context_length` و `max_completion_tokens` را هم می‌دهد.

### ۵.۵ استریم

SSE در همه‌ی پروتکل‌ها. mapperها: `ClaudeStreamingMapper.ts`، `OpenAIResponsesStreamingMapper.ts`، `internal-sse.ts`.
هدرهای زمان‌سنجی: `X-Timing-Clean-Ms`، `X-Timing-Norm-Ms`، `X-Timing-Thinking-Ms`، `X-Timing-Ttft-Ms` + `X-Session-Id`، `X-Antigravity-Session-Id`.
WebSocket دوجهته برای Responses (`openai-responses-websocket.server.ts`) با همان منطق احراز هویت.

### ۵.۶ لاگ ترافیک / مموری (audit)

`proxy-gateway/audit/` (~۴۵ فایل): `traffic-audit.service.ts`، `.repository.ts`، `.database.ts`، `.retention.ts`، `.worker.ts`، `traffic-classifier.ts` (کلاس‌ها: `system`، `ipc`، `auxiliary`، `model`)، `audit-sanitizer.ts`، `incremental-sse-redactor.ts`، `sensitive-data-masking`.
جدول‌ها روی Drizzle/SQLite: `request_logs`، `audit_payloads`، `audit_admin_events`.
حذف دسته‌ای ۳۲ ردیفی + `VACUUM`؛ retention جدا برای body و summary.

**Thought Store** (`proxy-gateway/thought-store/`، ۱۰ فایل): بازیابی thought/signature بین درخواست‌ها با کلید هش‌شده‌ی credential + شناسه‌ی نشست.

**state پایدار** در `~/.antigravity-agent/proxy-state/` (نوشتن atomic):

| فایل | حدود |
| --- | --- |
| `openai-responses-sessions.json` | ۵۰۰ نشست / ۱ ساعت |
| `openai-chat-completions.json` | ۵۰۰ / ۱ ساعت |
| `model-route-misses.json` | ۵۰ / ۳۰ روز |
| `proxy-batches.json` | ۲۰۰ / ۴۸ ساعت |
| `proxy-uploads.json` | ۲۵۶ / ۱ ساعت |

File store: `proxy-files/` — ۲۰ MiB per file، ۵۱۲ MiB per store، انقضا ۴۸ ساعت.

### ۵.۷ انتخاب حساب (Account Lease)

`server/modules/account-lease/` با الگوی Policy: `config`، `selection`، `quota`، `quota-refresh`، `hydration`، `fulfillment`، `limit`، `model`.

- استراتژی: `proxy.account_selection_strategy` — پیش‌فرض `balanced` (چرخش وزنی بر اساس quota)، یا `account-first` (چسبندگی به یک حساب برای هر مدل).
- وزن‌دهی quota: زیر ۲۵٪ یا نامعلوم → ۱؛ بین ۲۵–۷۴ → ۲؛ ۷۵+ → ۳.

### ۵.۸ upstream

- Gemini عمومی: `https://generativelanguage.googleapis.com/v1beta`
- داخلی (Internal Cloud Code): failover بین `daily-cloudcode-pa` و `cloudcode-pa` روی `/v1internal`
- پروکسی upstream: `google-proxy-agent.ts`، `https-proxy-agent`، `proxy-from-env`

### ۵.۹ بقیه‌ی زیرپوشه‌های گیت‌وی

`agent-tools/` (پیکربندی Claude Code / Codex / OpenCode) · `antigravity/` (۴۵ mapper: `ClaudeRequestMapper`، `ClaudeResponseMapper`، `OpenAIResponsesResponseMapper`، `ModelMapping`، `SignatureStore`، `ThinkingUtils`، `JsonSchemaUtils`) · `audit/` · `curl-export/` · `diagnostics/` · `ipc/` · `opencode-sync/` · `playground/` · `thought-store/` · `traffic-monitor/`

---

## ۶. حساب ابری گوگل و OAuth

### ۶.۱ کلاینت‌های OAuth

`services/OAuthClientRegistryService.ts`:

| مورد | مقدار |
| --- | --- |
| کلید کلاینت built-in | `antigravity_enterprise` |
| `client_id` | `1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com` |
| `client_secret` | `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` (در کد plaintext) |
| کلاینت‌های اضافه | از env `ANTIGRAVITY_OAUTH_CLIENTS` با فرمت `key|client_id|client_secret[|label]` |
| کلاینت فعال | env `ANTIGRAVITY_OAUTH_CLIENT_KEY` (پیش‌فرض `antigravity_enterprise`) |

**Scopeها** (`src/shared/auth/googleOAuthScopes.ts` — ۷ مورد):
`openid` · `cloud-platform` · `userinfo.email` · `userinfo.profile` · `cclog` · `experimentsandconfigs` · `aicode`

### ۶.۲ endpointهای بالادستی (`GoogleAPIService.ts`)

| کار | URL |
| --- | --- |
| صفحه‌ی احراز هویت | `https://accounts.google.com/o/oauth2/v2/auth` (`access_type=offline`, `prompt=consent`) |
| توکن | `https://oauth2.googleapis.com/token` (`authorization_code` و `refresh_token`) |
| پروفایل | `https://www.googleapis.com/oauth2/v2/userinfo` |
| پروژه | `.../v1internal:loadCodeAssist` (cloudcode → daily → sandbox) |
| مدل‌ها | `.../v1internal:fetchAvailableModels` |
| quota هفتگی | `.../v1internal:retrieveUserQuotaSummary` |
| اعتبار | `.../v1internal:fetchCredits` |

timeout: ۳۰ ثانیه · تأخیر تلاش مجدد روی `invalid_grant`: ۵۰۰ میلی‌ثانیه.

### ۶.۳ جریان ورود

`ipc/desktop-oauth-login.ts` (مالک کل login دسکتاپ — داده‌ی احراز هویت هرگز وارد IPC رندرر نمی‌شود) →
`headless-oauth-session.service.ts` → `cloud-account-oauth-settings.service.ts` → `GoogleAPIService.ts` →
`google-account-enrollment.service.ts` → `ide-account-sync.service.ts`.

### ۶.۴ ذخیره‌سازی credential

- توکن‌های OAuth حساب ابری **به‌صورت plaintext JSON در SQLite محلی** ذخیره می‌شوند — یک تصمیم آگاهانه و مستند.
- بقیه‌ی credentialها در keyring سیستم‌عامل: `shared/security/key-providers/{keytar, safe-storage, file}` + `master-key-manager.ts`.
- `cloud-account-device-binding-store.ts` و `cloud-account-device-profile-codec.ts` — اتصال دستگاه.

---

## ۷. بین‌المللی‌سازی

`src/localization/` — ساختار تخت، هر زبان یک فایل با کلیدهای kebab-case:

`en.ts` · `zh-CN.ts` · `ru.ts` · `vi.ts` · `tr.ts` · `fr.ts` · `pt-BR.ts` + `i18n.ts`

i18next + react-i18next + browser language detector · `fallbackLng: 'en'` · کلید در localStorage با نام `lang` · `load: 'currentOnly'`.

> **نکته:** در بسته‌ی نهایی فقط `en, en-US, zh-CN, ru` نگه داشته می‌شود (`forge.config.ts` → `electron-packager-languages`)، یعنی `vi/tr/fr/pt-BR` در کد هست ولی در بسته‌ی نصبی نیست.

---

## ۸. تست و CI

| بخش | تعداد | توضیح |
| --- | --- | --- |
| `src/tests/unit` | ۴۹۱ | همه‌ی تست‌های Vitest (تنها الگوی include شده) |
| `src/tests/performance` | ۹ + ۱۳ | performance recorder |
| `src/tests/e2e` | ۲ | Playwright (فقط chromium) |
| `src/tests/fixtures` | ۵ | proxy-parity (request/response/stream)، responses-format-v1 |

Vitest: `happy-dom`، `globals: true`، `maxWorkers: 4`، alias `@`، mock برای `keytar`/`better-sqlite3`/`electron`.
تست‌های Node-native (`node --test`) برای اسکریپت‌های کیفیت و پذیرش.

پوشش‌یافته‌ترین حوزه‌ها: account-lease و سیاست انتخاب، گارد کلید و envelope احراز هویت، مسیر کردن مدل، retry/fallback، mapperهای SSE، OAuth گوگل و طبقه‌بندی خطا، ذخیره‌ی credential، سوییچ داغ حساب، امنیت (master-key، masking، sandbox preload)، به‌روزرسانی ویندوز/لینوکس، workspace، runtime/core-RPC.

CI (`.github/workflows/`): `testing.yaml`، `lint.yaml`، `format.yaml`، `build-check.yaml`، `pr-checks.yaml`، `release.yml`، `publish.yaml`، `issue-triage.yml`، `react-doctor.yml`.

---

## ۹. مستندات، OpenSpec و حاکمیت عامل‌ها

### ۹.۱ `docs/` (۵۴ فایل md)

| مسیر | محتوا |
| --- | --- |
| `docs/README.md` | اندیس مستندات و نگاشت «رفتار ← مالک» |
| `docs/architecture.md` | نقشه‌ی runtime، مالکیت پروسه، جهت وابستگی، مرز IPC |
| `docs/development.md` · `docs/testing.md` · `docs/test-reliability.md` | راه‌اندازی، استراتژی تست، پایداری تست |
| `docs/security.md` · `docs/error-handling.md` | مرزهای اعتماد، مالکیت خطا |
| `docs/development/*` | build-and-package، git-checks، diagnostics، github-automation، nix، release-tooling، agent-skills |
| `docs/security/*` | privacy دیاگنوستیک، انتقال runtime خصوصی |
| `docs/testing/*` | agent-routing، delivery، diagnostics، native-runtime، review-evaluation |
| `docs/modules/*` | per-module: overview، security، testing |
| `docs/modules/proxy-gateway/compatibility.md` | **بلندترین سند** — مرجع سازگاری گیت‌وی |
| `docs/modules/proxy-gateway/account-leases.md` | ذخیره‌ی token/project حساب |
| `docs/modules/proxy-gateway/schema-conversion.md` | انتخاب schema، محدودیت تبدیل |
| `docs/modules/proxy-gateway/agent-tools.md` | پیکربندی Claude Code / Codex / OpenCode |
| `docs/modules/proxy-gateway/acceptance/*` | live-agent، media-thinking |
| `docs/modules/proxy-gateway/debugging/*` | Proxyman (و راهنمای ویندوز) |
| `docs/upgrade-guides/next/*` | account-switch-close، agy-binary-patch، process-diagnostics، workspace-credential-ownership |

سند راهنمای ماژول سرور: `src/modules/proxy-gateway/server/README.md` (~۴۹KB).

### ۹.۲ `openspec/`

ساختار: `openspec/project.md` + `openspec/changes/<نام>/` با `proposal.md`، `design.md`، `tasks.md` و `specs/<capability>/spec.md`.

۷ change فعال: `add-multiarch-release-artifacts`، `improve-cross-platform-stability`، `localize-app-chinese-default`، `refactor-db-drizzle`، `support-wsl-environment`، `update-device-fingerprint-hardening`، `update-ide-auth-compat-1165`.

### ۹.۳ حاکمیت عامل‌ها

| پوشه | محتوا |
| --- | --- |
| `AGENTS.md` | ۱۱.۵KB — قواعد معماری، تایپ/API، گردش‌کار تغییر، تأیید، امنیت داده |
| `.agents/` | ۲۵۰ فایل — `lessons.md`، `notes/` (~۲۴۰ یادداشت ثبت تصمیم)، skillهای Vercel |
| `.agent/` | ۱۲۲ فایل — skillهای OpenSpec، `project_overview`، `ui-ux-pro-max` |
| `.claude/` · `.codex/` | ۲۰ / ۵۱ فایل — promptها و skillهای `opsx-*` |
| `.github/skills/impeccable/` | پیاده‌سازی skill در سطح repo |
| `.impeccable/` | `config.json` + `design.json` (سیستم طراحی «Signal Blue») |

---

## ۱۰. پوشه‌های جانبی

| پوشه | نقش |
| --- | --- |
| `scripts/` (۲۰۲) | ابزارهای Node: `verify-runtime-boundaries`، `verify-type-boundaries`، `import-graph`، `check-agent-contracts`، `change-scope`، `acceptance/` (schema/diagnostics/installers)، `quality/`, `review-eval/`, `git/`, `github/`, `agent-skills/` |
| `patches/` | ۳ patch pnpm: AppImage maker، `@electron-forge/core`، `exe-icon-extractor` |
| `packaging/` | بسته‌ی AUR (`arch/PKGBUILD`) |
| `resources/` | فید آپدیت AppImage لینوکس |
| `images/` | ۲۱ آیکون و splash |
| `types/` | ۵ فایل declaration |
| `.github/` | ۸۰ فایل: workflowها، issue templateها، skillهای impeccable |

---

## ۱۱. نکات و ناسازگاری‌هایی که در خود پروژه هست

این‌ها را عمداً ثبت می‌کنم چون هنگام مراجعه به upstream ممکن است گمراه‌کننده باشند:

1. `openspec/project.md` می‌گوید **Electron 39** ولی `package.json` می‌گوید **`electron ^37.3.1`**.
2. `README.md` و `PRODUCT.md` سه زبان (انگلیسی/چینی/روسی) را اعلام می‌کنند، ولی کد **۷ زبان** دارد و بسته‌ی نصبی فقط ۴ زبان را نگه می‌دارد.
3. ساختار `src/` که در `openspec/project.md` توصیف شده (`src/main.ts`، `src/preload.ts`، `src/ipc/account/`، `src/services/`) با کد فعلی هم‌خوان نیست — آن سند قدیمی‌تر است.
4. `docs/ownership-cutover-audit.md` اسنپ‌شات **تاریخی** معماری است، نه گزارش وضعیت فعلی.
5. `GoogleAPIService.ts` حدود ۱۳۰۰ خط است؛ منطق fallback بین endpointهای quota فقط از کامنت‌ها و ثابت‌ها قابل استخراج است.

---

## ۱۲. فهرست فایل‌های کلیدی برای کار با این پروژه

| موضوع | فایل |
| --- | --- |
| جریان OAuth گوگل | `src/modules/cloud-account/services/GoogleAPIService.ts` |
| ثبت کلاینت OAuth | `src/modules/cloud-account/services/OAuthClientRegistryService.ts` |
| scopeها | `src/shared/auth/googleOAuthScopes.ts` |
| mapper کلاد ← داخلی | `src/modules/proxy-gateway/antigravity/ClaudeRequestMapper.ts` |
| نوع درخواست داخلی | `src/modules/proxy-gateway/antigravity/types.ts` |
| کلاینت upstream | `src/modules/proxy-gateway/server/modules/gemini/gemini-client.service.ts` |
| مسیر کردن مدل | `src/modules/proxy-gateway/server/shared/services/model-routing.service.ts` |
| گارد کلید | `src/modules/proxy-gateway/server/guards/proxy.guard.ts` |
| استخراج کلید | `src/modules/proxy-gateway/server/guards/api-key-auth.util.ts` |
| bootstrap سرور | `src/server/main.ts` |
| پیکربندی سرویس | `src/modules/config/types.ts` · `service-config.service.ts` |
| مرجع سازگاری | `docs/modules/proxy-gateway/compatibility.md` |
| راهنمای ماژول سرور | `src/modules/proxy-gateway/server/README.md` |

---

## ۱۳. آنچه ما از این پروژه گرفته‌ایم (و آنچه نگرفته‌ایم)

**گرفته‌ایم:** پروتکل‌ها و مسیرهای گیت‌وی، قالب کلید (`sk-<hex>`)، رفتار bind بر پایه‌ی وجود کلید، پورت ۸۰۴۵، کلاینت و scopeهای OAuth، ترتیب endpointهای upstream و failover آن‌ها، ساختار لاگ ترافیک.

**نگرفته‌ایم (خارج از دامنه‌ی این دور):** traffic audit کامل، thought store، پیکربندی ابزارهای agent، workspace و اشتراک فایل، تعویض داغ حساب بین کلاینت‌های IDE، سوییچ کردن خودکار حساب، پروفایل identity، به‌روزرسانی خودکار، CLI و runtime مستقل `core`.
