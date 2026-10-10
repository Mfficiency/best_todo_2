# flutter_local_notifications persists scheduled notifications as JSON via
# Gson, which reads generic type parameters through reflection (TypeToken).
# R8 full mode (default on AGP 8+) strips those generic signatures, so every
# zonedSchedule()/pendingNotificationRequests() call in a release build dies
# with "java.lang.RuntimeException: Missing type parameter." and NO alarm can
# be handed to the OS. These rules keep the signatures and Gson's reflection
# targets intact.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# Gson itself plus the plugin's model classes that get (de)serialized.
-keep class com.google.gson.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.google.gson.**
