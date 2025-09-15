#!/bin/bash

# Kora Release Build Script
# This script builds release versions for both iOS and Android

echo "🚀 Kora Release Build Script"
echo "============================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1 successful${NC}"
    else
        echo -e "${RED}❌ $1 failed${NC}"
        exit 1
    fi
}

# Main menu
echo ""
echo "Select build option:"
echo "1) iOS Release Build"
echo "2) Android Release Build (AAB)"
echo "3) Android Release Build (APK)"
echo "4) Both iOS and Android"
echo "5) Clean and Get Dependencies"
echo ""
read -p "Enter choice [1-5]: " choice

# Clean and get dependencies function
clean_and_setup() {
    echo -e "${YELLOW}🧹 Cleaning project...${NC}"
    flutter clean
    check_status "Flutter clean"
    
    echo -e "${YELLOW}📦 Getting dependencies...${NC}"
    flutter pub get
    check_status "Flutter pub get"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}🍎 Installing iOS pods...${NC}"
        cd ios && pod install && cd ..
        check_status "Pod install"
    fi
}

# iOS build function
build_ios() {
    echo -e "${YELLOW}🍎 Building iOS Release...${NC}"
    
    # Check if on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}❌ iOS builds can only be created on macOS${NC}"
        return
    fi
    
    flutter build ios --release
    check_status "iOS build"
    
    echo -e "${GREEN}✅ iOS build complete!${NC}"
    echo "📍 Next steps:"
    echo "1. Open ios/Runner.xcworkspace in Xcode"
    echo "2. Select 'Any iOS Device' as build target"
    echo "3. Product → Archive"
    echo "4. Distribute App → App Store Connect"
}

# Android AAB build function
build_android_aab() {
    echo -e "${YELLOW}🤖 Building Android App Bundle (AAB)...${NC}"
    
    # Check if keystore exists
    if [ ! -f "android/keystore/kora-release.keystore" ]; then
        echo -e "${YELLOW}⚠️  Keystore not found. Would you like to create one? (y/n)${NC}"
        read -p "" create_key
        if [ "$create_key" = "y" ]; then
            create_keystore
        else
            echo -e "${RED}❌ Cannot build release without keystore${NC}"
            return
        fi
    fi
    
    flutter build appbundle --release
    check_status "Android AAB build"
    
    echo -e "${GREEN}✅ Android AAB build complete!${NC}"
    echo "📍 Output: build/app/outputs/bundle/release/app-release.aab"
    echo "📤 Upload this file to Google Play Console"
}

# Android APK build function
build_android_apk() {
    echo -e "${YELLOW}🤖 Building Android APK...${NC}"
    
    # Check if keystore exists
    if [ ! -f "android/keystore/kora-release.keystore" ]; then
        echo -e "${YELLOW}⚠️  Keystore not found. Would you like to create one? (y/n)${NC}"
        read -p "" create_key
        if [ "$create_key" = "y" ]; then
            create_keystore
        else
            echo -e "${RED}❌ Cannot build release without keystore${NC}"
            return
        fi
    fi
    
    flutter build apk --release
    check_status "Android APK build"
    
    echo -e "${GREEN}✅ Android APK build complete!${NC}"
    echo "📍 Output: build/app/outputs/flutter-apk/app-release.apk"
}

# Create keystore function
create_keystore() {
    echo -e "${YELLOW}🔐 Creating Android keystore...${NC}"
    
    # Create directory if it doesn't exist
    mkdir -p android/keystore
    
    # Generate keystore
    keytool -genkey -v -keystore android/keystore/kora-release.keystore \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -alias kora
    
    check_status "Keystore creation"
    
    echo -e "${YELLOW}📝 Creating key.properties file...${NC}"
    echo "Enter the keystore password you just created:"
    read -s store_pass
    echo "Enter the key password you just created:"
    read -s key_pass
    
    cat > android/key.properties << EOF
storePassword=$store_pass
keyPassword=$key_pass
keyAlias=kora
storeFile=../keystore/kora-release.keystore
EOF
    
    echo -e "${GREEN}✅ Keystore created successfully!${NC}"
    echo -e "${RED}⚠️  IMPORTANT: Back up android/keystore/kora-release.keystore and passwords!${NC}"
}

# Execute based on choice
case $choice in
    1)
        clean_and_setup
        build_ios
        ;;
    2)
        clean_and_setup
        build_android_aab
        ;;
    3)
        clean_and_setup
        build_android_apk
        ;;
    4)
        clean_and_setup
        build_ios
        build_android_aab
        ;;
    5)
        clean_and_setup
        echo -e "${GREEN}✅ Project cleaned and dependencies installed!${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🎉 Build process complete!${NC}"
echo ""
echo "📱 App Version Info:"
grep "version:" pubspec.yaml | head -1
echo ""
echo "📚 For more details, see PUBLISHING_GUIDE.md"