# 🚀 Kora Release Checklist

## Pre-Release Testing ✓

### Functionality Testing
- [ ] Test voice calls between two devices
- [ ] Test matchmaking flow
- [ ] Test call timeout (5 minutes)
- [ ] Test skip/next functionality
- [ ] Test leave functionality
- [ ] Test direct calls from matches
- [ ] Test waveform animations
- [ ] Test conversation starters
- [ ] Test like/dislike functionality
- [ ] Test navigation flows
- [ ] Test on different network conditions
- [ ] Test permissions (microphone)

### Device Testing
- [ ] iPhone (latest iOS)
- [ ] iPhone (minimum supported iOS)
- [ ] Android (latest version)
- [ ] Android (minimum supported version)
- [ ] iPad (if supporting tablets)
- [ ] Android tablet (if supporting)

### Edge Cases
- [ ] Test with no internet connection
- [ ] Test with poor connection
- [ ] Test interruptions (phone calls)
- [ ] Test background/foreground transitions
- [ ] Test with microphone permission denied
- [ ] Test with minutes exhausted

## Store Assets Checklist ✓

### Screenshots Needed
- [ ] Call screen with waveform
- [ ] Matches screen
- [ ] Profile screen
- [ ] Conversation starter screen
- [ ] Search/matching screen

### Required Sizes
#### iOS
- [ ] iPhone 6.7" - 3 screenshots minimum
- [ ] iPhone 6.5" - 3 screenshots minimum
- [ ] iPhone 5.5" - 3 screenshots minimum
- [ ] iPad 12.9" - optional but recommended

#### Android
- [ ] Phone screenshots - 2 minimum
- [ ] Tablet screenshots - optional

### Graphics
- [ ] App Icon 1024x1024 (iOS)
- [ ] App Icon 512x512 (Android)
- [ ] Feature Graphic 1024x500 (Android)

## Legal Requirements ✓

- [ ] Privacy Policy URL live and accessible
- [ ] Terms of Service URL live and accessible
- [ ] GDPR compliance statement
- [ ] CCPA compliance (if applicable)
- [ ] Age restriction notice (17+)
- [ ] Data deletion process documented

## Technical Checklist ✓

### Version Numbers
- [ ] Update version in pubspec.yaml
- [ ] Increment build number

### API Keys & Secrets
- [ ] Remove any debug API keys
- [ ] Ensure production API keys are set
- [ ] Verify .env file is configured for production
- [ ] Ensure no secrets in code

### Code Quality
- [ ] Remove all console.log/print statements
- [ ] Fix all linter warnings
- [ ] Remove commented code
- [ ] Update deprecated APIs

### Security
- [ ] Android keystore backed up
- [ ] Keystore passwords saved securely
- [ ] ProGuard rules configured
- [ ] iOS certificates valid

## Submission Checklist ✓

### App Store (iOS)
- [ ] Archive built in Xcode
- [ ] Upload to App Store Connect
- [ ] Screenshots uploaded
- [ ] Description filled
- [ ] Keywords added
- [ ] Category selected
- [ ] Age rating questionnaire completed
- [ ] Price tier selected (Free)
- [ ] Countries selected
- [ ] Submit for review

### Play Store (Android)
- [ ] AAB file generated
- [ ] Upload to Play Console
- [ ] Screenshots uploaded
- [ ] Description filled
- [ ] Category selected
- [ ] Content rating questionnaire
- [ ] Countries selected
- [ ] Pricing set (Free)
- [ ] Submit for review

## Post-Release ✓

- [ ] Monitor crash reports
- [ ] Check user reviews
- [ ] Respond to support emails
- [ ] Plan first update
- [ ] Marketing launch
- [ ] Social media announcement

## Important Reminders 🔴

1. **BACKUP YOUR KEYSTORE** - You cannot update Android app without it
2. **TEST ON REAL DEVICES** - Simulators don't catch everything
3. **HAVE SUPPORT READY** - Users will have questions immediately
4. **MONITOR FIRST 48 HOURS** - Most issues appear early

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.0.0   | TBD  | Initial release |

## Emergency Contacts

- Technical Issues: [Your contact]
- App Store Issues: https://developer.apple.com/support/
- Play Store Issues: https://support.google.com/googleplay/android-developer

---

Remember: It's better to delay launch than release with critical bugs!