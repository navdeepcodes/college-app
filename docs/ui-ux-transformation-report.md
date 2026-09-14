# TrueKinn — UI/UX Transformation Report

Scope: a premium, production-grade visual and interaction pass across the
entire app, on top of the Supabase-only backend that the prior engineering
hardening pass left frozen. No backend redesign, no Firebase, no Moments,
no push notifications — see §12 for the one deliberate, minimal exception.

---

## 1. Design direction

**"After-hours campus."** The app already had a dark theme and a purple
accent, and the anonymous-chat screen (radial glow, gradient send button)
was reaching for something the rest of the app hadn't caught up to: a
nocturnal, intimate, slightly conspiratorial feel — closer to the actual
experience of scrolling your phone in a dorm room at 11pm than a clinical
white social app or a flat corporate dark mode. Rather than invent a new
identity, this pass generalized the one the app had already half-built:
every screen now draws from the same near-black canvas, the same single
confident violet accent, and the same restrained motion vocabulary that
anon chat previously had to itself.

Explicitly avoided: cloning Instagram/Snapchat/Discord/BeReal/Facebook: no
double-tap-to-like heart burst, no stories ring, no message-reaction
picker, no swipe-to-dismiss card stack. The interactions that exist (like,
send, approve/reject, report/block) are deliberately quiet — feedback
without spectacle.

## 2. Design system decisions

All new tokens live in `lib/core/`:

- **Color** (`app_colors.dart`) — a refined violet accent
  (`#7C5CFF`/`#B18CFF`/`#4B33A8`) replacing the flat `#6A3DE8`; a
  near-black canvas with a faint blue-violet undertone (`#0A0A10`) instead
  of pure black; a 3-step surface scale (surface / surfaceRaised /
  surfaceSunken) so cards, dialogs, and inputs read as distinct elevation
  without shadows; semantic success/danger/warning colors tuned to sit
  comfortably on dark (not pure red/green); a dedicated `anonAccent` for
  anonymous chat's own identity; and a deterministic
  `avatarGradientFor(seed)` used by every avatar fallback.
- **Typography** (`theme.dart`) — **Sora** for display/headings/buttons,
  **Inter** for body/labels, loaded via `google_fonts` (see §11). This
  replaces a real, silent bug: the old theme declared `fontFamily: 'SF Pro
  Display'`, but no such font was ever bundled — no asset, no `fonts:`
  section in `pubspec.yaml` — so it was silently falling back to the
  platform default the entire time the app has existed.
- **Spacing & radius** (`spacing.dart`) — an 8-step spacing scale and a
  5-step radius scale, replacing ad hoc `EdgeInsets`/`BorderRadius` values
  that varied inconsistently (radii from 8 to 28 with no pattern; avatar
  radii from 14 to 58) across the old codebase.
- **Motion** (`motion.dart`) — four durations (90/150/220/320ms) and three
  curves, named by intent, plus a `prefersReducedMotion(context)` helper
  used by the entrance/motion widgets (see §9).
- **Haptics** (`haptics.dart`) — four semantic calls (`select`, `tap`,
  `confirm`, `warn`) instead of raw `HapticFeedback.*` calls scattered by
  feel (see §6).
