# LPI City Money

A mobile-friendly, globally synced **fictional city-money game** for friends. Version 0.2.0 adds a daily global reward spin, temporary/lifetime VIP passes, animated crowns, admin media cards, payment receipts, and GitHub release update checks. It uses LPI game coins only: there are no real bank accounts, actual UPI payments, cash withdrawals, or redeemable rupees.

## Features

- Name/password accounts (custom game login, not Supabase Auth); passwords are salted and hashed with PBKDF2 before storage.
- Random 16-digit **fictional** LPI CityCard, expiry and CVV with a prominent simulated-card label.
- Direct transfers, simulated card transfers, 6-digit QR/request payments and explicit payer approval.
- VIP for 1,999 LPI game coins for 30 minutes or 19,999 LPI game coins for lifetime; active VIP has an animated crown, 3% game-coin transfer discount and simulated cashback rewards.
- Global daily spin with server-checked once-per-UTC-day rewards: configurable LPI coin prizes, one-use simulated cashback coupons, or temporary VIP.
- Admin media cards: send one image or MP4 video up to 4 MB to a selected player.
- Animated payment/bill/gift receipts and a GitHub Releases update checker for Windows and Android.
- One-time gift codes with a 16-digit code, matching card-style restriction, and stored-value deduction at creation.
- Admin controls: grant game coins, create bills, publish announcements, view players and create/revoke sandbox API keys.
- Bills can be postponed once for 10 minutes; overdue bills show a reminder but never lock the device.
- Fictional gold price that randomly changes, gold buy/sell and 10/20/30-coin daily SIP plans.
- Electron Windows installer and Capacitor Android APK build workflow.

## Connected services

This workspace is isolated in apps/lpi-city-money/ inside GemaaOfficials/Gemaa. It uses the existing Supabase project **ReEditX** with only lpi_* tables and one Edge Function named lpi-api; existing ReEditX tables were not changed.

- Public endpoint: https://zyoyxjagyglngrlbnkwb.supabase.co/functions/v1/lpi-api
- The publishable key is intentionally used by the public client. Never put a service_role key into this app or any client.
- Custom login uses the lpi_users and lpi_sessions tables and does not create Supabase Auth users.
- RLS is enabled on each lpi_* table. Browser/mobile access goes through the Edge Function; privileged operations run server-side.
- The admin password is stored as a bcrypt hash in the database secret table, not embedded in this repository.

## Run on desktop for development

Requires Node.js 22 or newer.

    npm install
    npm run dev

The web UI requires an internet connection to contact the Supabase Edge Function. QR scanning also needs camera permission; manually entering the 6-digit request code is the fallback.

## Build the Windows installer

    npm install
    npm run dist:win

Output is created inside release/.

## Build Android

    npm install
    npm run android:setup
    cd android
    # Windows: gradlew.bat assembleDebug
    # macOS/Linux: ./gradlew assembleDebug

The debug APK is at android/app/build/outputs/apk/debug/app-debug.apk. It can be installed for personal testing after allowing app installs from your chosen file manager. It is not a Play Store-signed release. Push a tag such as `lpi-v0.2.0` to build a GitHub Release with the Windows EXE and Android APK. The in-app updater checks the latest GitHub Release and opens the correct asset for the device; final installation and restart remain user-confirmed.

## GitHub Actions artifacts

The workflow .github/workflows/lpi-build.yml builds the Windows EXE and Android APK separately. Open Actions → Build LPI City Money, choose a successful run and download LPI-Windows-EXE or LPI-Android-APK. These are build artifacts, not automatically published releases.

## Sandbox API for Fry Trading (game-only)

Admin creates a key from Alt+T → Sandbox app API key. The full key is shown once; only its hash is stored server-side. Store it in a backend secret, never inside a public frontend or APK.

Endpoint:

    POST https://zyoyxjagyglngrlbnkwb.supabase.co/functions/v1/lpi-api
    Content-Type: application/json
    apikey: <Supabase publishable key>

Check a player's simulated balance:

    {
      "apiKey": "lpi_test_REPLACE_WITH_KEY",
      "operation": "balance",
      "userName": "PlayerName"
    }

Sandbox deposit:

    {
      "apiKey": "lpi_test_REPLACE_WITH_KEY",
      "operation": "deposit",
      "userName": "PlayerName",
      "amount": 100
    }

Sandbox withdrawal:

    {
      "apiKey": "lpi_test_REPLACE_WITH_KEY",
      "operation": "withdraw",
      "userName": "PlayerName",
      "amount": 25
    }

The key must have the corresponding permission. These operations change **LPI game coins only** and never move real funds.

## Important limitations

- This is not UPI and not a financial product. It does not use or copy real FamPay/RuPay card numbers, banking networks or real payment rails.
- Universal phone-to-phone NFC is not available to all browsers/devices; LPI uses QR plus a 6-digit code and explicit approval.
- Daily SIP deductions are processed server-side when the player opens the app on/after a due date. This prototype does not run guaranteed unattended scheduled deductions.
- Gold prices are random game values and do not track real gold or market prices.
- The included API is a test/sandbox integration; it should not be used for real deposits, withdrawals or money.
- The source includes a publishable Supabase key only; never replace it with a secret/service-role key.

Made by Gemaa.
