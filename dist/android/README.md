# Play NeonWastesRPG on Android

This is a **playtest APK**, debug-signed, for sideloading. It is not a Play
Store build.

## Fastest path

Download **[NeonWastesRPG.apk](https://github.com/jimmylovnjames/Game-development/raw/cursor/android-playable-9eac/dist/android/NeonWastesRPG.apk)**
(or open that file on the branch and use GitHub’s **Download raw file**).

Copy it to the phone, then Settings → security → allow install from this
source, and open the APK.

Package id: `rpg.neonwastes.playtest`. Uninstall that package before installing
a build signed with a different key.

## Build it yourself

Needs Godot **4.7.1**, Android SDK (platform-tools + build-tools 35 + platform
35), and a JDK 17+.

```bash
export ANDROID_HOME=$HOME/Android/Sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64   # or 21
godot --headless --path . --import
GODOT=godot bash tools/export_android.sh              # build/android/NeonWastesRPG.apk
```

Static checks (no SDK required):

```bash
bash tools/check_android_export.sh
```

## Controls

The on-screen HUD appears automatically on a phone:

- Left stick — move
- Right half of the screen — look
- **JUMP** / **SPRINT** / **USE** / **LIGHT** / **DUCK**

A Bluetooth gamepad (Xbox layout) also works: left stick move, right stick
look, A jump, X use, Y flashlight, B crouch, LB sprint.

## Notes

- Landscape (sensor). Portrait is locked out.
- The mobile renderer is **Compatibility** (OpenGL ES 3). Volumetric fog and
  SSAO from the desktop Forward+ look are off; neon signs and ink outlines
  still carry the frame.
- First launch hitch is shader compile. That is expected.
- arm64-v8a only. 32-bit `armeabi-v7a` phones are not supported.
