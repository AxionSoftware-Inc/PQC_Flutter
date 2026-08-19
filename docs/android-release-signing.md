# Android release signing

Release artifacts must use an operator-managed keystore. The Gradle build no
longer falls back to the Android debug key silently.

Set these environment variables in the build runner or deployment secret
store:

```sh
export ANDROID_KEYSTORE_PATH=/secure/path/axion-release.jks
export ANDROID_KEYSTORE_PASSWORD='...'
export ANDROID_KEY_ALIAS='axion-release'
export ANDROID_KEY_PASSWORD='...'
flutter build apk --release \
  --dart-define=API_BASE_URL=https://chat.example.com/api \
  --dart-define=SDK_RELEASE=v2
```

For a local install-only release test, the debug key can be enabled explicitly:

```sh
ALLOW_DEBUG_SIGNING=true flutter build apk --release
```

Never set `ALLOW_DEBUG_SIGNING` in CI, production, or a store upload pipeline.
Do not commit the keystore, passwords, or signing material.
