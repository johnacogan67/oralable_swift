# App Store Connect In-App Purchase Configuration Guide

**Related:** [LAUNCH_READINESS_CHECKLIST.md](./LAUNCH_READINESS_CHECKLIST.md) · [APP_STORE_METADATA.md](./APP_STORE_METADATA.md)

## Overview

This guide walks you through creating all subscription products in App Store Connect for both Oralable apps. This **MUST** be completed before App Store release.

##Prerequisites

- Apple Developer account with Admin or App Manager role
- Both apps created in App Store Connect:
  - **Oralable** (Patient App) - Bundle ID: `com.jacdental.oralable`
  - **Oralable for Dentists** - Bundle ID: `com.jacdental.oralable.dentist`
- Paid developer program membership ($99/year)
- Tax and banking information configured in App Store Connect

---

## Product Summary

### Patient App (Oralable)
- **1 Subscription Group**: "Oralable Premium"
- **2 Products**: Monthly + Yearly

### Dentist App (Oralable for Dentists)
- **1 Subscription Group**: "Oralable for Dentists"
- **4 Products**: Professional Monthly/Yearly + Practice Monthly/Yearly

---

## Part 1: Patient App (Oralable) - Subscriptions

### Step 1: Access In-App Purchases

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **My Apps**
3. Select **Oralable** (Patient App)
4. Click **In-App Purchases** in the left sidebar
5. Click the **+** button to create a new subscription group

### Step 2: Create Subscription Group

1. Click **Auto-Renewable Subscriptions**
2. Create new subscription group:
   - **Reference Name**: `Oralable Premium`
   - **Group Number**: Leave as auto-assigned
3. Click **Create**

### Step 3: Add Subscription Products

#### Product 1: Premium Monthly

1. Click **+** to add new subscription
2. Fill in details:

**Product Information:**
- **Reference Name**: `Premium Monthly`
- **Product ID**: `com.jacdental.oralable.premium.monthly`
  - ⚠️ IMPORTANT: Must match exactly - cannot be changed after creation
- **Subscription Group**: Select "Oralable Premium"

**Subscription Duration:**
- Select: **1 Month**

**Subscription Prices:**
1. Click **Add Pricing**
2. Select **Pricing Template** or **Manual Pricing**
3. Base Country: **Ireland (EUR)**
4. Price: **€9.99 / month**
5. Click **Next**
6. Review converted prices for other regions
7. Click **Create**

**Subscription Localizations:**
1. Click **Add Localization**
2. Language: **English (U.S.)**
3. Fields to fill:
   - **Display Name**: `Oralable Premium Monthly`
   - **Description**: `Unlock unlimited dentist sharing, advanced analytics, and unlimited data export. Manage your oral health data with comprehensive tools and insights.`
4. Click **Save**

**App Store Promotion (Optional):**
- **Promotional Image**: 1600x1200px image showing premium features
- Leave unchecked for now - can add later

4. Click **Save**

#### Product 2: Premium Yearly

1. Click **+** to add new subscription
2. Fill in details:

**Product Information:**
- **Reference Name**: `Premium Yearly`
- **Product ID**: `com.jacdental.oralable.premium.yearly`
- **Subscription Group**: Select "Oralable Premium"

**Subscription Duration:**
- Select: **1 Year**

**Subscription Prices:**
- Base Country: **Ireland (EUR)**
- Price: **€99.99 / year**

**Subscription Localizations:**
- Language: **English (U.S.)**
- **Display Name**: `Oralable Premium Yearly`
- **Description**: `Unlock unlimited dentist sharing, advanced analytics, and unlimited data export. Save 17% with annual billing. Manage your oral health data with comprehensive tools and insights.`

3. Click **Save**

### Step 4: Configure Subscription Group Settings

1. Go back to Subscription Group: "Oralable Premium"
2. Click **Subscription Group Localizations**
3. Add English (U.S.) localization:
   - **Subscription Group Display Name**: `Oralable Premium`
   - **Custom App Name**: `Oralable`

### Step 5: Set Up Free Tier (Optional)

The app has a free tier with limited features (1 dentist share, basic export). This doesn't require an IAP product - it's handled in code when no subscription is active.

**Free Tier Features** (from code analysis):
- 1 dentist connection
- Basic data export (CSV only)
- Daily summaries only
- Real-time monitoring (full access)
- Recording sessions (full access)

---

## Part 2: Dentist App (Oralable for Dentists) - Subscriptions

### Step 1: Access In-App Purchases

1. In App Store Connect, go to **My Apps**
2. Select **Oralable for Dentists**
3. Click **In-App Purchases**
4. Click **+** to create subscription group

### Step 2: Create Subscription Group

