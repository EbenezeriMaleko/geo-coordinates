# Rules specifically for ffmpeg_kit_flutter_new packages
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Keep standard internal native hooks safe from code-stripping
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
-keep class org.ffmpeg.** { *; }
-dontwarn org.ffmpeg.**

