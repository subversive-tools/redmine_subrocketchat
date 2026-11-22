# Redmine Subrocketchat Plugin

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![Redmine](https://img.shields.io/badge/Redmine-4.x%20%7C%205.x%20%7C%206.x%20%7C%207.x-red.svg?logo=redmine)
![Rocket.Chat](https://img.shields.io/badge/Rocket.Chat-6.x%20%7C%207.x%20%7C%208.x-F5455C.svg?logo=rocketchat)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A modern Redmine plugin that embeds **Rocket.Chat** directly into Redmine project pages and issues via **[@embeddedchat/react](https://github.com/RocketChat/EmbeddedChat)** — replacing legacy `<iframe>` integrations with a native, theme-adaptive chat sidebar, automatic SSO token authentication, live `#1234` issue autocomplete, and dedicated per-issue chat threads.

> Built for teams that want real-time Rocket.Chat collaboration tightly woven into their Redmine project and ticket workflow — without third-party cookie headaches, CORS hurdles, or iframe layout glitches.

---

## Features

- **Native EmbeddedChat Integration (No `<iframe>`)**:
  - Renders Rocket.Chat directly inside the Redmine DOM using a pre-bundled `@embeddedchat/react` client (`assets/javascripts/rocketchat_embedded.js`).
  - Eliminates third-party cookie restrictions, `X-Frame-Options` / CSP blocks, and double scrollbars.
- **Theme-Adaptive UI**:
  - Automatically inspects the active Redmine theme at runtime (background, foreground, primary accent, secondary box colors, border colors, and font family/size) and applies the exact palette to the chat widget.
  - Ultra-compact, single-row header that matches Redmine's `#top-menu` bar height.
  - Includes an **"Open in Rocket.Chat"** action inside the chat header menu (`⋮`) to jump straight into the full Rocket.Chat web/desktop client (`https://chat.example.com/group/<channel>`).
- **Persistent, Resizable & Collapsible Sidebar with PJAX Navigation**:
  - Displays the project's Rocket.Chat group as a dockable right-hand sidebar across all project views (Overview, Issues, Wiki, Kanban, Gantt, etc.).
  - **Drag-to-resize** left border (`220px` up to `70%` viewport width, persisted in `localStorage`; double-click resets to default `30em`).
  - **Collapsible**: closing the sidebar reveals a right-aligned **Chat** tab in Redmine's `#main-menu` with a brief visual highlight animation.
  - **Responsive**: on narrower viewports (`<= 1200px`), the sidebar automatically collapses into the `#main-menu` **Chat** tab and seamlessly re-docks into the sidebar when the window is widened again.
  - **Intra-project PJAX navigation**: switching between tabs within the same project swaps `#wrapper` via AJAX so the chat sidebar stays mounted and connected without reloading.
- **Live `#1234` Issue Autocomplete Dropdown**:
  - Type `#` followed by an issue ID or title fragment in the chat input to open a live autocomplete popup of project issues.
  - **`Enter` / `Tab`** (or clicking **Link**) inserts a rich Markdown link (`[#123: Issue Subject](https://redmine.example.com/issues/123)`).
  - **`Shift+Enter`** (or clicking **💬 Thread**) immediately opens or starts the dedicated Rocket.Chat thread for that issue.
- **Dedicated Per-Issue Chat Threads**:
  - Adds a contextual **Chat** button (with a live green indicator dot when an active thread exists) between *Edit* and *Watch* on every issue detail page.
  - Opening an issue that already has an active Rocket.Chat thread automatically switches the chat sidebar directly into that issue's thread (`tmid`).
  - Starting a thread posts an initial root message linking back to the Redmine issue (`🎫 [#123: Subject](url)`) and stores the resulting `rocketchat_thread_id` on the issue.
  - **Optional automatic thread creation** whenever a new issue is created.
  - **Optional automatic journal updates**: posts issue status/assignee/priority changes and notes as replies into the issue's active Rocket.Chat thread.
- **Automatic Channel, Member & User Synchronization**:
  - Automatically creates a private Rocket.Chat group (`groups.create`) when a Redmine project with the `rocket_chat` module is created, and archives/deletes it when the project is archived/deleted.
  - Automatically syncs project member additions, role permissions (`:access_rocket_chat`), and removals to the corresponding Rocket.Chat group.
  - **Auto-Provisioning & Token SSO**: optionally creates missing Redmine users in Rocket.Chat on the fly (`users.create`) and logs them into EmbeddedChat automatically via `users.createToken` (supports Rocket.Chat 7.x / 8.x `CREATE_TOKENS_FOR_USERS_SECRET`).
- **Built-in Rocket.Chat 8.x Compatibility & Same-Origin Proxy**:
  - Routes `/api/*`, `/file-upload/*`, and `/ufs/*` requests through Redmine's authenticated `RocketChatController#proxy`, avoiding browser CORS preflight (`OPTIONS 405`) and media authentication issues.
  - Transparently translates public channel endpoints (`channels.*`) used by EmbeddedChat to private group endpoints (`groups.*`).
  - Translates legacy `rooms.upload/:rid` calls (removed in Rocket.Chat 8.0) into Rocket.Chat 8.x's two-step `rooms.media` + `rooms.mediaConfirm` upload workflow.
  - Translates thread message queries (`query={"tmid":...}`) to `/api/v1/chat.getThreadMessages` for Rocket.Chat 7.x / 8.x compatibility.
- **Redmine Subsimplify Integration**:
  - Automatically respects [`redmine_subsimplify`](https://github.com/subversive-tools/redmine_subsimplify) module visibility settings when installed.

---

## Requirements

- **Redmine**: `4.x`, `5.x`, `6.x`, or `7.x` (Ruby `2.7+` / `3.x`)
- **Rocket.Chat**: `6.x`, `7.x`, or `8.x`
  - **WebSockets** must be reachable from the user's browser at the public Rocket.Chat URL (`wss://...`).
  - If using **Rocket.Chat 7.x / 8.x** with SSO auto-login (`users.createToken`), ensure the environment variable `CREATE_TOKENS_FOR_USERS_SECRET` is set on your Rocket.Chat server and configured in the plugin settings.

### Required Rocket.Chat Bot / Admin Permissions

Create a dedicated service/bot account in Rocket.Chat (e.g. `redmine_bot`) or use an admin account with a **Personal Access Token** and the following permissions:

| Permission Key | Purpose |
|:---|:---|
| `create-p` | Create private groups for Redmine projects |
| `delete-p` | Delete private groups when projects are removed (or archived if configured) |
| `add-user-to-any-p-room` | Add project members to private project groups |
| `remove-user` | Remove project members from private project groups |
| `view-p-room` | Query private group info, messages, and files |
| `create-personal-access-tokens` | Generate the API Token for the bot user |
| `api-bypass-rate-limit` | Avoid rate-limiting during bulk member or project synchronization |
| `create-user` *(optional)* | Required if **Automatically provision missing users in Rocket.Chat** is enabled |
| `create-user-token` *(optional)* | Required if **Automatic login (SSO via token) in EmbeddedChat** is enabled |

---

## Installation

> [!IMPORTANT]
> The plugin directory **MUST** be named `redmine_subrocketchat`.
> *(Upgrading from legacy `redmine_rocketchat`? The plugin automatically migrates your existing configuration from `plugin_redmine_rocketchat` on startup.)*

1. **Clone** the repository into your Redmine `plugins/` directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/subversive-tools/redmine_subrocketchat.git redmine_subrocketchat
   ```

2. **Run the plugin database migration** (adds `rocketchat_thread_id` to `issues`):
   ```bash
   cd /path/to/redmine
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. **Restart Redmine** (e.g. `touch tmp/restart.txt`, restart Puma/Unicorn/Passenger, or restart your Docker container).

4. **Configure the plugin** in Redmine:
   - Go to **Administration > Plugins > Redmine Subrocketchat Plugin > Configure** and enter your Rocket.Chat connection details.
   - Go to **Administration > Roles and permissions** and grant the **Access rocket chat** permission (under the *Rocket.Chat* section) to the appropriate roles.
   - Enable the **Rocket.Chat** module in your projects under **Project > Settings > Modules** (or enable it globally as a default project module under **Administration > Settings > Projects**).

---

## Configuration

Navigate to **Administration > Plugins > Redmine Subrocketchat Plugin > Configure**:

| Setting | Description | Default |
|:---|:---|:---|
| **Redmine Base URL** | Public base URL of your Redmine instance (used for backlinks in Rocket.Chat thread root messages). Defaults to Redmine's `protocol://host_name`. | Auto-detected |
| **Rocket.Chat URL** | Public URL of your Rocket.Chat server (used by the browser for WebSocket connections and "Open in Rocket.Chat" links, e.g. `https://chat.example.com`). | `https://chat.example.com` |
| **Optional internal Rocket.Chat address** | Optional internal backend URL for server-to-server REST API & proxy calls (e.g. `http://rocketchat:3000` in Docker setups). Falls back to **Rocket.Chat URL** if empty. | *(empty)* |
| **Rocket.Chat User ID** | User ID of the Rocket.Chat bot/admin account. | *(empty)* |
| **Rocket.Chat API Token** | Personal Access Token of the Rocket.Chat bot/admin account. | *(empty)* |
| **Rocket.Chat Token Secret (`CREATE_TOKENS_FOR_USERS_SECRET`)** | Optional secret required by Rocket.Chat 7.x / 8.x for `/api/v1/users.createToken` SSO token generation. | *(empty)* |
| **Show Rocket.Chat in Sidebar** | Renders Rocket.Chat as a persistent, collapsible, resizable sidebar across all project pages. If disabled, Rocket.Chat is only shown under the project's **Chat** tab. | Enabled (`1`) |
| **Automatic login (SSO via token) in EmbeddedChat** | Automatically generates a Rocket.Chat resume token for the current Redmine user so they are signed into EmbeddedChat immediately. | Enabled (`1`) |
| **Automatically provision missing users in Rocket.Chat** | Creates a matching Rocket.Chat user account (username, full name, email) automatically if the Redmine user does not exist in Rocket.Chat yet. | Enabled (`1`) |
| **Automatically create ticket threads for new issues** | Automatically posts a root message in the project's Rocket.Chat group and links the thread whenever a new issue is created. | Disabled (`0`) |
| **Post issue updates & notes to the ticket thread** | When an issue has an active Rocket.Chat thread, posts status/priority/assignee changes and notes as replies into that thread. | Enabled (`1`) |

---

## Usage

### 1. Project Chat Sidebar & `#main-menu` Tab
- When **Show Rocket.Chat in Sidebar** is enabled, the chat panel docks to the right side of every page in projects where the **Rocket.Chat** module is active.
- Drag the left edge of the sidebar to adjust its width; double-click the drag handle to reset it.
- Click the **`×`** button in the chat header to collapse the sidebar into the right-aligned **Chat** tab in the project menu. Click **Chat** in the project menu to expand it again.

### 2. Referencing Issues & Opening Threads with `#`
- Inside the chat message box, type `#` (e.g. `#42` or `#login`):
  - Use **`↑` / `↓`** to navigate matching issues in the current project.
  - Press **`Enter`** (or click **Link**) to insert `[#42: Issue Title](https://.../issues/42)` at the cursor.
  - Press **`Shift+Enter`** (or click **💬 Thread**) to switch EmbeddedChat directly into that issue's thread (creating the thread automatically if it doesn't exist yet).

### 3. Issue Detail Page Integration
- Every issue page displays a **Chat** link in the top and bottom `.contextual` action bars (between *Edit* and *Watch*).
- A **green dot** next to **Chat** indicates that an active Rocket.Chat thread already exists for this issue.
- When you open an issue that already has a thread, the sidebar automatically focuses that thread. Use the back arrow (`←`) in the thread header to return to the main project channel at any time.

---

## Rebuilding the Frontend Bundle

The plugin ships with a pre-built production bundle at [`assets/javascripts/rocketchat_embedded.js`](assets/javascripts/rocketchat_embedded.js), so **no Node.js installation is required on your Redmine server**.

If you want to modify [`frontend/rocketchat_embedded.jsx`](frontend/rocketchat_embedded.jsx) or update the EmbeddedChat patches:

```bash
cd frontend
npm install
npm run build
```

This runs [`frontend/build.mjs`](frontend/build.mjs), which applies the Redmine integration patches to `@embeddedchat/react` and bundles the code into `assets/javascripts/rocketchat_embedded.js` via `esbuild`.

---

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — Version history and release notes

## Contributing

Contributions are welcome — please fork the repository and open a Pull Request.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

[MIT License](LICENSE) — Copyright (c) 2024–2026 Stefan Mischke
