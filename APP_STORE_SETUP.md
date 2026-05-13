# NoteCrux — App Store Connect Setup Guide

Complete step-by-step guide to register NoteCrux and its subscriptions on App Store Connect. Follow top to bottom. Estimated time: **2–4 hours** (plus 24–48h for Apple review).

---

## 0. Prerequisites (do these first, in order)

| # | Item | Where | Notes |
|---|------|-------|-------|
| 1 | Apple Developer Program membership | [developer.apple.com/programs](https://developer.apple.com/programs/) | $99/year. Individual or Organization. |
| 2 | Paid Apps Agreement signed | App Store Connect → Business → Agreements | **Required for IAPs.** Without this, products can't be created. |
| 3 | Tax forms completed | App Store Connect → Business → Tax | US: W-9 or W-8BEN. EU: VAT info. |
| 4 | Banking info added | App Store Connect → Business → Banking | Where Apple sends payouts. |
| 5 | Bundle ID registered | [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers) | Must match `com.codergautamyt.NoteCrux` (current bundle ID from project). Enable **In-App Purchase** capability. |
| 6 | Privacy policy URL live | Your website | Must load at `https://notecrux.com/privacy` — paywall links to it. |
| 7 | Support URL live | Your website | E.g. `https://notecrux.com/support` — required in App Store Connect. |

> ⚠️ Steps 2–4 can take 24–48h to fully activate. Start these first.

---

## 1. Create the App Record

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**.
2. Fill in:
   - **Platform:** iOS
   - **Name:** `NoteCrux` (shown in App Store; 30 chars max)
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** `com.codergautamyt.NoteCrux` (from the dropdown)
   - **SKU:** `NOTECRUX-IOS-001` (internal, any unique string)
   - **User Access:** Full Access
3. Click **Create**.

---

## 2. Create the Subscription Group

A **subscription group** lets users upgrade/downgrade between plans at the same tier. Monthly and Yearly must live in the **same group**.

1. In App Store Connect → **My Apps** → **NoteCrux** → sidebar → **Subscriptions** → **Create** (next to Subscription Groups).
2. **Reference Name:** `NoteCrux Pro` (internal only)
3. Click **Create**.
4. Inside the group → **Localization** → **Add Localization** → English (U.S.):
   - **Subscription Group Display Name:** `NoteCrux Pro`
5. Save.

---

## 3. Create the Monthly Subscription

Inside the `NoteCrux Pro` group → **Create** (next to Subscriptions).

### 3.1 Basic info
| Field | Value |
|-------|-------|
| Reference Name | `NoteCrux Pro Monthly` |
| Product ID | `com.notecrux.pro.monthly` |

> ⚠️ Product ID **must match exactly** what's in `SubscriptionManager.swift:28`. Typos = products won't load.

### 3.2 Subscription Duration
- **1 Month**

### 3.3 Subscription Prices
- Click **Add Subscription Price** → select **USD $4.99** as base tier.
- Apple auto-calculates all other currencies. Review them, tweak if needed for key markets (EUR, GBP, JPY, etc.).

### 3.4 Localization (English — U.S.)
Click **Add Localization** → **English (U.S.)**:

| Field | Value |
|-------|-------|
| Subscription Display Name | `NoteCrux Pro Monthly` |
| Description | `Unlock unlimited meetings, AI summaries, smart insights, unlimited tasks, and full export. Billed monthly, cancel anytime.` |

### 3.5 Review Information
- **Screenshot:** Required. See [Section 5](#5-review-screenshots).
- **Review Notes:** `Paywall accessible from Settings → Upgrade, or when hitting free limits (3 meetings/mo, 10 tasks, 1 AI insight/day). Test purchase using sandbox account.`

### 3.6 Save (don't submit yet — we'll submit everything together with the app).

---

## 4. Create the Yearly Subscription

Same subscription group (`NoteCrux Pro`) → **Create**.

### 4.1 Basic info
| Field | Value |
|-------|-------|
| Reference Name | `NoteCrux Pro Yearly` |
| Product ID | `com.notecrux.pro.yearly` |

### 4.2 Subscription Duration
- **1 Year**

### 4.3 Subscription Prices
- **USD $39.99** as base tier.

### 4.4 Localization (English — U.S.)
| Field | Value |
|-------|-------|
| Subscription Display Name | `NoteCrux Pro Yearly` |
| Description | `Unlock unlimited meetings, AI summaries, smart insights, unlimited tasks, and full export. Billed yearly — save 33% vs monthly.` |

### 4.5 Review Information
- **Screenshot:** Required. Same paywall screen as monthly is fine.
- **Review Notes:** Same as monthly.

### 4.6 Save.

---

## 5. Review Screenshots

Apple requires **one screenshot per subscription product** showing the paywall where users can purchase it.

### Spec
- **Format:** PNG or JPEG
- **Dimensions:** 640 × 920 min (iPhone) or larger. Any iPhone screenshot size works.
- **Content:** Must show the subscription title, price, and duration clearly visible in your app UI.

### How to capture
1. Open Xcode → run NoteCrux on iPhone 16 Pro simulator (or similar).
2. Trigger the paywall:
   - Settings → Upgrade to Pro, **or**
   - Try to create a 4th meeting (free limit triggers it)
3. Take screenshot (`Cmd+S` in simulator, or Device → Screenshot)
4. Upload the **same image** to both monthly and yearly products' Review Information.

---

## 6. App Privacy (data collection disclosure)

App Store Connect → **NoteCrux** → **App Privacy**.

NoteCrux is local-first, so most answers are "No". Based on the code:

| Question | Answer | Reason |
|----------|--------|--------|
| Do you collect data? | **No** (if fully offline) OR **Yes** (if any analytics/crash logging is added) | Audit before submitting. Check for Firebase, Sentry, etc. |
| Contact Info | No | |
| Health & Fitness | No | |
| Financial Info | No | |
| Location | No | |
| Sensitive Info | No | |
| Contacts | No | |
| User Content (audio, transcripts) | **Stored locally only** — not "collected" per Apple's definition | |
| Identifiers | No | |
| Usage Data | No | Unless you add analytics |
| Diagnostics | No | Unless you add crash reporting |

> ⚠️ If you add analytics/crash reporting later, update this section before the next release.

---

## 7. App Information & Metadata

App Store Connect → **NoteCrux** → **App Information**.

### General
| Field | Value |
|-------|-------|
| Primary Category | Productivity |
| Secondary Category | Business |
| Content Rights | You own or have license for all content |
| Age Rating | Complete questionnaire — likely **4+** |

### Privacy Policy URL
`https://notecrux.com/privacy` — **must be live before submission**.

### Localizable Info (English — U.S.)
| Field | Value |
|-------|-------|
| Subtitle | `AI Meeting Notes & Tasks` (30 char max) |
| Privacy Policy URL | `https://notecrux.com/privacy` |

---

## 8. Prepare the Version for Submission

App Store Connect → **NoteCrux** → **iOS App** → version **1.0** (create if needed).

### Required fields
| Field | Value |
|-------|-------|
| Promotional Text | `AI-powered meeting notes, fully on-device. Record, summarize, extract action items. Your data never leaves your phone.` (170 char max) |
| Description | Longer marketing copy. Emphasize: local AI, privacy, unlimited meetings (Pro), export, insights. |
| Keywords | `meeting notes,ai transcription,voice memo,productivity,action items,tasks,summary,offline,private` (100 char max, comma-separated) |
| Support URL | `https://notecrux.com/support` |
| Marketing URL | Optional |
| Version | `1.0` |
| Copyright | `2026 Kaspar Works` |

### Screenshots
Apple requires screenshots for at minimum:
- **6.9" iPhone** (iPhone 16 Pro Max): 1320 × 2868 or 2868 × 1320
- **6.5" iPhone** (iPhone 14 Plus): 1242 × 2688

Provide **3–10 screenshots** each size. Recommended shots:
1. Dashboard with meetings list
2. Recording in progress
3. AI-generated insights / summary view
4. Paywall (`NoteCrux Pro`)
5. Tasks view
6. Settings / privacy

### App Review Information
| Field | Value |
|-------|-------|
| Sign-in Required | **No** (unless you add auth) |
| Contact Info | Your name, email, phone |
| Notes | `NoteCrux is local-first — all processing happens on-device using Apple's Foundation Models. No login required. Free tier: 3 meetings/month, 10 tasks, 1 AI insight/day. Pro: unlimited via monthly ($4.99) or yearly ($39.99) subscription. Paywall appears in Settings → Upgrade, or when hitting free limits.` |

---

## 9. Build Upload

1. In Xcode: **Product → Archive** (make sure scheme is on "Any iOS Device").
2. Organizer opens → **Distribute App** → **App Store Connect** → **Upload**.
3. Wait ~10–30 min for processing.
4. Back in App Store Connect → **iOS App** → **Build** → select the uploaded build.
5. Answer the **Encryption Export Compliance** question (for standard apps: `No` to "uses non-exempt encryption" unless you added custom crypto).

---

## 10. Link Subscriptions to the Version

In the version page (e.g. 1.0) → scroll to **In-App Purchases and Subscriptions** → **+** → select both:
- `NoteCrux Pro Monthly`
- `NoteCrux Pro Yearly`

This makes them ship **with this version**.

---

## 11. Sandbox Test BEFORE Submitting

**Critical — do this or you risk rejection.**

### Create a sandbox tester
1. App Store Connect → **Users and Access** → **Sandbox Testers** → **+**.
2. Create one with a fresh fake email (not your real Apple ID).
3. On your physical iPhone: **Settings → App Store → Sandbox Account → Sign In**.

### Test flow on a physical device
1. Archive build → **Distribute App** → **TestFlight & App Store** → upload.
2. Install via TestFlight on your device.
3. Open NoteCrux → hit the paywall → tap **Subscribe Yearly**.
4. Sandbox purchase prompt appears → confirm.
5. Verify:
   - `isSubscribed` flips to true
   - Pro features unlock (unlimited meetings, insights tab, bulk export)
   - Restore Purchases button works after reinstall

> ⚠️ Sandbox purchases use **accelerated renewal** (1 year = 1 hour, 1 month = 5 min). Useful for testing renewal flow.

### Simulator testing
With the StoreKit config now wired to the scheme, you can also test purchases in the simulator without a sandbox account. Xcode → Debug → StoreKit → Manage Transactions to simulate renewals, failures, etc.

---

## 12. Submit for Review

1. On the version page, scroll to **Submit for Review**.
2. Answer:
   - **Export Compliance:** No (standard)
   - **Content Rights:** Yes (you own the content)
   - **Advertising Identifier (IDFA):** No
3. Click **Submit**.
4. Review typically takes **24–48 hours**.

**Both the app AND the two subscription products are reviewed together** on first submission.

---

## 13. Common Rejection Reasons — Avoid These

| Reason | Prevention |
|--------|------------|
| Privacy policy URL 404 | Verify `https://notecrux.com/privacy` loads before submitting |
| Paywall missing auto-renew disclosure | ✅ Already fixed in `PaywallView.swift` |
| No restore purchases button | ✅ Already present |
| Subscription screenshot missing | Upload identical screenshot to both products |
| Product IDs don't match code | Verify `com.notecrux.pro.monthly` / `com.notecrux.pro.yearly` exactly |
| Paid Apps Agreement not signed | Confirm in App Store Connect → Business → Agreements |
| Review notes missing how to trigger paywall | ✅ Included in template above |

---

## 14. Post-Launch Checklist

After approval:
- [ ] Monitor App Store Connect → Analytics → Subscriptions for conversion
- [ ] Set up subscription status server notifications (optional, for receipt validation)
- [ ] Watch App Store reviews for paywall friction complaints
- [ ] Plan price experiments via App Store Connect (no code change needed)

---

## Quick Reference — Exact Strings the Code Expects

From `SubscriptionManager.swift`:

```
Monthly Product ID: com.notecrux.pro.monthly
Yearly Product ID:  com.notecrux.pro.yearly
```

From `PaywallView.swift`:
```
Privacy Policy:  https://notecrux.com/privacy
Terms of Use:    https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

If you change any of these, update both the code and App Store Connect.

---

## Final Pre-Submission Checklist

- [ ] Paid Apps Agreement signed
- [ ] Tax + banking info complete
- [ ] Bundle ID `com.codergautamyt.NoteCrux` has IAP capability
- [ ] App record created on App Store Connect
- [ ] Subscription group `NoteCrux Pro` created
- [ ] `com.notecrux.pro.monthly` created with localization + screenshot
- [ ] `com.notecrux.pro.yearly` created with localization + screenshot
- [ ] Privacy policy live at `https://notecrux.com/privacy`
- [ ] Support URL live
- [ ] App privacy questionnaire complete
- [ ] App screenshots uploaded (at least 6.9" and 6.5")
- [ ] App description, keywords, promo text filled in
- [ ] Build uploaded via Xcode Archive
- [ ] Both subscriptions linked to the version
- [ ] Sandbox purchase tested on physical device
- [ ] Submit for Review clicked
