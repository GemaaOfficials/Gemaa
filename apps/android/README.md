# Remim Android source

This directory contains the Flutter application source. The small Android Gradle host project is generated from the installed Flutter SDK by `scripts/build-android.sh`; keeping generated Gradle files out of this source tree avoids pinning a machine-specific Android toolchain.

Build on a machine with Flutter stable, Android SDK/build-tools and Java installed:

```bash
# from the Remim repository root
SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
SUPABASE_ANON_KEY="YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY" \
./scripts/build-android.sh
```

The script writes `release/Remim-Android-release.apk`. Cloud variables are optional for a local-only browser, but sign-in and cross-device transfer need a configured Supabase project and `supabase/supabase_schema.sql` applied there.
