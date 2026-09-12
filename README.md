# College App

A cross-platform **college community app** built with Flutter — a private social network for students, with a feed, Snapchat-style moments, chat, clubs, and events.

## ✨ Features

- **Authenticated community** — Email & Google sign-in via Firebase Auth, gated to recognized college emails (`.edu`, `.ac.in`, and partner colleges).
- **Feed** — Post updates, like and comment, see others' posts.
- **Moments** — Snapchat-style disappearing photo/video moments from the in-app camera.
- **Chat** — 1:1 and group conversations.
- **Clubs** — Join/create clubs, club chats, announcements, member management, and admin dashboards.
- **Events** — Discover and create campus events.
- **Anonymous chat** — College-verified anonymous group chats.
- **Notifications** — Push notifications via Firebase Cloud Messaging.
- **Search & profiles** — Find people, public profiles, friends list.
- **Moderation** — Text filtering and moderation tooling.

## 🧱 Tech Stack

| Layer | Choice |
| --- | --- |
| Client | [Flutter](https://flutter.dev) (Android, iOS, macOS, Linux, Windows, Web) |
| Auth & database | [Firebase Auth](https://firebase.google.com/products/auth) + [Cloud Firestore](https://firebase.google.com/products/firestore) |
| Push notifications | [Firebase Cloud Messaging](https://firebase.google.com/products/cloud-messaging) |
| Cloud functions | [Firebase Cloud Functions](https://firebase.google.com/products/functions) |
| File storage | [Supabase Storage](https://supabase.com) |
| Camera / media | `camera`, `video_player`, `image_picker` |

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.3.0`
- A [Firebase project](https://console.firebase.google.com) with **Authentication**, **Firestore**, **Cloud Functions**, and **Cloud Messaging** enabled
- A [Supabase project](https://supabase.com) with a storage bucket (for moments/media)

### Setup

1. **Clone the repo**

   ```bash
   git clone https://github.com/navdeepcodes/college-app.git
   cd college-app
   ```

2. **Add Firebase config**

   Create your platform config files — `lib/firebase_options.dart` (enable `flutterfire configure`) and, for iOS, `GoogleService-Info.plist`.

   > ⚠️ `lib/secrets.dart` is **git-ignored** and not committed. Create it locally with your app keys:
   >
   > ```dart
   > // lib/secrets.dart — never commit this file
   > class Secrets {
   >   static const String supabaseUrl = '...';
   >   static const String supabaseAnonKey = '...';
   > }
   > ```

3. **Get dependencies & run**

   ```bash
   flutter pub get
   flutter run
   ```

## 📁 Project Structure

```
lib/
├── anon/           # Anonymous college chat
├── app/            # App-level wiring (auth gate)
├── auth/           # Login, signup, profile setup, college detection
├── chat/           # Direct & group messaging
├── clubs/          # Clubs, club admin, club chats & events
├── constants/      # College lists & maps
├── core/           # Theme, colors, shared widgets
├── events/         # Campus events
├── feed/           # Home feed, posts, comments
├── models/         # Post & user models
├── moderation/     # Text filtering & moderation
├── moments/        # Snapchat-style stories (camera + video)
├── navigation/     # Bottom nav shell
├── notifications/  # Push notifications & friend requests
├── profile/        # Profiles, friends, settings
├── search/         # People search
├── services/       # Firebase/Supabase service layers
├── widgets/        # Shared widgets
├── main.dart       # Entry point
└── secrets.dart    # Local API keys (NOT committed)
```

Deployment config for Firebase (rules, indexes, functions) lives in `firebase.json`, `firestore.rules`, `firestore.indexes.json`, and `functions/`. Supabase config (including the `cleanup-moments` edge function) lives in `supabase/`.

## 📄 License

All rights reserved unless otherwise stated.