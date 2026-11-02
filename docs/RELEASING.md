# Client releases

Actions → Release Client → Run workflow on `main`: enter a new tag such as `v0.2.2`. Alternatively push a new `vMAJOR.MINOR.PATCH` tag. Manual runs create the tag at the checked-out source only after every platform builds. Suffixes such as `-rc.1` publish prereleases. Published versions cannot be overwritten.

The workflow uses `.flutter-version`, enforces `pubspec.lock`, runs analysis and tests, builds Android, Windows x64 and macOS universal, then publishes an APK, Android license bundle, two desktop ZIPs and SHA256SUMS.txt. Release permissions are limited to the final publishing job. Third-party actions are pinned by commit.

## Android signing

Configure these repository Actions secrets before the first run:

| Secret | Value |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | Base64 of the dedicated open-source release keystore |
| ANDROID_STORE_PASSWORD | Keystore password |
| ANDROID_KEY_PASSWORD | Key password |
| ANDROID_KEY_ALIAS | Key alias |

Back up the keystore and passwords securely. Retain the same key for upgrades. Signing material is restored only for the Android build and deleted immediately afterward; it must never be committed or uploaded as an artifact. The build fails if signing secrets are missing. The open-source application ID is distinct from the official Android app. The CI build number is `1000 + github.run_number` and the display version comes from the release tag.

The published default relay is an example. Users configure their own server in the app. Do not add production configuration or credentials to source exports.

Windows is not Authenticode signed. macOS uses the existing ad-hoc identity and is not notarized; Developer ID distribution requires separate certificates and configuration. No iOS package is published.

After a failed partial upload, remove the incomplete draft before rerunning the original tag workflow. Do not move an existing published tag. Automated builds do not replace real-device testing for native credentials and camera access.
