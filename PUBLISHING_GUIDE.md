# 📱 Kora - App Store Publishing Guide

## 🎯 Pre-Publishing Checklist

### ✅ App Configuration (COMPLETED)
- [x] App name: "Kora"
- [x] Bundle ID: `com.hallden.kora`
- [x] Version: 1.0.0+1
- [x] Category: Social Networking
- [x] Permissions configured

### 📋 Required Assets & Information

## 🍎 Apple App Store Requirements

### 1. Apple Developer Account
- [ ] Apple Developer Program membership ($99/year)
- [ ] App Store Connect access

### 2. App Store Assets
Create these in your design tool:

#### Screenshots (REQUIRED - at least 3, max 10 per size)
- **iPhone 6.7" (1290 × 2796 px)** - iPhone 15 Pro Max
- **iPhone 6.5" (1284 × 2778 px)** - iPhone 14 Plus  
- **iPhone 5.5" (1242 × 2208 px)** - iPhone 8 Plus
- **iPad 12.9" (2048 × 2732 px)** - iPad Pro

#### App Icon
- **1024 × 1024 px** - App Store icon (no transparency, no rounded corners)

### 3. App Store Listing Information

#### Basic Information
- **App Name**: Kora
- **Subtitle**: Authentic Voice Conversations
- **Category**: Primary: Social Networking, Secondary: Lifestyle
- **Age Rating**: 17+ (due to unrestricted web access potential)

#### Description (Max 4000 characters)
```
Kora brings authenticity back to online connections through voice-only conversations. No profiles, no photos, no judgments - just real conversations with real people.

KEY FEATURES:

🎙️ Voice-First Connections
Connect instantly through voice calls. No endless texting, no ghosting - just genuine conversations that matter.

🔄 Smart Matching
Our intelligent matching system connects you with people who share your interests and are looking for meaningful conversations.

⏱️ Structured Conversations
5-minute initial calls help break the ice without pressure. Get conversation starters to keep things flowing naturally.

👥 Build Real Connections
When you click with someone, continue the conversation and build lasting connections based on personality, not appearances.

🔒 Privacy-Focused
Your conversations are private. No recording, no data mining - just secure, encrypted voice calls.

✨ Features:
• Instant voice calling with matched users
• Real-time waveform animations during calls
• Conversation starters to break the ice
• Smart matchmaking based on interests
• 5-minute introductory calls
• Continue conversations with mutual matches
• Monthly minute tracking
• Safe and respectful community

Kora is perfect for:
• People tired of superficial dating apps
• Those seeking genuine friendships
• Anyone looking for meaningful conversations
• People who value personality over appearance

Join Kora today and discover connections that go beyond the surface.
```

#### Keywords (Max 100 characters)
```
voice chat, audio dating, voice calls, social, friends, conversation, talk, meeting, voice only
```

#### Support Information
- **Support URL**: https://kora.app/support (create this)
- **Privacy Policy URL**: https://kora.app/privacy (REQUIRED)
- **Terms of Service URL**: https://kora.app/terms (recommended)

#### Additional Information
- **Copyright**: © 2024 Kora Inc.
- **Trade Representative Contact** (if outside US): Your contact info
- **Routing App Coverage File**: Optional

### 4. iOS Build & Submission Process

```bash
# 1. Clean and get dependencies
flutter clean
flutter pub get
cd ios && pod install && cd ..

# 2. Build for release
flutter build ios --release

# 3. Open in Xcode
open ios/Runner.xcworkspace

# 4. In Xcode:
# - Select "Any iOS Device" as build target
# - Product → Archive
# - Distribute App → App Store Connect
# - Upload
```

## 🤖 Google Play Store Requirements

### 1. Google Play Console
- [ ] Google Play Developer account ($25 one-time fee)
- [ ] Accept developer agreement

### 2. Play Store Assets

#### Screenshots (REQUIRED - at least 2, max 8)
- **Phone**: 16:9 aspect ratio (1080 × 1920 px recommended)
- **Tablet**: 16:9 aspect ratio (1920 × 1080 px) - optional but recommended

#### Graphics
- **App Icon**: 512 × 512 px (PNG, no transparency)
- **Feature Graphic**: 1024 × 500 px (displayed at top of listing)

