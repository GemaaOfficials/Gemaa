# LPI City Money

## Downloads · v0.4.0

- **Windows installer (EXE):** https://github.com/GemaaOfficials/Gemaa/releases/download/lpi-v0.4.0/LPI.City.Money.Setup.0.4.0.exe
- **Android app (APK):** https://github.com/GemaaOfficials/Gemaa/releases/download/lpi-v0.4.0/app-debug.apk
- **All release files and notes:** https://github.com/GemaaOfficials/Gemaa/releases/tag/lpi-v0.4.0

A mobile-friendly, globally synced **fictional city-wallet game** for friends. v0.4.0 brings a fresh black-and-emerald wallet interface, brighter readable text, mobile bottom navigation, a gold animated SVG VIP crown, and a public LPI Player Card ID. The project is a sandbox game: balances and transactions are LPI game coins only, never rupees or real money.

## Features

- Name/password game accounts; passwords are salted and PBKDF2-hashed before storage.
- A public, non-payment **LPI Player Card ID** (format `LPI-XXXXXXXXXX`) and game-only expiry. No card number, CVV, or payment credential is generated, stored, or shown.
- Card renewal: once the game-card expiry date passes, the dashboard issues one 500 LPI game-coin renewal bill. The player sees the bill and must manually pay it from their game balance; paying renews the card for 24 months. There is no automatic charge and no ₹500 payment.
- Game-coin transfers with payment review and slide-to-confirm, plus 6-digit request payments and explicit payer approval.
- Personal player QR/pay code identifies a recipient; another player can enter an LPI amount before confirming. QR codes are not UPI codes.
- Optional device-local WebAuthn prompt where supported; this is a convenience feature, not banking-grade transaction authentication.
- VIP plans use LPI game coins only. Active VIP displays a glowing animated gold crown SVG beside the player name and recipient checks.
- Global daily spin, admin announcements, media cards, gift codes, bills, fictional gold trading, and game-only SIP plans.
- Admin tools to manage game coins, bills, announcements and sandbox API keys.
- Windows Electron installer, portable ZIP and Android Capacitor APK build workflow.
- In-app update checker shows compatible versions and download progress where supported.

## Connected services

The source is isolated in `apps/lpi-city-money/`. It uses the existing Supabase project **ReEditX** and the LPI tables plus one Edge Function named `lpi-api`.

- Public endpoint: https://zyoyxjagyglngrlbnkwb.supabase.co/functions/v1/lpi-api
- The public client uses a publishable Supabase key. Never put a `service_role` or secret key in the app.
- Custom game login uses `lpi_users` and `lpi_sessions`; it does not create Supabase Auth users.
- App operations pass through the Edge Function; privileged database actions remain server-side.

## Run on desktop for development

Requires Node.js 22 or newer.

    npm install
    npm run dev

## Build Windows

    npm install
    npm run dist:win

Output is created inside `release/`.

## Build Android

    npm install
    npm run android:setup
    cd android
    # Windows: gradlew.bat assembleDebug
    # macOS/Linux: ./gradlew assembleDebug

The debug APK is at `android/app/build/outputs/apk/debug/app-debug.apk`. It is for personal testing and is not a Play Store-signed release.

## Sandbox API · LPI game coins only

Create a key from Admin (Alt+T) → Sandbox app API key. Select only the required scopes. v0.4.0 supports `balance`, `deposit`, `withdraw`, and `player_lookup`. Existing active sandbox keys were upgraded to these four game-only scopes.

Endpoint:

    POST https://zyoyxjagyglngrlbnkwb.supabase.co/functions/v1/lpi-api
    Content-Type: application/json
    apikey: <Supabase publishable key>
    x-lpi-api-key: <LPI sandbox key>

Look up a player by their public LPI Player Card ID:

    {
      "operation": "player_lookup",
      "cardId": "LPI-0123456789"
    }

Read a balance:

    {
      "operation": "balance",
      "cardId": "LPI-0123456789"
    }

Sandbox deposit or withdrawal:

    {
      "operation": "deposit",
      "cardId": "LPI-0123456789",
      "amount": 100
    }

    {
      "operation": "withdraw",
      "cardId": "LPI-0123456789",
      "amount": 25
    }

Each action requires the matching key scope. `balance`, `deposit`, and `withdraw` can also target a player by their exact game username using `userName`. `player_lookup` requires the public card ID. The endpoint does not accept a CVV, expiry date, or real payment-card number. It cannot move money or pay bills in rupees. Keep API keys on a trusted backend, never in a browser or APK.

## Important limitations

- This is a pretend-money game, not a bank, wallet provider, UPI app, or financial product. LPI coins have no rupee value and cannot be redeemed for cash.
- Player Card IDs are profile identifiers, not payment-card numbers.
- The 500-coin expiry renewal invoice is issued inside the game only. The player must manually pay it from their LPI balance.
- The LPI design uses an original black-and-emerald theme and common wallet-style navigation; it does not copy PhonePe branding or claim to process real payments.
- Personal QR codes use an LPI custom URI, not UPI. Use the in-app scanner or enter a request code.
- Daily SIP processing happens when a player opens the app on/after a due date; this prototype does not guarantee unattended scheduled deductions.
- Fictional gold values are random game values, not real market prices.
- Never store or request bank-card numbers, CVVs, expiry dates, UPI PINs, or real payment credentials.

Made by Gemaa.