1. Click **Auto-Renewable Subscriptions**
2. Create new subscription group:
   - **Reference Name**: `Oralable for Dentists`
   - **Group Number**: Leave as auto-assigned
3. Click **Create**

### Step 3: Add Subscription Products

#### Product 1: Professional Monthly

**Product Information:**
- **Reference Name**: `Professional Monthly`
- **Product ID**: `com.jacdental.oralable.dentist.professional.monthly`
- **Subscription Group**: "Oralable for Dentists"
- **Subscription Duration**: 1 Month
- **Subscription Level**: 1 (Lower tier)

**Pricing:**
- Base: €29.99/month

**Localization:**
- **Display Name**: `Professional Monthly`
- **Description**: `Connect with up to 50 patients. Access real-time bruxism data, historical trends, and detailed analytics. Perfect for individual practitioners.`

#### Product 2: Professional Yearly

**Product Information:**
- **Reference Name**: `Professional Yearly`
- **Product ID**: `com.jacdental.oralable.dentist.professional.yearly`
- **Subscription Group**: "Oralable for Dentists"
- **Subscription Duration**: 1 Year
- **Subscription Level**: 1

**Pricing:**
- Base: €299.99/year

**Localization:**
- **Display Name**: `Professional Yearly`
- **Description**: `Connect with up to 50 patients. Access real-time bruxism data, historical trends, and detailed analytics. Save 17% with annual billing.`

#### Product 3: Practice Monthly

**Product Information:**
- **Reference Name**: `Practice Monthly`
- **Product ID**: `com.jacdental.oralable.dentist.practice.monthly`
- **Subscription Group**: "Oralable for Dentists"
- **Subscription Duration**: 1 Month
- **Subscription Level**: 2 (Higher tier)

**Pricing:**
- Base: €99.99/month

**Localization:**
- **Display Name**: `Practice Monthly`
- **Description**: `Unlimited patient connections for your dental practice. Full access to all features including advanced analytics, export tools, and multi-provider support.`

#### Product 4: Practice Yearly

**Product Information:**
- **Reference Name**: `Practice Yearly`
- **Product ID**: `com.jacdental.oralable.dentist.practice.yearly`
- **Subscription Group**: "Oralable for Dentists"
- **Subscription Duration**: 1 Year
- **Subscription Level**: 2

**Pricing:**
- Base: €999.99/year

**Localization:**
- **Display Name**: `Practice Yearly`
- **Description**: `Unlimited patient connections for your dental practice. Full access to all features including advanced analytics, export tools, and multi-provider support. Save 17% with annual billing.`

### Step 4: Configure Subscription Group Settings

1. Subscription Group Localization:
   - **Display Name**: `Oralable for Dentists`
   - **Custom App Name**: `Oralable for Dentists`

### Step 5: Set Up Free Tier

**Starter Tier** (Free):
- 5 patient connections maximum
- Basic patient data viewing
- No advanced analytics

This is handled in code when no subscription is active.

---

## Part 3: Test Your Subscriptions

### Step 1: Enable StoreKit Configuration

1. In Xcode, select your scheme (Edit Scheme → Run)
2. Go to **Options** tab
3. Under **StoreKit Configuration**, select:
   - For Patient App: `Configuration.storekit`
   - For Dentist App: `DentistConfiguration.storekit`
4. Build and run

### Step 2: Create Sandbox Test Accounts

1. In App Store Connect, go to **Users and Access**
2. Click **Sandbox Testers** in sidebar
3. Click **+** to add tester
4. Fill in details:
   - **Email**: Use a unique email (can be fake, e.g., `test1@example.com`)
   - **Password**: Strong password
   - **Country/Region**: Ireland (to match EUR pricing)
   - **Birth Date**: Set to 18+ years old
5. Click **Invite**
6. Repeat to create at least 2 testers (one patient, one dentist)

### Step 3: Test Purchase Flow

**Patient App:**
1. Sign out of your personal App Store account on device
2. Run Patient App (from Xcode or TestFlight)
3. Navigate to subscription screen
4. Tap "Subscribe to Premium Monthly"
5. When prompted, use sandbox test account credentials
6. Complete "purchase" (no actual charge)
7. Verify subscription activates in app

**Dentist App:**
1. Run Dentist App
2. Try connecting to >5 patients (should hit free tier limit)
3. Navigate to subscription screen
4. Purchase Professional Monthly
5. Verify patient limit increases to 50

### Step 4: Test Subscription States

Test these scenarios:
- ✓ Free tier limitations work correctly
- ✓ Subscription unlock features
- ✓ Upgrade from Monthly to Yearly
- ✓ Downgrade from Practice to Professional
- ✓ Subscription renewal (fast-forward time in sandbox)
- ✓ Subscription expiry behavior
- ✓ Restore purchases after reinstall

---

## Part 4: Submission Preparation

