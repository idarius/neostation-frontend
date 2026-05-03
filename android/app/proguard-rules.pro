# Flutter standard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Prevent R8 from removing native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the sqlite3 classes
-keep class org.sqlite.** { *; }
-keep class sqlite3.** { *; }

# For general plugins that might use reflection
-dontwarn io.flutter.plugins.**
-dontwarn com.neogamelab.neostation.**

# Fix for missing Play Core classes referenced by Flutter engine
-dontwarn com.google.android.play.core.**

# Keep BouncyCastle (used by jcifs-ng for SMB NTLMv2 — needs MD4).
# The provider's algorithms are registered via reflection-loaded class
# names (string constants in put() calls), which R8 cannot trace, so
# without this rule the digest/cipher classes get stripped and SMB
# connect() throws NoSuchAlgorithmException despite the provider class
# itself surviving.
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep jcifs-ng (loaded through reflection chains internally).
-keep class jcifs.** { *; }
-dontwarn jcifs.**
