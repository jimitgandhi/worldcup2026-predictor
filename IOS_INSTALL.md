# WC2026 Predictor - iOS Installation Guide

## ⚠️ Admin Setup Required First

**Before users can install**, the admin must configure Firebase Authentication:

👉 **See `FIREBASE_WEB_SETUP.md` for required setup steps**

Without this setup, sign-in will fail with "unauthorized domain" error.

---

## For iPhone Users (Progressive Web App)

Since this app is not on the App Store, iPhone users can install it as a Progressive Web App (PWA). It looks and works just like a native app!

### Installation Steps:

1. **Open Safari** on your iPhone (must be Safari, not Chrome)

2. **Go to the app URL:**
   ```
   https://worldcup2026-predictor-2d036.web.app
   ```

3. **Tap the Share button** (square with arrow pointing up) at the bottom of Safari

4. **Scroll down** and tap **"Add to Home Screen"**

5. **Tap "Add"** in the top right corner

6. **Done!** The app icon will appear on your home screen like any other app

### Using the App:

- **Open from your home screen** (not Safari) for the best experience
- The app will run in full-screen mode (no Safari UI)
- All your predictions and data are saved (uses Firebase)
- Works offline after first load (cached data)

### Notes:

- ✅ All core features work: predictions, leaderboard, profile, admin panel
- ❌ Push notifications are not available on iOS (technical limitation)
- ❌ Share button is hidden on web (but you can screenshot and share manually)
- 🔄 App auto-updates whenever you refresh (no need to reinstall)

### Need Help?

Contact the admin if you have any issues!

---

## For Android Users

Android users should install the native APK for the best experience (includes notifications).

Download: `app-release.apk` (get from admin)
