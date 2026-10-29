# LPI City Money

A mobile-friendly, globally synced **fictional city-money game** for friends. Version 0.3.1 adds a blue/green pixel-inspired redesign, an in-app updater with byte-based download progress on Windows, a compatible-build check, SVG iconography, animated payment review and slide-to-confirm flow, personal open-amount pay QR codes, saved issued gift cards, and an admin-controlled daily spin. It uses LPI game coins only: there are no real bank accounts, actual UPI payments, cash withdrawals, or redeemable rupees.

## Features

- Name/password accounts (custom game login, not Supabase Auth); passwords are salted and hashed with PBKDF2 before storage.
- Random 16-digit **fictional** LPI CityCard, expiry and CVV with a prominent simulated-card label.
- Direct game-coin transfers with a payment review modal and slide-to-confirm interaction; simulated card transfers, 6-digit request payments and explicit payer approval.
- Personal player QR/pay code identifies the recipient; another player can enter any game-coin amount before confirming. These QR codes are LPI-only, not UPI codes.
- Optional WebAuthn platform-authenticator prompt (fingerprint, face unlock, or passcode depending on the device) where available. This is a local game UX feature, not banking-grade transaction authentication; it is unavailable in some browsers/file origins.
- Indian rupee glyph styling is visual formatting only; every amount is still LPI game coins, not rupees or redeemable value.
- VIP for 1,999 LPI game coins for 30 minutes or 19,999 LPI game coins for lifetime; active VIP has an animated crown shown beside the player name and recipient check, 3% game-coin transfer discount and simulated cashback rewards.
- Global daily spin with server-checked once-per-UTC-day rewards: configurable LPI coin prizes, one-use simulated cashback coupons, or temporary VIP. Admins can pause/activate the spin globally.
- Admin media cards: send one image or MP4 video up to 4 MB to a selected player.
- Recipient lookup displays an animated SVG crown beside active VIP names, so the payer can identify the VIP before confirming a simulated transfer.
- Animated payment/bill/gift receipts and a GitHub Releases update checker for Windows and Android.
- One-time gift codes with a 16-digit code and stored-value deduction at creation. Issuers can select any LPI gift-card style; any LPI player can redeem it regardless of their own CityCard style. Issued-card records and active gift codes are available in the issuer's authenticated history for later sharing.
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

The debug APK is at android/app/build/outputs/apk/debug/app-debug.apk. It can be installed for personal testing after allowing app installs from your chosen file manager. It is not a Play Store-signed release. Release builds publish the Windows EXE and Android APK to GitHub Releases so the app's built-in updater can find versioned assets. v0.2.2 includes the corrected LPI launcher icon and minimum-client-version checks for payment and write actions. The in-app updater checks for a compatible newer GitHub Release, shows “You're up to date” when no newer asset exists, and downloads the selected asset without navigating to a release page. Windows downloads show real byte progress inside the app; the final installer/package installation remains user-confirmed.

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

The key must have the corresponding permission. These operations change **LPI game coins only** and never move real funds. Connected apps must not request real bank-card numbers, CVVs, or expiry dates; this endpoint is not a card processor. Keep keys on a trusted backend, never in a browser/mobile frontend, and issue only the scopes required.

## Important limitations

- This is not UPI and not a financial product. It does not use real bank accounts, real UPI IDs, banking networks or real payment rails. The look is an original LPI design and does not reproduce PhonePe pixel-for-pixel.
- Apply `apps/lpi-city-money/supabase/migrations/20261029_lpi_payment_ui_refresh.sql` from the repository root to the connected Supabase project, then redeploy the `lpi-api` Edge Function. The migration removes the card-style restriction for gift-card redemption and adds the global spin activation column.
- A personal QR uses an LPI custom URI, not a UPI QR. Another camera app may display its text; use LPI's in-app scanner to load the recipient.
- Universal phone-to-phone NFC is not available to all browsers/devices; LPI uses QR plus a 6-digit code and explicit approval.
- Daily SIP deductions are processed server-side when the player opens the app on/after a due date. This prototype does not run guaranteed unattended scheduled deductions.
- Gold prices are random game values and do not track real gold or market prices.
- The included API is a test/sandbox integration; it should not be used for real deposits, withdrawals or money.
- The source includes a publishable Supabase key only; never replace it with a secret/service-role key.

Made by Gemaa.
