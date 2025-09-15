#!/bin/bash

# Script to handle missing dSYM files for Agora frameworks
# This script should be added as a "Run Script" build phase in Xcode

echo "Handling Agora framework dSYM upload issues..."

# Set the path to the built products directory
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$1}"
DWARF_DSYM_FOLDER_PATH="${DWARF_DSYM_FOLDER_PATH:-$2}"

if [ -z "$BUILT_PRODUCTS_DIR" ] || [ -z "$DWARF_DSYM_FOLDER_PATH" ]; then
    echo "Usage: $0 <BUILT_PRODUCTS_DIR> <DWARF_DSYM_FOLDER_PATH>"
    echo "Or run this script as part of Xcode build process"
    exit 0
fi

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