- **Component theme** (`theme.dart`) — a full `ThemeData`: input decoration
  (the app previously had *no* `inputDecorationTheme` at all, so every
  screen hand-rolled its own `OutlineInputBorder`/colors — this is why
  onboarding forms looked different from the create-club form, which
  looked different from edit-profile), dialog, bottom sheet, snackbar,
  chip, list tile, popup menu, and tab bar themes, all pulling from the
  same tokens. Screens that used to hardcode `Colors.black`,
  `Colors.deepPurple`, `Color(0xFF1E1E22)`, etc. now inherit from the
  theme; the handful of intentional exceptions (club hero gradient, anon
  chat's own backdrop) reference the token file, not literals.
- **Shared widgets** (`lib/core/widgets/`) — nine reusable pieces built
  for this pass and used across many screens (§3–§8 detail where):
  `Entrance` (keyed one-shot entrance animation), `Pressable` (press-scale
  feedback for custom tap targets), `Skeleton` (shimmer loading
  placeholder), `EmptyState`, `AppAvatar` (initials-gradient fallback),
  `LikeButton` (optimistic like), `ChatBubble` + `MessageStatusIcon`,
  `RequestCard` (approve/reject shell), `relativeTime()`.

## 3. Screen-by-screen changes

**Onboarding** — `welcome_screen.dart` rebuilt as a real hero moment
(staggered entrance, ambient glow, honest copy: "Posts, chats, and clubs —
just for your college," "Verified with your college email") instead of a
placeholder `Text('college_app')`. `login_screen.dart` and
`signup_screen.dart` re-themed (no more hardcoded `Colors.black`/`grey`),
staggered field entrance, icon-prefixed inputs, loading-state button
morph. `profile_setup_page.dart` restructured into labeled sections
("Your identity," "Your college") with staggered entrance and a single
deliberate custom page transition (fade+scale) into the app on submit —
the one bespoke transition in the whole app, spent on the moment a new
user's profile becomes real. **Fixed a real, pre-existing bug**:
`signup_screen.dart` and `profile_setup_page.dart` each hand-typed their
own college list — 7 colleges in one, a different 5 in the other, several
not recognized by `CollegeDetector` at all — so a student could see one
set of colleges at signup and a different set during profile setup. Now
both use one shared `kCollegeOptions` list.

**Navigation** (`bottom_nav_shell.dart`) — switched from rebuilding
`screens[_currentIndex]` from scratch on every tab tap to `IndexedStack`,
so each tab keeps its scroll position, its Realtime subscriptions, and its
widget state across switches (a real state/perf fix, not just visual — see
§10). Nav icons get a selection-tint capsule and a light haptic on switch;
the profile tab's own avatar now uses the shared `AppAvatar`.

**Feed** (`feed_screen.dart`, `post_user_header.dart`,
`comments_screen.dart`, `add_post_screen.dart`, `post_detail_screen.dart`,
`user_posts_grid.dart`) — optimistic `LikeButton` with a bounce and a
haptic; skeleton image loading instead of a bare spinner; pull-to-refresh;
a real empty state with a "Create a post" call to action instead of flat
text; entrance animation per card (new posts only, see §9). **Found and
fixed a real bug live, on-device** (§13): the feed's early-return guard
required *both* `media_path` and `user_id` to be non-null before rendering
a post at all — but `media_path` is nullable in the schema (a post can be
text-only), and three real posts in the live database had no media. They
were rendering as `SizedBox.shrink()` while still counting toward the
list's length, so the feed showed neither the posts nor the "No posts
yet" empty state — just a blank screen. Fixed by requiring only
`user_id`, and rendering the image block conditionally; the same fix was
applied to `user_posts_grid.dart` (now shows a text tile instead of
silently dropping the post from the count) and `post_detail_screen.dart`.
`post_detail_screen.dart`'s like button was also **dead code** before this
pass — the `_ActionButton` for likes had no `onTap` at all; it now uses
the shared `LikeButton`.

**Profile & friends** (`profile_screen.dart`, `friends_list_screen.dart`,
`edit_profile_screen.dart`, `feed/widgets/friend_button.dart`) — avatar
initials-gradient fallback everywhere a photo is missing (replacing a
generic gray person icon that made every no-photo profile look like an
empty database row); stat row, college/year shown as a pill chip;
`FriendButton` rebuilt to *morph* between states (loading → none →
requestSent/friends) via `AnimatedSwitcher` with a scale+fade transition,
instead of an instant swap, with a haptic on send/accept. Blocking a user
from the profile menu now asks for confirmation first ("X won't be able to
message you...") — the one moderation action that previously fired
immediately on menu selection with zero confirmation.

**Chat** (`chat_screen.dart`, `club_chat_screen.dart`,
`chats_list_screen.dart`) — a new shared `ChatBubble` used by both 1:1 and
club chat, with sender-run-aware corner shaping (a "tail" on the newest
bubble in a consecutive run, the standard messaging-app grouping cue);
message status ("sent"/"delivered"/"seen") now renders as an icon
(`MessageStatusIcon`) instead of raw text; composer is a rounded pill with
a circular gradient send button that swaps to a spinner while sending;
each new bubble gets a short slide+fade entrance. `chats_list_screen.dart`
now shows a relative timestamp per conversation (previously showed none
at all despite `last_message_at` being available).

**Anonymous chat** (`anon_home_screen.dart`,
`college_anon_chat_screen.dart`) — deliberately the lightest-touch pass:
this screen already had the most premium execution in the app (radial
gradient backdrop, gradient send button, countdown badges). Colors were
reconciled to the shared `anonAccent`/`accentDeep` tokens instead of
hardcoded `Colors.deepPurpleAccent`, and new message bubbles get the same
entrance animation as every other chat surface — but its distinct "shadow
mode" identity (pure black backdrop, countdown timers, anon-id badges) was
preserved exactly, per the brief's own instruction not to flatten
different chat types into sameness.

**Clubs** (`clubs_screen.dart`, `club_profile_screen.dart`,
`club_admin_dashboard_screen.dart`, `club_join_requests_screen.dart`,
`admin_club_requests_screen.dart`, `create_club_screen.dart`) — club cards
now have real press feedback (`Pressable`) where before they were a bare
`GestureDetector` with zero tap response; entrance animation on the grid;
a proper `EmptyState` with a call to action. `club_profile_screen.dart`'s
hero header and admin-dashboard card use the shared gradient tokens.
Three separate hand-rolled approve/reject card implementations (club
creation requests, club join requests, reports — see §8) are now one
shared `RequestCard` component, so a future change to that pattern only
has to happen once.

**Events** (`events_screen.dart`) — restyled to the shared card system
(was a bare `Card` with `color: Colors.white10`); date shown as a small
date-chip instead of a plain string. No functionality changed — creation
remains reachable only from the feed's "+" sheet, per the brief's
instruction not to build missing product surfaces during this pass.

**Notifications** (`notifications_screen.dart`) — both notification types
now share a `_NotificationCard` shell with a leading icon/avatar, and
**now show a relative timestamp** ("2h ago") — previously not shown at
all despite `created_at` being available on every row, so a notification
never told the user *when* something happened.

**Settings & moderation** (`settings_screen.dart`, `report_dialog.dart`,
`reports_admin_screen.dart`) — settings restructured into labeled sections
with icon chips. **"Account" now navigates to `EditProfileScreen`** — it
previously had no `onTap` at all (a dead tap that looked interactive but
did nothing). **"Privacy" is now honestly labeled "Soon"** with a chip and
no tap handler, rather than looking tappable and silently doing nothing —
there's no Privacy screen in the app and this pass didn't invent one.
`report_dialog.dart` re-themed (no more hardcoded `Color(0xFF1E1E22)`),
its reason picker gets a cleaner selected-state ring; `reports_admin_screen.dart`
uses the shared `RequestCard`.

## 4. Navigation changes

No route architecture changed. The one structural fix is `IndexedStack`
in `bottom_nav_shell.dart` (§3, §10) — tabs now preserve state instead of
rebuilding from scratch on every switch. Tab switches get a light
selection haptic; the Clubs screen's "Your clubs"/"Explore" segmented
control now crossfades between its two lists instead of cutting instantly.

## 5. Animation system

Documented in `lib/core/motion.dart`. Four building blocks, deliberately
small:

- **`Entrance`** — a keyed, one-shot fade+slide for list items. Because
  almost every list in this app is `StreamBuilder`-driven and rebuilds
  wholesale on every emission, a naive per-build animation would replay
  every time someone else's like landed. `Entrance` relies on Flutter's
  own element-diffing: wrap each row in `Entrance(key: ValueKey(id), ...)`
  and a row Flutter has already seen keeps its `State` (and its
  "already played" flag) across rebuilds — only a genuinely new key gets a
  fresh entrance. Used for feed posts, comments, chat bubbles (all three
  chat surfaces), club cards, join/report request cards, notifications.
- **`AnimatedSwitcher`** transitions for state changes that should read as
  a *morph*, not a cut: `FriendButton`'s relationship states, chat send
  buttons swapping to a spinner, login/signup button labels swapping to a
  spinner.
- **`Pressable`** — a press-scale (0.96) wrapper for the app's many custom
  `GestureDetector` containers that previously had no tap feedback of any
  kind (club cards, top-bar pill icons, image pickers). Standard Material
  widgets (`ElevatedButton`, `InkWell`) already get a ripple for free and
  weren't touched.
- **`LikeButton`**'s bounce (scale 1 → 1.35 → 1) on a positive like.

Everything resolves in 90–320ms; nothing in this app runs an ambient or
looping animation. `prefersReducedMotion()` is checked by `Entrance`
itself — when the OS "reduce motion" setting is on, entrances skip
straight to their end state.

**Considered and deliberately not built**: shared-element `Hero`
transitions for avatars (feed → profile, nav bar → profile tab). Rejected
after tracing a real crash risk: `Hero` requires a unique tag per route,
but `BottomNavShell` now keeps all five tabs mounted simultaneously via
`IndexedStack` (§10), and the feed can show the same user's avatar twice
if they've posted more than once — either condition alone means two
`Hero`s can share a tag on screen at once, which is a hard Flutter
assertion failure, not a style tradeoff. Removed the animation rather than
ship a `try`/hope.

## 6. Haptic strategy

Four semantic calls in `lib/core/haptics.dart`, each tied to a specific,
already-audited list of call sites — not sprinkled by feel:

- **`select()`** (light selection) — bottom-nav tab change only.
- **`tap()`** (light impact) — like, friend request sent, club join
  request sent, message sent (all three chat surfaces).
- **`confirm()`** (medium impact) — friend request accepted, club/join
  request approved or rejected, report status changed, profile setup
  completed.
- **`warn()`** (heavy impact) — blocking a user (after the new
  confirmation dialog, §3).

Deliberately excluded: scrolling, opening a screen, typing, tapping a
passive list row. `HapticFeedback` calls are already safe no-ops on
devices/platforms without haptic hardware, so no availability checks were
needed.

## 7. Micro-interactions

- Like: instant optimistic icon flip + count adjustment + bounce + haptic,
  reconciling with the Realtime-authoritative value once the round trip
  completes (`LikeButton`, §8).
- Send buttons (1:1 chat, club chat) morph between an arrow icon and a
  spinner in place, never swap to a differently-shaped control.
- `FriendButton` morphs its whole shape between states (a chip for
  Friends, a disabled outline for a sent request, a filled button with an
  icon for Add/Accept) via `AnimatedSwitcher`, instead of the old instant
  text swap.
- Avatar fallbacks are deterministic per user (`avatarGradientFor(seed)`)
  — the same person always gets the same gradient, so a face becomes
  recognizable at a glance even without a photo.
- Pressable club cards, top-bar pill icons, and image pickers compress
  slightly on press — previously zero feedback on tap for any of these.

## 8. Loading / empty / error state improvements

- **`Skeleton`** (shimmer sweep, pure `AnimationController` + `ShaderMask`,
  no new dependency) replaces bare spinners for feed images, grid
  thumbnails, and club cards while their specific content loads.
- **`EmptyState`** (icon + title + optional message + optional action)
  replaces the app's many one-off `Center(child: Text('No X yet'))` calls:
  feed, comments, friends list, start-conversation, club join requests,
  club creation requests, reports, notifications, search, events, chats
  list. Each answers what's happening and, where there's something to do,
  offers a concrete next action (e.g. feed's empty state opens the post
  composer directly).
- **`EmptyState.error`** / the `isError` variant gives a calm, human
  message ("Couldn't load X — check your connection") instead of exposing
  raw exception text, with a retry action where the surrounding widget
  actually has something to retry.
- The single most impactful fix in this category was **not cosmetic**:
  the feed's blank-screen bug (§3, §13) was a loading/empty-state failure
  in the sense that mattered most — the screen looked "stuck," even though
  no spinner was technically spinning forever.

## 9. Accessibility improvements

- `prefersReducedMotion(context)` (backed by
  `MediaQuery.of(context).disableAnimations`, the real OS-level "reduce
  motion" signal on both iOS and Android) is checked by every `Entrance`
  animation; when set, entrances render in their final state immediately.
- `IconButtonThemeData.minimumSize` set to 44×44 app-wide; the top bar's
  custom pill icons were bumped from an effective ~36px tap target to a
  clearer padded target.
- Text throughout uses `Theme.of(context).textTheme.*` rather than fixed
  pixel sizes disconnected from the user's system text-scale setting;
  nothing new introduced a font size below 11px.
- `AppAvatar`'s initials fallback gives every profile a legible, high-
  contrast identity mark instead of a low-contrast gray-on-gray icon.
- Not attempted: a full semantic-label audit of every icon-only button
  across 37 touched files. Icon buttons that already carried a `tooltip`
  or an adjacent label were left as-is; a handful of icon-only actions
  (e.g. the feed's top-bar pill icons) do not yet have explicit
  `Semantics`/`tooltip` labels for screen readers. Flagged in §14.

## 10. Performance improvements

- **`IndexedStack` in `BottomNavShell`** (§3): tabs preserve scroll
  position and Realtime subscriptions across switches instead of
  rebuilding from scratch. Tradeoff, stated plainly: all five tabs now
  mount (and start their `.stream()` subscriptions) as soon as
  `BottomNavShell` first builds, rather than lazily on first visit —
  slightly more sustained Realtime channels open at once, in exchange for
  eliminating a real reload-flicker/state-loss bug on every tab switch.
  Given this app's already-established pattern of many concurrent
  `.stream()` subscriptions per screen (confirmed safe under load in the
  prior hardening pass), this was judged the right tradeoff; a future
  lazy-tab-mount optimization remains possible if the college's data
  volume ever makes it worth the added complexity.
- **`cacheWidth` on thumbnail images** — grid post thumbnails
  (`user_posts_grid.dart`) and club card images (`clubs_screen.dart`) now
  decode at a bounded resolution (320–360px) instead of the source
  image's full resolution, for tiles that render at roughly a third of
  screen width. A real memory/decode-time win, not a style choice.
- `Skeleton` uses a single lightweight `AnimationController` per instance
  (no image assets, no new package) — cheap enough to use liberally.
- No speculative rebuild/`const`-audit pass was run across the whole
  codebase; `dart fix --apply` was used once to pick up
  `prefer_const_constructors` lints the analyzer already flagged (§15),
  but a systematic "minimize rebuilds" pass was out of scope for a UI/UX
  effort and wasn't attempted.

## 11. New dependencies, and why

**`google_fonts: ^6.2.1`** — the only new dependency. Justification: the
existing theme declared `fontFamily: 'SF Pro Display'` with no font ever
bundled (§2) — a real, previously-invisible bug, not a preference. Rather
than hand-bundle `.ttf` assets and wire a `fonts:` section, `google_fonts`
is the standard, lightweight way to ship a deliberate type pairing (Sora +
Inter) in a Flutter app: it fetches once at first use and caches on
device, with a graceful system-font fallback while a face is first
loading. No shimmer/animation/UI-kit package was added — `Skeleton`,
`Entrance`, `Pressable`, etc. are all built on plain `AnimationController`
and `ShaderMask`/`Transform`, already part of the Flutter SDK.

## 12. Backend changes, if any

None. No migration, no RLS change, no schema change, no new Supabase
table or column. This pass touched only `lib/` (Dart/Flutter source),
`pubspec.yaml`/`pubspec.lock` (the one new dependency), and `test/`. The
feed/grid/detail-screen fix in §3/§13 is a client-side rendering fix for
data the schema already supported (`media_path` was already nullable) —
not a backend change.

## 13. Concrete bugs found and fixed this pass

1. **Feed silently blank for posts without an image.** `_MergedFeed`'s
   `itemBuilder` required both `media_path` and `user_id` to render a
   post; three real, live posts in the database are text-only
   (`media_path IS NULL`), so they rendered as `SizedBox.shrink()` while
   still counting toward the list — meaning the feed showed neither those
   posts nor the "No posts yet" empty state, just a blank screen. Found
   live, on-device, logging in with a real beta account. Fixed in
   `feed_screen.dart`, `user_posts_grid.dart`, and `post_detail_screen.dart`
   (§3).
2. **Dead like button in `post_detail_screen.dart`.** The like
   `_ActionButton` there had no `onTap` handler at all — tapping it did
   nothing, silently. Fixed by wiring it to the shared `LikeButton`.
3. **Inconsistent college lists at signup vs. profile setup.**
   `signup_screen.dart` offered 7 colleges (several not recognized by
   `CollegeDetector` and unrelated to what NMIT/RVCE/BMS/PES students
   would actually see); `profile_setup_page.dart` offered a different 5.
   Unified into one `kCollegeOptions` list (§3).
4. **Dead "Account" and unlabeled "Privacy" settings rows.** Neither had
   an `onTap`. "Account" now opens `EditProfileScreen` (a real,
   already-existing destination — zero new screens); "Privacy" is now
   honestly marked "Soon" instead of looking interactive and doing
   nothing.
5. **`Entrance`'s reduced-motion check crashed on first run**, found
   immediately during Android device testing: `MediaQuery.of(context)`
   was called inside `initState()`, which Flutter explicitly disallows
   (the element isn't fully attached yet) — every screen using `Entrance`
   threw a red-screen assertion on load. Moved the check into
   `didChangeDependencies()` with a start-once guard. This is the kind of
   bug static analysis (`flutter analyze`, 0 issues throughout) cannot
   catch — it only surfaced through actually launching the app on the
   emulator, exactly per this mission's "don't go backwards" mandate.
6. **Block-a-user had zero confirmation.** Selecting "Block user" from a
   profile's menu fired immediately with no confirmation step, for an
   action the brief itself calls out as needing to be "deliberate." Added
   a confirmation dialog before the block call (report and unblock remain
   single-tap, matching their lower-stakes nature).

## 14. Remaining UX issues (not fixed this pass)

- Icon-only top-bar buttons in the feed app bar (add/events/chat/bell)
  don't carry explicit `Semantics`/`tooltip` labels for screen readers —
  a real accessibility gap, not fixed in this pass (§9).
- No dedicated "offline/reconnecting" banner or state — the app still
  relies on per-screen error states (now calmer and consistent via
  `EmptyState`) rather than a single global connectivity indicator. Real
  network-interruption testing (airplane-mode toggling) was not performed
  in this pass; it's a device-level test matrix orthogonal to the visual
  work here.
- Club "Members" and platform Events creation remain stubs
  ("coming soon" snackbars) — confirmed again this pass that nothing
  security- or correctness-relevant depends on them; left untouched per
  the brief's explicit instruction not to build missing product surfaces.
- The 90-second anonymous-chat message lifetime made live multi-account
  round-trip testing of that specific screen impractical within this
  pass; its send/receive/dedupe logic was not touched (colors only), and
  was already live-verified in the prior hardening pass.

## 15. Deferred improvements

- A systematic `const`-constructor and rebuild-minimization audit across
  all 37 touched files (one round of `dart fix --apply` was run to
  resolve the lints the analyzer already flagged — see §10 — but a deeper
  performance pass, e.g. converting more subtrees to `const` or splitting
  large `build()` methods, was out of scope for a visual-design pass).
- Lazy tab mounting for `BottomNavShell` (only build/subscribe a tab the
  first time it's actually selected, rather than all five up front) — a
  possible follow-up to the `IndexedStack` tradeoff in §10 if Realtime
  connection count ever becomes a real concern.
- A full text-scale-factor stress test (rendering every touched screen at
  200% system font size) was not performed; layouts were built using
  `Theme` text styles and `Flexible`/`Expanded` with overflow handling
  where text length varies, but not explicitly verified at extreme scale
  factors.
- Explicit `Semantics` labeling pass for icon-only controls (§14).

## 16. Tests run

- `flutter analyze` — **0 issues**, checked repeatedly through the pass
  (after every batch of screen edits) and again at the end.
- `flutter test` — **46/46 passing**: the 37 tests already in the suite
  (unchanged, all still green), plus 9 new tests added this pass:
  - `test/relative_time_test.dart` (6 cases) — covers `relativeTime()`'s
    "just now" / minutes / hours / days / weeks / absolute-date
    boundaries, the new utility behind notification and chat-list
    timestamps.
  - `test/avatar_test.dart` (3 cases) — covers `AppAvatar`'s initials
    fallback: first-letter extraction, uppercasing, and the "?" fallback
    for an empty name.
- Live, on-device validation on the Android emulator (`emulator-5554`,
  API 35), signed in as the real beta account `beta-a@nmit.ac.in` against
  the live Supabase project — not a mock, not a cold static read of the
  code. Exercised: welcome → signup (college dropdown, unified list
  confirmed) → login → feed (posts rendering, including the fixed
  text-only-post case; like button optimistic update, count `1→2`
  confirmed live) → profile (avatar, stats including the previously-fixed
  `clubs_count`, empty-posts state) → settings (Account → EditProfileScreen
  navigation, Privacy "Soon" chip, anonymous-ID section) → clubs (list,
  club detail hero, admin dashboard card) → club chat (bubble grouping/
  tail rendering with real multi-sender history, live message send
  end-to-end) → 1:1 chat (bubble + status-icon rendering with real
  history) → chats list (relative-time display) → anonymous home and
  anonymous college chat (identity preserved, empty state, composer). The
  `Entrance` reduced-motion crash (§13.5) was caught and fixed entirely
  through this process, not through code review.

---

**UI/UX transformation complete.**
