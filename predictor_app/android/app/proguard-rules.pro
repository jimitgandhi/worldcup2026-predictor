# ─── Gson (used by flutter_local_notifications for serializing scheduled notifications) ───
# Without these rules, R8 strips generic type information and Gson's TypeToken throws
# "TypeToken must be created with a type argument" at runtime.
-keepattributes Signature
-keepattributes *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# ─── flutter_local_notifications ─────────────────────────────────────────────────────────
-keep class com.dexterous.** { *; }
