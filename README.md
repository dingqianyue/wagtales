# Wagtales

A social app for pets of all kinds: give each pet a profile, share photo posts, follow other pets and people, and message their owners. Built with Swift, SwiftUI, and Supabase.

## Features

**Accounts**
- Email sign-up, log-in, and password reset (Supabase Auth)
- Username validation: unique, must start with a letter, and only lowercase letters, numbers, and underscores
- Editable user profile with a photo and optional public details

**Pet profiles**
- Add and edit pets with a photo, species, breed, gender, birthday (exact or approximate), and personality
- Age shown automatically, plus a birthday badge on the pet's birthday
- Co-ownership: add other users as co-owners so they can manage the pet too
- Memorial mode for pets that have passed away

**Feed and posts**
- Home feed with Following and Explore tabs
- Square photo posts with likes, saves, and comments
- Photos are center-cropped, resized, and compressed on the device before upload
- Threaded comments with likes and deletion
- Reusable post grid on user and pet profiles

**Social**
- Follow pets and people, with follower and following lists
- Search for users, pets, and posts
- Public profile pages

**Messaging**
- Inbox with the latest message from each conversation and unread indicators
- One-to-one chat
- Anti-spam rule: a first message can't be followed by another until the recipient replies

**Backend (Supabase)**
- Relational Postgres schema for users, pets, co-ownership, posts, follows, comments, and messages
- Row level security on every table: users can only change their own data, only existing owners can add pet co-owners, and messages are visible only to the sender and receiver
- Database triggers keep like, save, and comment counts in sync
- Foreign keys cascade, so removing a user cleans up all of their data, and pets left with no owners are deleted too
- Inbox query runs as a Postgres function that can only return the signed-in user's conversations
- Storage buckets for avatars and post photos, where users can only delete their own uploads
- Schema kept as versioned SQL migrations

**In progress (UI prototypes with mock data)**
- Community map showing nearby pets and reported hazards, with location-sharing privacy levels (hidden, approximate, or exact, for mutual followers or everyone)

## Tech stack

| Area | Technology |
| --- | --- |
| Language | Swift |
| UI | SwiftUI (iOS 26.2+), PhotosPicker, MapKit |
| Backend | Supabase: Postgres (relational schema), Auth, Storage, and RPC functions |
| Client SDK | [supabase-swift](https://github.com/supabase/supabase-swift) via Swift Package Manager |
| Concurrency | Swift async/await |

## Project structure

```
supabase/migrations/   # Database schema, security rules, and storage setup
apps/ios/Wagtales/
├── Wagtales.xcodeproj
├── Wagtales/          # App entry point, tab navigation, theme, assets
├── Views/             # Feature screens (feed, profiles, chat, map, …)
├── Pet.swift, Post.swift
├── Supabase.swift     # Supabase client setup
├── ImageCompressor.swift
├── LocationManager.swift
├── WagtalesTests/
└── WagtalesUITests/
```

## Running locally

1. Create a Supabase project and apply the migrations, either with the [Supabase CLI](https://supabase.com/docs/guides/cli) (`supabase link`, then `supabase db push`) or by running the files in `supabase/migrations/` in order in the SQL Editor.
2. Open `apps/ios/Wagtales/Wagtales.xcodeproj` in Xcode.
3. In `Supabase.swift`, set your project URL and publishable key.
4. Choose an iOS simulator and run.
