# Test plan — TestFlight build #1

The first build exists to prove the delivery path and the device, not to capture
anything. There is no session storage yet, so nothing you do here is saved.

## What to check

1. **The build installs and opens.** The first screen reads `VividHome build <n>`,
   where `<n>` matches the build number TestFlight shows. If it says `unknown`,
   the Info.plist is not reaching the bundle — report it.
2. **Scene reconstruction is supported.** The line under the title should be the
   green "Scene reconstruction supported". A red line on a LiDAR iPhone means the
   capability check is wrong, which blocks everything after this build.
3. **The core version line** shows `core 0.1.0 · session format v1`.
4. **Open AR session.** The button should be enabled. Tapping it asks for camera
   permission the first time, with the wording "VividHome records the camera and
   LiDAR to document your house during construction."
5. **The camera runs.** After granting permission you should see a live camera
   view. Move the phone slowly around a room for about 30 seconds. Watch for
   freezing, or the view going black.
6. **Done returns.** The Done button closes the AR view and returns to the first
   screen. Reopening the AR session should work a second and third time.

## What to report

The build number, the phone model and iOS version, and for anything that failed,
what you saw instead. A screen recording helps for anything visual.

## Not in this build

Recording, room and phase selection, markers, landmarks, stills, and any writing
to disk. Those arrive in later builds; see `docs/schedule.md`.
