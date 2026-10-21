# Remim Browser

Remim is a lean cross-platform browser prototype for Android and Windows. It has a single active desktop page view at a time, a 60-second inactive-tab freeze path, a curated tracker/ad request blocklist on desktop, a Flutter WebView client on Android, local bookmarks/history, and optional Supabase sync with realtime tab transfers.

> **Build status for this workspace:** the source scaffold and validation tests are provided. An APK and Windows installer have **not** been produced in this Linux workspace because Flutter/Android SDK and Windows packaging tools are not installed here. Use the included Windows/Android build scripts or run the GitHub Actions workflow to produce real installables. No placeholder binaries are included.

## What's in the project

- `electron/` — Windows/Linux desktop browser shell based on Electron `BaseWindow` + `WebContentsView`, with isolated/sandboxed renderers and network filtering.
- `src/` — minimal dark browser UI, bookmark/history views, Supabase auth/sync, teleport notifications, and URL/blocklist helpers.
- `apps/android/` — Flutter Android client using `webview_flutter` and `supabase_flutter`.
- `supabase/supabase_schema.sql` — bookmarks, browsing history, device sessions, transfers, row-level security, indexes, and Realtime publication configuration.
- `.github/workflows/build-installers.yml` — builds an Android release APK and a Windows x64 NSIS installer on the appropriate runners.
- `scripts/` — local build and source validation commands.

## Important engineering limits

- **No browser can promise a universal 300 MB process ceiling.** Memory use depends on the OS, active page, media, graphics, browser engine and extensions. Remim reduces the number of live inactive desktop tabs and requests tracker/ad domains be blocked; it cannot guarantee a specific RAM figure.
- **Desktop tab freezing:** while Low memory is enabled, a page inactive for 60 seconds is converted to a sanitized static HTML preview, its web contents are closed, and its last URL is retained. Selecting a frozen tab shows the static preview; use the preview's **Restore live page** link or the toolbar reload button to load the real site again. Form controls, scripts, frames, media and external resource links are stripped from the preview, but it is still stored in the local app profile.
- **Android tab freezing:** `webview_flutter` provides no general public callback for intercepting every subresource request. The Android client filters navigations to known tracker hosts and runs a small DOM/CSS cleanup for common ad slots, but it is not equivalent to desktop's network-level blocker. Background WebViews are kept only until the 60-second timer fires, then their controller references are released and the tab restores from its URL when selected.
- **Ad/script handling is conservative.** The desktop network filter blocks a maintained list of known ad/analytics endpoints and hides common ad slots. It intentionally does not block generic JavaScript frameworks because doing that broadly would break login forms, video players and modern websites.
- **Session Teleportation transfers a URL/title, not cookies or login state.** The recipient opens the URL in its own browser session. Both devices must be signed in to the same Supabase account.
- The desktop app uses Electron, not Tauri. Electron's Chromium runtime is generally heavier than a minimal native WebView wrapper, but its native `WebContentsView` API allows Remim to embed web pages and close their renderer contents after freezing.

## Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor** and run `supabase/supabase_schema.sql`.
3. In the project Auth settings, configure email/password sign-in. For new accounts, email confirmation may be required depending on your project settings.
4. Enable the `session_transfers` table in Realtime if your project configuration does not automatically apply the included publication statement.
5. Copy `.env.example` to `.env` and fill in the project URL and the public anon/publishable key:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY
```

Only the public client key belongs in the app. **Never ship a Supabase `service_role` key.** Row-level security policies are included; do not disable them.

For Android builds, the same values are passed as Dart defines. If omitted, the browser remains usable in local-only mode, but cloud login, bookmark/history sync and teleport are unavailable.

## Run the desktop app in development

Requirements: Node.js 22.12+ and npm. On Windows, also ensure your account can install desktop apps. Supabase is optional.

```powershell
Copy-Item .env.example .env
# Edit .env with your Supabase public URL and key if cloud features are desired.
npm install
npm run dev:desktop
```

Or validate source helpers without downloading desktop dependencies:

```bash
./scripts/verify-source.sh
```

## Build the Windows installer

Build the actual installer on Windows to avoid cross-platform NSIS/Wine packaging problems:

```powershell
./scripts/build-windows.ps1
```

The installer should appear at:

```text
release/Remim-Setup-0.1.0-x64.exe
```

Equivalent commands are `npm install`, `npm run build`, then `npx electron-builder --win nsis --x64 --publish never`.

## Build the Android APK

Requirements: Flutter stable, Java, Android SDK and Android build-tools. Set `ANDROID_HOME`/`ANDROID_SDK_ROOT` and accept SDK licenses before building.

```bash
SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
SUPABASE_ANON_KEY="YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY" \
./scripts/build-android.sh
```

The script generates the Flutter Android host project into `.build/android`, builds Release mode, and copies the APK to:

```text
release/Remim-Android-release.apk
```

On Windows, run the equivalent commands in Git Bash or WSL with Android SDK configured, or use the GitHub Actions workflow below.

## Produce both installers in GitHub Actions

The checked-in workflow builds on pushes to `main`, version tags, or a manual run (**Actions → Build Remim installers → Run workflow**). On its first run, it reconstructs and expands the source archive into normal tracked files in the repository. The workflow uploads two artifacts separately: `Remim-Android-APK` and `Remim-Windows-Installer`. Add repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY` to bake the public app configuration into the builds; without them, browser features remain local-only. The workflow is manual or tag-triggered and does not automatically publish a public release.

## Local verification

```bash
./scripts/verify-source.sh
```

When npm packages are available, `npm run build` runs the Node URL/blocklist tests, performs TypeScript checks, and builds the UI. `npm test` runs only the Node tests.

## Privacy notes

History/bookmarks are initially stored in the device's local app profile. When signed in, page titles/URLs and bookmark metadata are synced to your Supabase project. Avoid signing in on shared devices. Browser session cookies are stored by the embedded WebView profile, not transferred by Teleport. Static desktop snapshots omit form controls and scripts, but page text may still contain private content; clear browser app data on shared machines.
