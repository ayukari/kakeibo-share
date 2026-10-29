# kotlinx.serialization と Ktor（supabase-kt）
-keepattributes *Annotation*, InnerClasses, Signature
-keep,includedescriptorclasses class jp.kakeibo.share.**$$serializer { *; }
-keepclassmembers class jp.kakeibo.share.** { *** Companion; }
-dontwarn org.slf4j.**
