# MainActivity probes this upstream static field by its original name.
-keepclassmembers class com.yausername.youtubedl_android.YoutubeDL {
    *** ffmpegPath;
}

# Commons Compress constructs ZIP extra fields reflectively while unpacking
# Python and FFmpeg. R8 must preserve their constructors and implementations.
-keep class * implements org.apache.commons.compress.archivers.zip.ZipExtraField { *; }
