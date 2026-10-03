# SayFridge Mobile

Flutter Android application with a browser build of the same Mobile interface.
The [project README](../README.md) is the overall entry point. Use Flutter 3.44.8,
Dart 3.12.2 and Android Studio/SDK for Android development.

## Local execution

Run from `mobile/`:

```bash
flutter pub get --enforce-lockfile
flutter run -t lib/main.dart \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` reaches the host backend from an Android emulator. To use the shared
cloud backend, replace it with `https://sayfridge-backend-preview.vercel.app/api/v1`.
The native app connects directly to Vercel, not through Render; Vercel connects to Neon.
Restart the Flutter run/build after changing compile-time API configuration.

```bash
flutter run -d chrome --web-port=5174 -t lib/main.dart \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Allow the local browser origin in backend CORS. Browser builds default to same-origin
`/api/v1`; a standalone static site requires an explicit API URL for online features.
The Android application ID is `com.appix.sayfridge`.

## Checks

```bash
flutter analyze
flutter test --exclude-tags manual_preview
```

[Testing Strategy and Evidence](../docs/testing/README.md) owns CI selections,
report policy and native acceptance. [Build and Deployment](../docs/delivery/README.md)
owns Render settings, APK build/install and release publication.

## Interaction and state

Home, inventory/spaces, quantity operations, expiry and Assistant use real APIs.
The Assistant and Daily Check-in share `AgentInputPanel`: hold the speech region
to recognize English (`en-US`), release to await editable text, slide up to cancel,
and send explicitly. The keyboard microphone switches modes rather than starting
recognition. Camera/gallery images can be previewed, removed and compressed before
sending. Daily Check-in allows 1,000 characters and up to four images and requests
approval before deductions. Failed sends preserve input.

Assistant is a secondary page: Back returns to its entry page and hides bottom
navigation. Header controls remain fixed. Input sits above the safe area and shifts
with the keyboard. Message avatars and speech tails stay near the top of each
bubble as longer text extends the body downward. `AppBottomNavigation` stays
outside scroll content at the safe-area
bottom: 78% available width, icon/text gap 3 logical pixels and bottom spacing 28.
Use the component's `extent` to reserve content space rather than adding duplicate margins.
Desktop browsers show a centered 390px phone frame up to 844px tall; small/touch
browsers use available space. The frame includes dialogs and does not alter native layout.

Assistant replies render Markdown headings, bold names, and hanging-indent lists.
Body line height is 1.45; list items have 8px spacing and paragraph/section breaks
have 14px spacing. Older plain-text lists also emphasize short labels before a
colon. Stored messages retain their original text. The backend agent prompt
requests this structure for new reports and needs backend deployment to take effect.
Generated documents start with a brief introduction followed by a `##` title.
`AssistantReply` keeps the introduction in a bubble and places the complete
document in a full-width rounded card below it. Untitled legacy inventory reports
with storage-space bullets also use a card. Short replies and action reviews keep
their normal conversation layout.

Production confirmation dialogs share `AppDialog`: pale-green rounded cards, green
filled primary actions with dark text, and unfilled green-outline cancel actions.
Cancel aligns with the left content inset and the primary action aligns right;
actions wrap vertically when large text cannot fit on one row.
Sign in offers email/password only. The Recover password dialog has no email
delivery endpoint yet and tells the user that no recovery email was sent.

Photo stock displays review cards before writes. Confirm all handles selected
eligible proposals, with per-item results; clarification/unknown outcomes remain
separate. Retain conversation/request identity during reconnects and query state
before retrying. Current balances show exact or estimated state; exact measurements
can be edited and recorded through reconciliation, while initial stock facts remain.
Assistant review headers use a 56px item icon with 14px spacing before the name/status.
Item clarification and "Describe another detail" reuse the shared composer as a
compact, voice-first draft input: hold to speak, release to edit the transcript,
or switch between keyboard and voice. Confirm submits the item-scoped answer;
recording alone never sends it. Sliding up cancels speech and preserves the existing
text/selected choices. These inline inputs accept up to 1,000 characters and have
no photo or separate send action. Successful review cards say "Saved successfully"
for both additions and updates; quantity conversion prompts prefer the server's
user-facing question.
While the keyboard is open for a pending item, the disabled main composer is
hidden without discarding its text/photos, leaving space for inline editing.
Inventory Delete enters selection, Confirm opens archival confirmation and Cancel
clears selection. Item-details quantity actions use full-row controls.

Credentials use FlutterSecureStorage. Access renews automatically; concurrent
requests share renewal. Logout waits for server revocation before clearing credentials,
so offline logout can be retried. Business lists and local conversation state reset
on account changes. Full history listing is not provided by the backend.

## Profile and reminders

Profile preferences (nickname, avatar and reminder settings) are local per-user data
through `ProfilePreferencesRepository`; they are not synchronized to the backend.
Registration saves the nickname and selected avatar under the created user ID.
Personal Information prefills the saved nickname, falling back to the same email
prefix shown on Profile for older accounts without a saved name. The stored
`full_name` key remains compatible with existing preferences. The avatar library
uses four columns with a fixed confirmation button outside the scroll area.
All library avatars have a white rim; Profile, Personal Information and signup
use a thinner 2.5px rim.
Guest menus lead to login and successful login returns to Profile. Email/password
changes have no backend API and are not reported as successful.

Native reminders use local scheduled notifications after explicit permission.
Browser notifications operate with permission while the app is open. Home shows
expired, upcoming and check-in reminders; Mark as read suppresses repeats for the
day. Process now opens expired inventory and uses the existing Discard confirmation,
retaining its record. Production voice usage is unavailable: the current user API
does not provide a request-count quota. The preview's 12/50 is sample data.
Home's bell and the notification inbox share the same unread list. Mark as read
updates the list after persistence without waiting for OS notification cancellation;
older asynchronous queries cannot restore a dismissed notification.

Profile tests live in `test/screens/profile_flow_test.dart` and
`test/state/profile_controller_test.dart`.

## Android launcher artwork

Launcher resources use the SayFridge fridge/microphone artwork in
`assets/launcher/launcher_avatar.png`, with density-specific legacy icons and
an adaptive foreground/background for launcher masks.
This launcher source removes the thin white circular edge from the mascot backdrop.
The launcher background matches the green sampled inside the artwork so
square/adaptive icons do not show a lighter frame around the circular source.
After changing that asset, run `python scripts/generate_launcher_icons.py` with
Pillow installed, then rebuild the APK. Icon generation is a development step;
it adds no app runtime dependency.

Inventory tiles and item icon previews/library cards use each artwork's sampled
green background, including manually selected icons and the default mascot.
After replacing food artwork, run `python scripts/generate_item_artwork_palette.py`
to refresh the palette. Both scripts read/package existing artwork without redrawing it.

## Debug-only offline preview

```bash
flutter run --debug -t lib/main_preview.dart
```

The separate preview starts on Profile with `UI PREVIEW · OFFLINE`, makes no
network requests and does not read/alter real credentials. It supplies eight sample
items, three upcoming items and Fridge/Freezer/Pantry; dates are relative to startup.
The badge switches sample/empty inventory and resets filters. Profile/reminder
edits exist only in preview memory; writes do not pretend to persist inventory.
Logout switches to guest; Enter preview returns without a password. The normal
`lib/main.dart` entry contains no preview wiring. Preview refuses release/profile mode.
