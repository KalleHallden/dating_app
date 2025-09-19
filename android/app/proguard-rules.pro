# Flutter specific ProGuard rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Agora specific rules
-keep class io.agora.** { *; }
-keep class com.agora.** { *; }

# Supabase/WebRTC rules
-keep class org.webrtc.** { *; }
-keep class com.supabase.** { *; }

# Keep your app's classes
-keep class com.hallden.kora.** { *; }

# Google Maps
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# Don't warn about missing classes that are referenced from libraries
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
-dontwarn sun.misc.Unsafe

# Play Core library rules - these are referenced but not used in release builds
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**