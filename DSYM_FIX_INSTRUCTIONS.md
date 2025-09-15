# Fix for Agora dSYM Upload Errors

The errors you're seeing are because Agora frameworks don't include debug symbol (dSYM) files, but App Store Connect expects them for crash reporting.

## Solution: Add Build Script to Xcode

### Step 1: Open Xcode Project
1. Open `ios/Runner.xcworkspace` in Xcode (not the .xcodeproj file)

### Step 2: Add Run Script Build Phase
1. In Xcode, select the **Runner** project in the navigator
2. Select the **Runner** target
3. Go to **Build Phases** tab
4. Click the **+** button and select **New Run Script Phase**
5. Drag the new **Run Script** phase to be **AFTER** the "Thin Binary" phase but **BEFORE** any copy phases

### Step 3: Configure the Script
1. Name the script: `Handle Agora dSYMs`
2. In the script field, paste this code:

```bash
# Handle missing dSYM files for Agora frameworks
echo "Handling Agora framework dSYM upload issues..."

# List of Agora frameworks that may not have dSYM files
AGORA_FRAMEWORKS=(
    "AgoraAiEchoCancellationExtension"
    "AgoraAiEchoCancellationLLExtension"  
    "AgoraAiNoiseSuppressionExtension"
    "AgoraAiNoiseSuppressionLLExtension"
    "AgoraAudioBeautyExtension"
    "AgoraClearVisionExtension"
    "AgoraContentInspectExtension"
    "AgoraFaceCaptureExtension"
    "AgoraFaceDetectionExtension"
    "AgoraLipSyncExtension"
    "AgoraReplayKitExtension"
    "AgoraRtcKit"
    "AgoraRtcWrapper"
    "AgoraVideoEncoderExtension"
    "AgoraVideoDecoderExtension"
    "AgoraVideoSegmentationExtension"
    "AgoraSpatialAudioExtension"
    "Agoraffmpeg"
    "Agorafdkaac"
    "AgoraSoundTouch"
    "AgoraVideoAv1DecoderExtension"
    "AgoraVideoAv1EncoderExtension"
    "AgoraVideoQualityAnalyzerExtension"
    "video_enc"
    "video_dec"
    "aosl"
)

# Create empty dSYM files for missing Agora frameworks
for framework in "${AGORA_FRAMEWORKS[@]}"; do
    FRAMEWORK_PATH="$BUILT_PRODUCTS_DIR/$framework.framework"
    DSYM_PATH="$DWARF_DSYM_FOLDER_PATH/$framework.framework.dSYM"
    
    if [ -d "$FRAMEWORK_PATH" ] && [ ! -d "$DSYM_PATH" ]; then
        echo "Creating placeholder dSYM for $framework"
        mkdir -p "$DSYM_PATH/Contents/Resources/DWARF"
        
        # Create Info.plist for dSYM
        cat > "$DSYM_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleIdentifier</key>
    <string>com.apple.xcode.dsym.$framework</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>dSYM</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
EOF
        
        # Create empty DWARF file
        touch "$DSYM_PATH/Contents/Resources/DWARF/$framework"
    fi
done

echo "dSYM handling complete."
```

### Step 4: Set Build Phase Options
1. Make sure **"Run script only when installing"** is **UNCHECKED**
2. Under **Input Files**, add: `$(BUILT_PRODUCTS_DIR)/Runner.app`
3. Under **Output Files**, add: `$(DWARF_DSYM_FOLDER_PATH)`

### Step 5: Clean and Archive
1. In Xcode: **Product → Clean Build Folder**
2. **Product → Archive** 
3. The script will now create placeholder dSYM files for Agora frameworks that don't have them

## Alternative Solution (if above doesn't work)

If the script approach doesn't work, you can disable symbol uploading for these specific frameworks by adding this to your build settings:

1. Go to **Build Settings** in your Runner target
2. Search for "Debug Information Format"  
3. Set **Debug Information Format** to **DWARF** (instead of **DWARF with dSYM File**) for Release builds only

This will prevent the symbol upload requirement but you'll lose crash symbolication for those frameworks.

## What This Fixes

This script creates placeholder dSYM files for Agora frameworks that don't provide them, preventing the upload errors you're seeing during App Store submission.