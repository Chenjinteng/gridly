# =============================================================================
# D69:gridly + Flutter Android release 混淆规则
# 参考:https://docs.flutter.dev/deployment/android#shrinking-your-code-with-r8
# =============================================================================

# -----------------------------------------------------------------------------
# Flutter framework 兜底 keep
# -----------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# -----------------------------------------------------------------------------
# Drift(SQLite ORM)+ sqlite3_flutter_libs keep
# - Drift 用反射调 generated class,R8 会误删
# -----------------------------------------------------------------------------
-keep class **$Drift* { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class org.sqlite.** { *; }
-keep class androidx.sqlite.** { *; }

# -----------------------------------------------------------------------------
# Riverpod + Flutter 反射 keep
# -----------------------------------------------------------------------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes Exceptions

# -----------------------------------------------------------------------------
# 警告抑制(已知 R8 误报)
# -----------------------------------------------------------------------------
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**