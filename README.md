# Redmine Subrocketchat Plugin

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![Redmine](https://img.shields.io/badge/Redmine-4.x%20%7C%205.x%20%7C%206.x%20%7C%207.x-red.svg?logo=redmine)
![Rocket.Chat](https://img.shields.io/badge/Rocket.Chat-6.x%20%7C%207.x%20%7C%208.x-F5455C.svg?logo=rocketchat)
![License](https://img.shields.io/badge/license-MIT-green.svg)

A modern Redmine plugin that embeds **Rocket.Chat** directly into Redmine project pages and issues via **[@embeddedchat/react](https://github.com/RocketChat/EmbeddedChat)** — replacing legacy `<iframe>` integrations with a native, theme-adaptive chat sidebar, a **1-Click Setup Wizard**, live `#1234` issue autocomplete, and dedicated per-issue chat threads.

> Built for teams that want real-time Rocket.Chat collaboration tightly woven into their Redmine project and ticket workflow — without third-party cookie headaches, CORS configuration, or iframe layout glitches.

---

## Features

- **1-Click Setup Wizard (Zero Rocket.Chat CORS / Iframe Config Needed)**:
  - Because all REST and media requests run through the built-in Redmine same-origin proxy, **you do not need to configure CORS or iframe headers in Rocket.Chat**.
  - Simply enter your **Rocket.Chat URL** plus the username & password of a Rocket.Chat `admin` / bot user in the plugin settings and click **Connect & Generate Token** — Redmine automatically generates and stores a non-expiring Personal Access Token and User ID.
  - Enable role permissions (`:access_chat`), default project modules, and initial project channel synchronization with a single button click directly on the plugin settings page.
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
  - Automatically creates a private Rocket.Chat group (`rm_<project_identifier>`) when a Redmine project with the `rocket_chat` module is created, and deletes it when the project is deleted.
  - Automatically syncs project member additions and removals to the corresponding Rocket.Chat group.
  - **Auto-Provisioning**: automatically creates missing Redmine users in Rocket.Chat on the fly (`users.create`).
- **Built-in Rocket.Chat 8.x Compatibility & Same-Origin Proxy**:
  - Routes `/api/*`, `/file-upload/*`, and `/ufs/*` requests through Redmine's authenticated `RocketChatController#proxy`.
  - Transparently translates public channel endpoints (`channels.*`) used by EmbeddedChat to private group endpoints (`groups.*`).
  - Translates legacy `rooms.upload/:rid` calls (removed in Rocket.Chat 8.0) into Rocket.Chat 8.x's two-step `rooms.media` + `rooms.mediaConfirm` upload workflow.
  - Translates thread message queries (`query={"tmid":...}`) to `/api/v1/chat.getThreadMessages` for Rocket.Chat 7.x / 8.x compatibility.

---

## Requirements

- **Redmine**: `4.x`, `5.x`, `6.x`, or `7.x`
- **Rocket.Chat**: `6.x`, `7.x`, or `8.x`
- A dedicated bot/service user in Rocket.Chat (e.g. `redmine_bot`) with the **`admin`** role.

---

## Quick Installation & 1-Click Setup

> [!IMPORTANT]
> The plugin directory **MUST** be named `redmine_subrocketchat`.
> *(Upgrading from legacy `redmine_rocketchat`? Your existing configuration is migrated automatically on startup.)*

1. **Clone & Migrate**:
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/subversive-tools/redmine_subrocketchat.git redmine_subrocketchat

   cd /path/to/redmine
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

2. **Restart Redmine**.

3. **1-Click Setup in Redmine** (**Administration > Plugins > Subrocketchat > Configure**):
   - **Step 1**: Enter your **Rocket.Chat URL** (`https://chat.example.com`) and the username & password of your Rocket.Chat admin/bot user (`redmine_bot`), then click **⚡ Connect & Generate Token**.
   - **Step 2**: Check the Redmine roles that should have chat access and click **✔ Apply Roles & Synchronize Projects Now**.
   - Done!

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

If you want to modify [`frontend/rocketchat_embedded.jsx`](frontend/rocketchat_embedded.jsx):

```bash
cd frontend
npm install
npm run build
```

---

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — Version history and release notes

## Contributing

Contributions are welcome — please fork the repository and open a Pull Request.

## License

[MIT License](LICENSE) — Copyright (c) 2024–2026 Stefan Mischke
