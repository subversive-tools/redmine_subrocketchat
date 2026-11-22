# Changelog

All notable changes to **Redmine Subrocketchat** (`redmine_subrocketchat`, formerly `redmine_rocketchat`) are documented in this file.

## [2.0.0] - 2026-11-22

### Added
- **Renamed to `redmine_subrocketchat`** (`Subrocketchat`) as part of the [Subversive Tools](https://github.com/subversive-tools) plugin suite, with automatic seamless migration of existing `plugin_redmine_rocketchat` database settings.
- **Native `@embeddedchat/react` Integration**: Replaced the legacy `<iframe>` embedding with a native, DOM-integrated React chat component (`assets/javascripts/rocketchat_embedded.js`) that avoids third-party cookie blocks and `X-Frame-Options` restrictions.
- **Theme-Adaptive UI**: Dynamically inherits font family, font size, background, text, border, and primary accent colors from the active Redmine theme, with a compact single-row icon header matching the exact height of Redmine's `#top-menu`.
- **Draggable Resizable & Collapsible Sidebar**:
  - Smooth drag splitter on the left edge of the sidebar (`localStorage` persisted width, double-click to reset to `30em`).
  - Collapses into a right-aligned **Chat** tab in Redmine's `#main-menu` with a pulse/blink highlight indicator.
  - Responsive docking between the right sidebar (`> 1200px`) and the main content area (`<= 1200px`) using a single live chat instance without reconnecting.
- **Intra-Project PJAX Navigation**: Switching between project tabs (Overview, Issues, Kanban, Wiki, Gantt, Settings) swaps `#wrapper` via AJAX while keeping the Rocket.Chat sidebar open and connected without reloading.
- **`#1234` Issue Autocomplete Dropdown**: Typing `#` in the chat input opens a live searchable dropdown of visible project issues (`Enter` inserts a formatted Markdown issue link; `Shift+Enter` or clicking `💬 Thread` opens/starts the dedicated issue thread).
- **Per-Issue Chat Threads (`tmid`)**:
  - Added database migration `001_add_rocketchat_thread_id_to_issues.rb` (`issues.rocketchat_thread_id`).
  - Added a native **Chat** action link (`icon-comment` with active status dot) between *Edit* and *Watch* in the issue contextual bar.
  - Automatic switching directly into the issue's thread when creating a thread or opening an issue that already has an active thread.
  - Optional automatic creation of issue threads on issue creation and automatic posting of issue status changes/notes as thread replies.
- **Automatic User Provisioning & Token SSO**: Optionally creates missing Redmine users in Rocket.Chat (`/api/v1/users.create`) and supports resume token generation (`/api/v1/users.createToken` with optional `CREATE_TOKENS_FOR_USERS_SECRET`).
- **Built-in Rocket.Chat 8.x Compatibility Proxy**:
  - Eliminates browser CORS preflight issues by routing `/api/v1/*` requests through Redmine (`RocketChatController#proxy`).
  - Translates legacy `rooms.upload/:rid` calls to Rocket.Chat 8.x's two-step `rooms.media` + `rooms.mediaConfirm` upload workflow.
  - Translates deprecated `query={"tmid":...}` calls to `/api/v1/chat.getThreadMessages`.
  - Proxies authenticated `/file-upload/*` and `/ufs/*` media URLs and maps `channels.images` to `groups.files` so inline images, downloads, and the fullscreen `ImageGallery` lightbox work seamlessly in private project groups.

## [1.0.2] - 2024-12-03

### Added
- Initial release (`redmine_rocketchat`): automatic creation and deletion of private Rocket.Chat groups (`rm_<project_identifier>`), project member synchronization (`ProjectPatch`, `MemberPatch`), and iframe-based project tab / sidebar view.