### 3. Play Store Listing Information

#### Store Listing
- **App name**: Kora
- **Short description** (80 chars): "Connect through authentic voice conversations. Real people, real talks."
- **Full description** (4000 chars): Use same as App Store

#### Categorization
- **Category**: Social
- **Content Rating**: Teen (you'll fill out a questionnaire)

#### Contact Details
- **Email**: support@kora.app
- **Website**: https://kora.app
- **Phone**: Optional

### 4. Android Build & Submission Process

#### Generate Release Keystore (ONE TIME ONLY)
```bash
# Create keystore directory
mkdir -p android/keystore

# Generate keystore (SAVE THE PASSWORDS!)
keytool -genkey -v -keystore android/keystore/kora-release.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias kora

# Create key.properties file (DO NOT COMMIT TO GIT)
cat > android/key.properties << EOF
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=kora
storeFile=../keystore/kora-release.keystore
EOF

# Add to .gitignore
echo "android/key.properties" >> .gitignore
echo "android/keystore/" >> .gitignore
```

#### Build Release APK/AAB
```bash
# Clean build
flutter clean
flutter pub get

# Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# OR Build APK
flutter build apk --release

# Output locations:
# AAB: build/app/outputs/bundle/release/app-release.aab
# APK: build/app/outputs/flutter-apk/app-release.apk
```

## 📝 Privacy Policy & Terms (REQUIRED)

### Create Privacy Policy covering:
- What data you collect (voice calls, profile info, location)
- How you use the data
- Data retention policies
- User rights (deletion, access)
- Contact information
- Third-party services (Agora, Supabase, etc.)

### Create Terms of Service covering:
- User conduct rules
- Age requirements (17+)
- Prohibited content
- Account termination
- Liability limitations
- Dispute resolution

## 🔒 Required Permissions Explanations

### iOS (Info.plist) - ALREADY CONFIGURED ✅
- **Microphone**: "This app needs access to microphone for voice calls with other users."
- **Local Network**: "This app uses the local network to connect voice calls between users."

### Android (AndroidManifest.xml) - ALREADY CONFIGURED ✅
- RECORD_AUDIO
- INTERNET
- MODIFY_AUDIO_SETTINGS

## 🚀 Pre-Launch Testing

### 1. TestFlight (iOS)
```bash
# Upload to TestFlight for beta testing
# In App Store Connect:
# 1. Go to TestFlight tab
# 2. Add internal/external testers
# 3. Submit for review (external only)
```

### 2. Google Play Console Testing
```bash
# Internal Testing Track
# 1. Upload AAB to Internal Testing
# 2. Add testers by email
# 3. Share testing link
```

## 📊 Analytics & Crash Reporting (Recommended)

Consider adding:
- Firebase Analytics
- Firebase Crashlytics
- Sentry

## 🎯 Launch Strategy

### Soft Launch
1. Release in limited countries first
2. Gather feedback and fix issues
3. Gradually expand availability

### Marketing Materials Needed
- [ ] App preview video (15-30 seconds)
- [ ] Social media accounts
- [ ] Landing page (kora.app)
- [ ] Press kit

## ⚠️ Important Notes

1. **NEVER LOSE YOUR KEYSTORE**: Back up your Android keystore file and passwords. You cannot update your app without it.

2. **Version Management**: 
   - iOS uses build numbers for each upload
   - Update in pubspec.yaml: `version: 1.0.0+2` (increment +2, +3, etc.)

3. **Review Times**:
   - Apple: 24-48 hours typically
   - Google: 2-3 hours typically

4. **Rejection Common Reasons**:
   - Missing privacy policy
   - Inappropriate content
   - Crashes or bugs
   - Misleading description
   - Guideline violations

## 🔄 Post-Launch Updates

To update your app:
1. Increment version in `pubspec.yaml`
2. Build new release
3. Upload to stores
4. Add release notes

## 📞 Support Contacts

- Apple Developer Support: https://developer.apple.com/support/
- Google Play Console Help: https://support.google.com/googleplay/android-developer

---

## Next Steps:
1. Create keystore for Android
2. Set up developer accounts
3. Create privacy policy and terms
4. Prepare screenshots and graphics
5. Build and test release versions
6. Submit for review

Good luck with your launch! 🚀