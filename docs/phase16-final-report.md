# Phase 16 — Overnight Sprint Final Report (Phases 10–16)

**Date:** 2026-09-13
**Branch:** `main` — all Phases 13–16 work committed & pushed at sprint end (see git log)
**Base:** preceding Phases 1–8 (commit `467b52b`) + Phases 9–12 (`ead4526`, `92a7eab`, `4ce2d08`)

---

## What this sprint delivered

| Phase | Outcome | Verified by |
|---|---|---|
| **10 — Auth/profile hardening** | Fixed **two real Firestore rules bugs** that were denying *every* signup/profile-save: `endsWith` (doesn't exist in rules → replaced with RE2 `matches`) and missing-property reads (rules throw on `resource.data.anonId` when absent → guarded with `'k' in map`). Stamped `collegeId` + immutable `anonId` at user-doc creation. | 21 new rules tests |
| **11 — Moderation** | TextFilter wired **before-write** on all 4 write paths (post caption, comments, club chat, 1:1 chat) — block-and-flag with `cleanedText`. Scope + client-side-only limitation documented. | analyzer clean |
| **12 — Code quality** | analyze **47→0**; deprecated-API migrations (`withValues(alpha:)`, `initialValue:`, `publishableKey:`, `adminUid` const); **all** `use_build_context_synchronously` gaps fixed. | `flutter analyze` 0 issues, 32/32 tests |
| **13 — Dependency review** | Removed **4 verified-dead deps** (`camera`, `video_player`, `path_provider`, `firebase_messaging`) — zero imports; pruned ~30 transitive packages; native registrants rebuilt to 0 refs on **all** platforms. **No upgrades** — majors stay deferred (High-tier). | analyze 0, 32/32 tests, registrant grep |
| **14 — Testing + gates** | Analyzer 0 / **32/32 unit** / **149/149 rules** / **index audit: zero gaps** / **secret scan clean**. | see below |
| **15 — Native build blockers** | **Confirmed:** missing `android/app/google-services.json` (while the google-services Gradle plugin is applied) ⇒ **any native Android build hard-fails**. iOS: commented `platform :ios, '13.0'` — soft risk. | doctor: Android SDK healthy otherwise |
| **16 — Final report** | this document | — |

---

## Gate results (Phase 14)

| Gate | Result |
|---|---|
| `flutter analyze` | **No issues found** (0) |
| `flutter test` | **32/32 passed** |
| Rules suite (5 files, emulator) | **149/149 passed, 0 failed** (18+44+40+30+17) |
| Runtime composite-index audit | **No query requires a missing index** — 16 query shapes checked |
| Secret scan (tracked source) | **Clean** — no `svc_`/service-role/API tokens (firebase_options.dart public keys are by-design client config) |
| Dead-dependency scan | camera/video_player/path_provider/firebase_messaging → 0 imports |

---

## Open items handed to the user (verified, decision-required)

1. **[BLOCKER — native Android build]** `android/app/google-services.json` is missing.
   Download from Firebase console (project `navdeep-college-app`, Android package
   `com.navdeep.collegeapp.college_app`) and place at `android/app/google-services.json`,
   then `flutter build apk --debug`. See `docs/phase15-native-build-blockers.md`.
2. **[Index hygiene]** 4 declared indexes have **no matching current query** (verified in the
   Phase 14 audit) — candidates to drop, **confrim with one grep then delete from
   `firestore.indexes.json`**: `club_requests(status↗,createdAt↘)`,
   `chats/{chatId}/messages(toUid↗,status↗)`, `friend_requests(fromUid↗,toUid↗,status↗)`,
   `college_anon_posts(collegeId↗,isHidden↗,createdAt↘)`.
3. **[High-tier dependency majors]** (deferred, documented): firebase_* → 4/6, google_sign_in → 7,
   supabase_flutter → 3, image_picker → 2, flutter_lints → 6, cupertino_icons → 2. Do in a
   dedicated device-test session; see `docs/phase5-dependency-modernization-audit.md`.
4. **[iOS]** confirm `pod install` succeeds with the commented-out platform line (soft risk).
5. **[Live data]** full production Firestore data inspection needs a logged-in
   `firebase` CLI / service-account key (none tracked by design). Run `firebase login`
   then `firebase deploy --only firestore --dry-run` to validate rules against the real
   project.

---

## Sprint constraints — compliance

All 16 phases complied: **no rule weakened** (every fix additive/strict), **no schema
migrations**, **no dependency upgrades**, **no security weakening**, **no credential
exposure** (secret scan clean), **no auth-strategy change**. Deletions were limited to
verified-dead Dart packages/config (`camera*`, `video_player*`, `path_provider*`,
`firebase_messaging`, Moments screens).

---

## Files produced Phases 10–16

```
docs/phase11-moderation-integration.md
docs/phase13-dependency-review.md
docs/phase14-testing-gates.md
docs/phase15-native-build-blockers.md
docs/phase16-final-report.md        (this file)
lib/moderation/text_filter.dart      (+4 write-path integrations)
functions/test-rules/…              (21 new cases in Phases 10–11)
```

Commits Phases 10–16: `ead4526`, `92a7eab`, `4ce2d08`, then the Phase 13–16 consolidated
commit(s) at sprint end (see `git log --oneline -6`).