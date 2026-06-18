# WC 2026 Predictor 🏆⚽

A Flutter app for predicting FIFA World Cup 2026 match scores with friends. Sign in with Google, submit predictions before kick-off, earn points based on accuracy, and compete on a real-time leaderboard.

> Built for a private group of ~8 friends. Free to run — no paid Firebase services needed.

---

## Scoring System

| Outcome | Points |
|---------|--------|
| 🎯 Exact score (e.g. predicted 2-1, actual 2-1) | **50 pts** |
| 🎯➕ Almost correct (right result + one score exact) | **30 pts** |
| ✅ Correct result only (right winner/draw, wrong scores) | **20 pts** |
| 🎲 One score right | **10 pts** |
| ❌ Wrong | **0 pts** |

---

## Features

- 🔐 **Google Sign-In** — one tap to join
- 📅 **Live match schedule** — Upcoming / Live / Past tabs, synced from ESPN every 60s
- ✏️ **Predict before kickoff** — stepper input, locked once match starts
- 🔒 **Locked badge** — shown when kickoff passed but ESPN hasn't gone live yet
- 🏆 **Real-time leaderboard** — with medals for top 3, tap any user to see their picks
- 📊 **Profile stats** — points breakdown, result accuracy %, prediction history
- 📱 **Share your predictions** — flag emojis included 🇺🇸🇲🇽🇧🇷
- 🔔 **Notifications** — "Last chance!" 10 min before kickoff + post-match result alerts
- ⚙️ **Admin panel** — settle scores, re-settle, manage users, sync ESPN data
- 🌐 **Progressive Web App** — works on iOS/desktop via browser

---

## Tech Stack

| Layer | Technology | Cost |
|-------|-----------|------|
| Frontend | Flutter (Android + Web PWA) | Free |
| Auth | Firebase Authentication (Google) | Free |
| Database | Cloud Firestore | Free (Spark plan) |
| Hosting | Firebase Hosting (PWA) | Free |
| Live Scores | ESPN unofficial API | Free, no key needed |

---

## Setup (Fork & Run)

### 1. Create Firebase project
1. [console.firebase.google.com](https://console.firebase.google.com) → Create project
2. **Authentication** → Sign-in method → Google → Enable
3. **Firestore** → Create database → Production mode → copy rules from `firestore.rules`

### 2. Add your apps
- **Android:** Project Settings → Add app → Android → package `com.worldcup2026.predictor` → download `google-services.json` → place at `predictor_app/android/app/google-services.json`
- **Web:** Project Settings → Add app → Web → copy config into `predictor_app/lib/firebase_options.dart`

### 3. SHA-1 fingerprint (required for Google Sign-In on Android)
```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -alias androiddebugkey -storepass android -keypass android
```
Copy the `SHA1:` line → Firebase Console → Project Settings → Your Android app → Add fingerprint.

### 4. Build
```powershell
cd predictor_app
flutter build apk --release   # Android APK
flutter build web --release   # Web PWA
```

### 5. Make yourself admin
Sign in once, then in Firestore Console → `users` → your doc → add field `isAdmin: true`.

---

## Admin Panel

Tap the **⚙️ icon** in the top-right (admin users only).

| Tab | What it does |
|-----|-------------|
| **Matches** | Settle scores after full time, re-settle if needed, delete predictions per match |
| **Users** | View all users, manually edit points, delete users |
| **Leaderboard** | Current standings, recalculate ranks, copy to clipboard |
| **Danger Zone** | Delete all predictions, sync matches from ESPN, backfill kickoff times, recalculate all scores |

### Match settlement flow
1. ESPN marks match as `finished`
2. App auto-detects (admin must have app open) and shows "Auto-settling..."
3. Admin can also tap **Settle** / **Re-settle** manually at any time
4. Points calculated, leaderboard updated instantly

---

## Project Structure

```
predictor_app/lib/
├── main.dart
├── models/
│   ├── match.dart             # Match model (Firestore + ESPN parsers)
│   ├── prediction.dart        # Prediction + PredictionResult enum
│   └── user_model.dart        # User with points stats + accuracy
├── services/
│   ├── auth_service.dart      # Google Sign-In, user upsert
│   ├── espn_service.dart      # ESPN API (live scores, no key needed)
│   ├── firestore_service.dart # Matches, predictions, settle, leaderboard
│   ├── notification_service.dart # Local notifications + scheduling
│   └── scoring_service.dart   # Points calculation logic
├── screens/
│   ├── login_screen.dart
│   ├── home_shell.dart        # Bottom nav + notification routing
│   ├── schedule_screen.dart   # 3-tab match list + prediction inputs
│   ├── leaderboard_screen.dart
│   ├── profile_screen.dart    # Stats, history, share
│   └── admin_screen.dart      # 4-tab admin panel
└── widgets/
    ├── match_card.dart
    ├── match_widgets.dart     # FlagImage, StatusBadge, ResultChip
    └── shimmer_loading.dart
```

---

## Firestore Schema

```
users/{uid}
  displayName, email, photoUrl, createdAt
  totalPoints, rank
  predictionsCount, exactCount, correctPlusOneCount, correctResultCount, oneScoreCount
  isAdmin (boolean — set manually for admin users)

predictions/{uid}_{matchId}
  userId, matchId, homeTeam, awayTeam
  homeScore, awayScore        ← user's prediction
  kickoffTime                 ← copied from match at submit time
  result, pointsEarned        ← filled by settleMatch()
  createdAt

matches/{matchId}
  homeTeam, awayTeam, homeTeamCode, awayTeamCode
  group, venue, kickoff (Timestamp)
  status: upcoming | live | finished
  homeScore, awayScore        ← final score (set on settle)

notifications/{id}
  userId, matchId, message, read (bool), createdAt
```

---

## Live Score Source

```
https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard
```
No API key needed. Polled every 60s. Schedule screen also refreshes on app resume.

---

## Web / PWA

Deploy to Firebase Hosting (`firebase deploy --only hosting`) and share the `.web.app` URL with your group.

For iOS users: Safari → Share → "Add to Home Screen" for a native-like experience.

> Note: Push notifications and share sheet are disabled on web.

