# Antigravity Manager - Installation and Usage Guide

Antigravity Manager is a Windows desktop application that manages AI coding service accounts (such as Google Cloud Code / Gemini), monitors quotas, and runs a local proxy/gateway allowing coding tools to access them via an API key.

---

## Architecture & Components

The application consists of two tightly integrated parts:
1. **Frontend (Flutter UI):** `antigravity_manager.exe` provides the graphical user interface, dashboards, account manager, playground, and traffic logs.
2. **Backend (Rust Host & Proxy):** `antigravity-host.exe` manages SQLite profile storage, Google OAuth sessions, quota tracking, and the local AI API gateway.

When you launch `antigravity_manager.exe`, it automatically detects and starts `antigravity-host.exe` in the background if it is not already running, communicating securely over a private named pipe.

---

## Installation & Setup

### For End Users (Pre-built Release)
1. Go to the [GitHub Releases](https://github.com/SwanFlutter/antigravity_manager/releases) page.
2. Download the latest `antigravity-manager-windows-x64.zip` archive.
3. Extract the ZIP file to any folder on your Windows PC (e.g., `C:\Program Files\AntigravityManager` or your desktop).
4. **Important Notice on Network & Location:**
   - Google requires valid network conditions for Gemini / Cloud Code services. Always ensure you are connected behind a clean, stable VPN or proxy to prevent Google from flagging location restrictions or requiring unexpected account re-verification (`VALIDATION_REQUIRED` / `TOS_VIOLATION`).

### Running the Application
1. Double-click **`antigravity_manager.exe`**.
2. Navigate to the **Accounts** tab to connect your Google account securely via OAuth.
3. Navigate to the **API Proxy** tab to start the local gateway (default port `8045`).
4. Configure your coding assistants (such as Cline, Continue, or custom OpenAI/Anthropic clients) to point to `http://127.0.0.1:8045/v1` using your local API key (`sk-...`).

---

## Troubleshooting & Account Security

- **Account Verification (`VALIDATION_REQUIRED`):** If Google requests verification, click the **Verify Account** button directly in the account card to open the official verification page in your browser.
- **Account Restrictions (`TOS_VIOLATION`):** If an account is restricted by Google, use the **Submit Appeal** button to submit a review request, or connect a fresh Google account.
- **Local Proxy:** Regenerating the API key in the proxy settings will not remove upstream Google restrictions; ensure your network IP is stable.