### Step 1: Submit Products for Review

Before submitting the app:

1. For each product in App Store Connect:
   - Ensure status shows "Ready to Submit"
   - Click **Submit for Review**
2. Products must be approved BEFORE app can be released
3. Approval typically takes 24-48 hours

### Step 2: Add Screenshots (Required)

For each subscription product:
1. Upload promotional screenshot (1600x1200px)
2. Show key features unlocked by subscription
3. Use consistent branding with app screenshots

### Step 3: App Privacy

In App Store Connect, under **App Privacy**:

1. Add data type: **Purchases**
   - Collected: Yes
   - Linked to user: Yes
   - Used for tracking: No
   - Purpose: App functionality

---

## Part 5: Tax & Legal

### Tax Information

1. In App Store Connect, go to **Agreements, Tax, and Banking**
2. Ensure these are completed:
   - ✓ Paid Applications Agreement signed
   - ✓ Tax forms submitted (W-8BEN for non-US, W-9 for US)
   - ✓ Banking information provided for payouts

### Pricing Notes

- Prices are in EUR (Euro) as base currency
- Apple auto-converts to all App Store regions
- Apple takes 30% commission (70% to you)
- After 1 year of active subscription: 85% to you (15% to Apple)

**Example Revenue** (Premium Monthly at €9.99):
- Month 1-12: €6.99 per subscriber per month
- Month 13+: €8.49 per subscriber per month

---

## Part 6: Post-Launch Monitoring

### Key Metrics to Track

1. **Subscriber Count**:
   - Patient Premium: Target 100+ in first 3 months
   - Dentist Professional: Target 20+ in first 3 months

2. **Conversion Rate**:
   - Free → Premium: Industry average 2-5%
   - Free → Professional: Higher expected for B2B (10-20%)

3. **Churn Rate**:
   - Target: <5% monthly churn
   - Monitor reasons for cancellations

4. **Revenue**:
   - Track MRR (Monthly Recurring Revenue)
   - Calculate LTV (Lifetime Value) per subscriber

### Where to Monitor

- **App Store Connect** → **Sales and Trends**
- **App Analytics** → **Subscriptions**
- **Reports** → Download detailed CSV reports

---

## Troubleshooting

### Problem: "Product IDs don't match"
**Solution**: Product IDs in App Store Connect MUST exactly match the IDs in your code:
- Check `SubscriptionManager.swift` lines 28-35 (Patient App)
- Check `DentistSubscriptionManager.swift` (Dentist App)

### Problem: "Products not loading in app"
**Solution**:
1. Verify products are "Ready for Sale" status
2. Check app bundle ID matches exactly
3. Wait 24 hours after creating products (propagation delay)
4. Use sandbox account, not personal Apple ID

### Problem: "Sandbox purchase fails"
**Solution**:
1. Ensure StoreKit configuration is selected in scheme
2. Sandbox tester email must not be a real Apple ID
3. Sign out of real App Store account on device

### Problem: "Subscription doesn't renew"
**Solution**:
- Sandbox subscriptions renew fast (5 minutes = 1 month)
- Maximum 6 renewals in sandbox, then auto-cancels
- This is normal sandbox behavior

---

## Estimated Time

- Creating subscription groups: 30 minutes
- Adding all 6 products: 2 hours
- Localization and metadata: 1 hour
- Sandbox testing: 2 hours
- **Total: 5-6 hours**

---

## Pricing Strategy Recommendations

### Patient App

**Current Pricing**: €9.99/mo or €99.99/yr

**Considerations**:
- Health/wellness apps typically range €5-15/month
- Offering yearly discount (17% off) encourages annual commitment
- Free tier is essential for user acquisition

**Alternative Strategy**:
- Add mid-tier at €4.99/month (2 dentist shares, limited export)
- This can increase conversion from free users

### Dentist App

**Current Pricing**:
- Professional: €29.99/mo (50 patients)
- Practice: €99.99/mo (unlimited)

**Considerations**:
- B2B pricing - dentists can expense this
- €300/year is reasonable for practice management tool
- Consider offering 30-day free trial to convert dentists

**Alternative Strategy**:
- Add per-patient pricing: €1/patient/month (scales better)
- Offer practice-wide licenses for multi-provider offices

---

## Next Steps

After completing IAP setup:

1. Test thoroughly with sandbox accounts
2. Submit products for review (before app submission)
3. Complete app screenshots and metadata
4. Submit both apps for TestFlight Beta Review
5. Recruit beta testers (patients and dentists)
6. Monitor beta feedback
7. Submit for App Store Review

---

## Resources

- [Apple Subscriptions Best Practices](https://developer.apple.com/app-store/subscriptions/)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [Subscription Pricing Guide](https://developer.apple.com/app-store/subscriptions/)
