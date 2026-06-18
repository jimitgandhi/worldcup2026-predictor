# 🔥 Firebase Web App Setup - REQUIRED

## ⚠️ IMPORTANT: Sign-In Won't Work Until You Complete These Steps

The web app is deployed, but Google Sign-In will fail until you authorize the hosting domain in Firebase.

---

## Step-by-Step Setup

### 1. Open Firebase Console

Go to: https://console.firebase.google.com/project/worldcup2026-predictor-2d036/authentication/settings

### 2. Navigate to Authentication Settings

1. Click **Authentication** in the left sidebar
2. Click the **Settings** tab (at the top, next to "Sign-in method")
3. Scroll down to the **Authorized domains** section

### 3. Add Your Hosting Domains

Click **Add domain** and add these two domains (one at a time):

```
worldcup2026-predictor-2d036.web.app
```

```
worldcup2026-predictor-2d036.firebaseapp.com
```

**Why both?** Firebase Hosting provides both domains, and users might access either one.

### 4. Verify the Domains are Listed

After adding, you should see in the authorized domains list:
- ✅ localhost (already there)
- ✅ worldcup2026-predictor-2d036.web.app (you added)
- ✅ worldcup2026-predictor-2d036.firebaseapp.com (you added)

### 5. Test Sign-In

1. Go to: https://worldcup2026-predictor-2d036.web.app
2. Click "Sign in with Google"
3. Should now work! ✅

---

## Troubleshooting

### If Sign-In Still Fails:

1. **Clear browser cache and cookies** for the site
2. **Open browser console** (F12) and look for errors
3. **Verify Google Sign-In is enabled**:
   - In Firebase Console → Authentication → Sign-in method
   - Make sure "Google" provider is **Enabled** (toggle should be green)

### Common Errors:

**Error: "auth/unauthorized-domain"**
- ✅ Fix: Add the hosting domain to authorized domains (steps above)

**Error: "popup closed by user"**
- This is normal if user closes the Google sign-in popup
- Just try signing in again

**Error: "auth/popup-blocked"**
- Browser is blocking popups
- Allow popups for this site in browser settings

---

## What This Does

Firebase Authentication has a security feature that only allows sign-in from authorized domains. By default, only `localhost` is authorized (for development).

When you deploy to Firebase Hosting, you must manually add the hosting domain to the authorized list, otherwise all sign-in attempts will fail with an unauthorized domain error.

This is a **one-time setup** - you won't need to do it again for future deployments.

---

## Alternative: Use Firebase CLI (Advanced)

If you prefer command line:

```bash
# List current authorized domains
firebase auth:domains:list

# Add new domain
firebase auth:domains:add worldcup2026-predictor-2d036.web.app
firebase auth:domains:add worldcup2026-predictor-2d036.firebaseapp.com
```

---

**After completing these steps, the web app will be fully functional!** 🎉
