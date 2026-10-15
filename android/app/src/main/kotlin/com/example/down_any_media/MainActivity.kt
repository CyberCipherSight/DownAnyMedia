package com.example.down_any_media

import android.app.DownloadManager
import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val channelName = "down_any_media/android_downloader"
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var updateAttempted = false
    private var lastUpdateStatus = "Not checked"
    private var lastUpdateMessage: String? = null
    private var pendingSharedPayload: Map<String, Any?>? = null
    private var lastNotificationUpdateAt = 0L
    private var lastNotificationProgress = -1
    private var lastNotificationStatus = ""
    private var lastProgressUiUpdateAt = 0L
    private var lastFFmpegDiagnostic: FFmpegDiagnostic? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        requestNotificationPermissionIfNeeded()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDefaultDownloadFolder" -> result.success(publicDownloadDisplayDir())
                "getInitialSharedContent" -> {
                    val payload = pendingSharedPayload ?: sharedPayloadFromIntent(intent)
                    pendingSharedPayload = null
                    result.success(payload)
                }
                "getEngineStatus" -> getEngineStatus(result)
                "testFFmpeg" -> testFFmpeg(result)
                "analyzeUrl" -> analyzeUrl(call, result)
                "startMp3Download" -> startMp3Download(call, result)
                "cancelDownload" -> {
                    val processId = call.argument<String>("processId")
                    if (processId.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        result.success(YoutubeDL.getInstance().destroyProcessById(processId))
                    }
                }
                "openFile" -> result.success(openFile(call))
                "openFolder" -> result.success(openFolder(call))
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = sharedPayloadFromIntent(intent) ?: return
        val activeChannel = channel
        if (activeChannel == null) {
            pendingSharedPayload = payload
        } else {
            mainHandler.post {
                activeChannel.invokeMethod("sharedContentReceived", payload)
            }
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun startMp3Download(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val processId = call.argument<String>("processId")?.trim().orEmpty()
        val folderName = cleanPathSegment(call.argument<String>("folderName"))
        val relativeBaseFolder = cleanRelativeBaseFolder(call.argument<String>("relativeBaseFolder"))
            ?: defaultRelativeBaseFolder()
        val outputBaseName = cleanPathSegment(call.argument<String>("outputBaseName"))
        val embedMetadata = call.argument<Boolean>("embedMetadata") ?: true
        val embedThumbnail = call.argument<Boolean>("embedThumbnail") ?: true
        val downloadMode = call.argument<String>("downloadMode") ?: "mp3"
        val isVideo = downloadMode == "video"
        val audioQuality = call.argument<String>("audioQuality")
            ?.takeIf { it in setOf("0", "5", "9") }
            ?: "0"
        val videoFormatSelector = call.argument<String>("videoFormatSelector")
            ?.takeIf { it.isNotBlank() }
            ?: "bv*+ba/best"
        val videoQuality = call.argument<String>("videoQuality") ?: "best"
        val notificationTitle = call.argument<String>("notificationTitle")
            ?.takeIf { it.isNotBlank() }
            ?: outputBaseName
            ?: "MP3 download"
        val queueIndex = call.argument<Int>("queueIndex") ?: 0
        val queueTotal = call.argument<Int>("queueTotal") ?: 0

        if (url.isBlank()) {
            result.error("missing_url", "Paste a URL before downloading.", null)
            return
        }

        if (processId.isBlank()) {
            result.error("missing_process_id", "Android download process id is missing.", null)
            return
        }

        updateDownloadNotification(
            DownloadForegroundService.ACTION_START,
            processId,
            notificationTitle,
            0,
            "Preparing download...",
            queueIndex,
            queueTotal,
        )

        executor.execute {
            val startedAt = System.currentTimeMillis()
            val workDir = workDownloadDir(folderName)
            val taskId = cleanPathSegment(processId) ?: "download_$startedAt"
            var selectedFormat = if (isVideo) videoFormatSelector else "bestaudio/best"
            var fallbackAttempted = false
            val fallbackStepsTried = mutableListOf<String>()
            var ffmpegDiagnostic: FFmpegDiagnostic? = null
            var filesFound = emptyList<String>()

            try {
                ensureDirectory(workDir, "Could not create app download work folder.")
                ensurePublicDownloadDir(folderName, relativeBaseFolder = relativeBaseFolder)
                initDownloader(applicationContext)
                updateYoutubeDLIfNeeded(processId)
                if (isVideo) {
                    ffmpegDiagnostic = resolveFFmpegPath()
                }

                val outputName = if (outputBaseName.isNullOrBlank()) {
                    "%(title).180s-[$taskId].%(ext)s"
                } else {
                    "$outputBaseName-[$taskId].%(ext)s"
                }

                var lastError: Throwable? = null
                var mediaFile: File? = null

                if (isVideo) {
                    val diagnostic = ffmpegDiagnostic
                    if (diagnostic?.available == true) {
                        sendProgress(processId, 0f, "Preparing media processing...")
                    } else {
                        sendProgress(
                            processId,
                            0f,
                            "Downloading the best available video.",
                        )
                    }
                    val attempts = videoFormatAttempts(videoFormatSelector, diagnostic?.available == true)
                    for ((attemptIndex, attempt) in attempts.withIndex()) {
                        selectedFormat = attempt.format ?: "yt-dlp default"
                        fallbackAttempted = fallbackAttempted || attemptIndex > 0
                        fallbackStepsTried.add(attempt.label)
                        try {
                            val request = buildDownloadRequest(
                                url = url,
                                outputPath = File(workDir, outputName).absolutePath,
                                isVideo = true,
                                videoFormat = attempt.format,
                                ffmpegLocation = if (attempt.requiresFFmpeg) diagnostic?.path else null,
                                audioQuality = audioQuality,
                                embedMetadata = embedMetadata,
                                embedThumbnail = embedThumbnail,
                            )
                            val statusLine = if (attemptIndex == 0) {
                                "Downloading video..."
                            } else if (attempt.format == null) {
                                "Retrying with automatic video selection..."
                            } else if (!attempt.requiresFFmpeg) {
                                "Retrying with best available video..."
                            } else {
                                "Retrying with best available video..."
                            }
                            sendProgress(processId, 0f, statusLine)
                            YoutubeDL.getInstance().execute(request, processId) { progress, _, line ->
                                sendProgress(processId, progress, line)
                                updateDownloadNotification(
                                    DownloadForegroundService.ACTION_UPDATE,
                                    processId,
                                    notificationTitle,
                                    progress.toInt().coerceIn(0, 100),
                                    notificationStatusFromLine(line),
                                    queueIndex,
                                    queueTotal,
                                )
                            }
                            filesFound = filesFoundForTask(workDir, taskId)
                            mediaFile = newestMedia(workDir, startedAt, true, taskId)
                            if (mediaFile != null) {
                                break
                            }
                            lastError = IllegalStateException("No video file was created.")
                        } catch (error: YoutubeDL.CanceledException) {
                            throw error
                        } catch (error: Throwable) {
                            lastError = error
                            filesFound = filesFoundForTask(workDir, taskId)
                            mediaFile = newestMedia(workDir, startedAt, true, taskId)
                            if (mediaFile != null) {
                                break
                            }
                        }
                    }
                } else {
                    val request = buildDownloadRequest(
                        url = url,
                        outputPath = File(workDir, outputName).absolutePath,
                        isVideo = false,
                        videoFormat = null,
                        ffmpegLocation = null,
                        audioQuality = audioQuality,
                        embedMetadata = embedMetadata,
                        embedThumbnail = embedThumbnail,
                    )
                    YoutubeDL.getInstance().execute(request, processId) { progress, _, line ->
                        sendProgress(processId, progress, line)
                        updateDownloadNotification(
                            DownloadForegroundService.ACTION_UPDATE,
                            processId,
                            notificationTitle,
                            progress.toInt().coerceIn(0, 100),
                            notificationStatusFromLine(line),
                            queueIndex,
                            queueTotal,
                        )
                    }
                    filesFound = filesFoundForTask(workDir, taskId)
                    mediaFile = newestMedia(workDir, startedAt, false)
                }
                if (mediaFile == null) {
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_FAILED,
                        processId,
                        notificationTitle,
                        0,
                        "Failed",
                        queueIndex,
                        queueTotal,
                    )
                    val failureMessage = lastError?.let { readableError(it) }
                        ?: if (isVideo) "No video file was created." else "No MP3 file was created."
                    postSuccess(
                        result,
                        mapOf(
                            "status" to "error",
                            "error" to failureMessage,
                            "selectedFormat" to selectedFormat,
                            "fallbackStepsTried" to fallbackStepsTried,
                            "fallbackAttempted" to fallbackAttempted,
                            "tempFolder" to workDir.absolutePath,
                            "publishResult" to "Not published",
                            "ffmpegAvailable" to (ffmpegDiagnostic?.available == true),
                            "ffmpegPath" to ffmpegDiagnostic?.path,
                            "ffmpegVersion" to ffmpegDiagnostic?.version,
                            "ffmpegExecutionTest" to ffmpegDiagnostic?.executionTest,
                            "videoMergeSupported" to (ffmpegDiagnostic?.videoMergeSupported == true),
                            "androidAbi" to androidAbiLabel(),
                            "filesFound" to filesFound,
                        ),
                    )
                } else {
                    sendProgress(processId, 100f, "Publishing file to Downloads...")
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_UPDATE,
                        processId,
                        notificationTitle,
                        100,
                        "Publishing",
                        queueIndex,
                        queueTotal,
                    )
                    val warnings = mutableListOf<String>()
                    if (isVideo && ffmpegDiagnostic?.available != true) {
                        warnings.add("Video saved using the best available format.")
                    }
                    if (isVideo && videoQuality in setOf("p1080", "p720", "p480")) {
                        warnings.add(if (fallbackAttempted) {
                            "Video saved using the best available fallback format."
                        } else {
                            "Video saved. If the selected quality was unavailable, the nearest available format was used."
                        })
                    }
                    val warning = warnings.joinToString(" ").ifBlank { null }
                    postCompletedSafely(
                        result,
                        mediaFile,
                        warning,
                        folderName = folderName,
                        isVideo = isVideo,
                        selectedFormat = selectedFormat,
                        fallbackStepsTried = fallbackStepsTried,
                        fallbackAttempted = fallbackAttempted,
                        tempFolder = workDir.absolutePath,
                        ffmpegDiagnostic = ffmpegDiagnostic,
                        filesFound = filesFound,
                        relativeBaseFolder = relativeBaseFolder,
                    )
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_COMPLETE,
                        processId,
                        notificationTitle,
                        100,
                        "Completed",
                        queueIndex,
                        queueTotal,
                    )
                }
            } catch (error: YoutubeDL.CanceledException) {
                stopDownloadNotification(processId)
                postSuccess(result, mapOf("status" to "cancelled"))
            } catch (error: Throwable) {
                val mp3 = newestMedia(workDir, startedAt, isVideo)
                val message = readableError(error)
                if (!isVideo && mp3 != null && looksLikeOptionalMetadataFailure(message)) {
                    sendProgress(processId, 100f, "Publishing file to Downloads...")
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_UPDATE,
                        processId,
                        notificationTitle,
                        100,
                        "Publishing",
                        queueIndex,
                        queueTotal,
                    )
                    postCompletedSafely(
                        result,
                        mp3,
                        "MP3 saved. Thumbnail or metadata embedding did not complete.",
                        folderName,
                        relativeBaseFolder = relativeBaseFolder,
                    )
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_COMPLETE,
                        processId,
                        notificationTitle,
                        100,
                        "Completed with warning",
                        queueIndex,
                        queueTotal,
                    )
                } else {
                    updateDownloadNotification(
                        DownloadForegroundService.ACTION_FAILED,
                        processId,
                        notificationTitle,
                        0,
                        "Failed",
                        queueIndex,
                        queueTotal,
                    )
                    if (isVideo) {
                        filesFound = filesFoundForTask(workDir, taskId)
                        postSuccess(
                            result,
                            mapOf(
                                "status" to "error",
                                "error" to message,
                                "selectedFormat" to selectedFormat,
                                "fallbackStepsTried" to fallbackStepsTried,
                                "fallbackAttempted" to fallbackAttempted,
                                "tempFolder" to workDir.absolutePath,
                                "publishResult" to "Not published",
                                "ffmpegAvailable" to (ffmpegDiagnostic?.available == true),
                                "ffmpegPath" to ffmpegDiagnostic?.path,
                                "ffmpegVersion" to ffmpegDiagnostic?.version,
                                "ffmpegExecutionTest" to ffmpegDiagnostic?.executionTest,
                                "videoMergeSupported" to (ffmpegDiagnostic?.videoMergeSupported == true),
                                "androidAbi" to androidAbiLabel(),
                                "filesFound" to filesFound,
                            ),
                        )
                    } else {
                        postError(result, message)
                    }
                }
            }
        }
    }

    private fun analyzeUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        if (url.isBlank()) {
            result.error("missing_url", "Paste a URL before analyzing.", null)
            return
        }

        executor.execute {
            try {
                initDownloader(applicationContext)
                val request = YoutubeDLRequest(url)
                request.addOption("--dump-single-json")
                request.addOption("--flat-playlist")
                request.addOption("--skip-download")
                request.addOption("--no-warnings")
                val response = YoutubeDL.getInstance().execute(request)
                if (response.exitCode == 0 && response.out.isNotBlank()) {
                    postSuccess(result, mapOf("status" to "ok", "json" to response.out))
                } else {
                    val message = response.err.ifBlank { "Unsupported URL or playlist." }
                    postSuccess(result, mapOf("status" to "error", "error" to message))
                }
            } catch (error: Throwable) {
                postSuccess(result, mapOf("status" to "error", "error" to readableError(error)))
            }
        }
    }

    private fun buildDownloadRequest(
        url: String,
        outputPath: String,
        isVideo: Boolean,
        videoFormat: String?,
        ffmpegLocation: String?,
        audioQuality: String,
        embedMetadata: Boolean,
        embedThumbnail: Boolean,
    ): YoutubeDLRequest {
        val request = YoutubeDLRequest(url)
        request.addOption("--newline")
        request.addOption("--no-warnings")
        if (isVideo) {
            if (videoFormat != null) {
                request.addOption("-f", videoFormat)
            }
            if (ffmpegLocation != null) {
                request.addOption("--merge-output-format", "mp4")
                request.addCommands(listOf("--ffmpeg-location", ffmpegLocation))
            }
        } else {
            request.addOption("-x")
            request.addOption("-f", "bestaudio/best")
            request.addOption("--audio-format", "mp3")
            request.addOption("--audio-quality", audioQuality)
            if (embedMetadata) {
                request.addOption("--embed-metadata")
            }
            if (embedThumbnail) {
                request.addOption("--embed-thumbnail")
            }
        }
        request.addOption("--no-playlist")
        request.addOption("--no-mtime")
        request.addOption("-o", outputPath)
        return request
    }

    private fun videoFormatAttempts(selectedFormat: String, ffmpegAvailable: Boolean): List<VideoAttempt> {
        val attempts = if (ffmpegAvailable) {
            listOf(
                VideoAttempt(selectedFormat, true, "$selectedFormat with FFmpeg merge"),
                VideoAttempt("bv*+ba/best", true, "bv*+ba/best with FFmpeg merge"),
                VideoAttempt("best", false, "best pre-merged"),
                VideoAttempt(null, false, "yt-dlp default"),
            )
        } else {
            listOf(
                VideoAttempt("best", false, "best pre-merged without FFmpeg"),
                VideoAttempt(null, false, "yt-dlp default without FFmpeg"),
            )
        }
        return attempts.distinctBy { "${it.format}:${it.requiresFFmpeg}" }
    }

    private fun getEngineStatus(result: MethodChannel.Result) {
        executor.execute {
            try {
                initDownloader(applicationContext)
                val version = YoutubeDL.getInstance().versionName(applicationContext)
                val ffmpeg = resolveFFmpegPath()
                postSuccess(
                    result,
                    mapOf(
                        "status" to when {
                            lastUpdateStatus.startsWith("Update failed") -> "Update failed but usable"
                            ffmpeg.available -> "Ready"
                            else -> "FFmpeg unavailable"
                        },
                        "ytDlpAvailable" to true,
                        "ffmpegAvailable" to ffmpeg.available,
                        "ytDlpVersion" to version,
                        "ffmpegVersion" to ffmpeg.version,
                        "ffmpegPath" to ffmpeg.path,
                        "ffmpegExecutionTest" to ffmpeg.executionTest,
                        "videoMergeSupported" to ffmpeg.videoMergeSupported,
                        "androidAbi" to ffmpeg.androidAbi,
                        "activeEnginePath" to "Bundled Android yt-dlp/Python/FFmpeg",
                        "androidUpdateStatus" to lastUpdateStatus,
                        "message" to (lastUpdateMessage ?: ffmpeg.failureReason),
                    ),
                )
            } catch (error: Throwable) {
                postSuccess(
                    result,
                    mapOf(
                        "status" to "Engine error",
                        "ytDlpAvailable" to false,
                        "ffmpegAvailable" to false,
                        "ytDlpVersion" to "Unknown",
                        "ffmpegVersion" to "Unknown",
                        "ffmpegPath" to null,
                        "ffmpegExecutionTest" to readableError(error),
                        "videoMergeSupported" to false,
                        "androidAbi" to androidAbiLabel(),
                        "activeEnginePath" to "Bundled Android engine",
                        "androidUpdateStatus" to lastUpdateStatus,
                        "message" to readableError(error),
                    ),
                )
            }
        }
    }

    private fun testFFmpeg(result: MethodChannel.Result) {
        executor.execute {
            try {
                initDownloader(applicationContext)
                val version = YoutubeDL.getInstance().versionName(applicationContext)
                val ffmpeg = resolveFFmpegPath(force = true)
                postSuccess(
                    result,
                    mapOf(
                        "status" to if (ffmpeg.available) "Ready" else "FFmpeg unavailable",
                        "ytDlpAvailable" to true,
                        "ffmpegAvailable" to ffmpeg.available,
                        "ytDlpVersion" to version,
                        "ffmpegVersion" to ffmpeg.version,
                        "ffmpegPath" to ffmpeg.path,
                        "ffmpegExecutionTest" to ffmpeg.executionTest,
                        "videoMergeSupported" to ffmpeg.videoMergeSupported,
                        "androidAbi" to ffmpeg.androidAbi,
                        "activeEnginePath" to "Bundled Android yt-dlp/Python/FFmpeg",
                        "androidUpdateStatus" to lastUpdateStatus,
                        "message" to ffmpeg.failureReason,
                    ),
                )
            } catch (error: Throwable) {
                postSuccess(
                    result,
                    mapOf(
                        "status" to "FFmpeg test failed",
                        "ytDlpAvailable" to false,
                        "ffmpegAvailable" to false,
                        "ytDlpVersion" to "Unknown",
                        "ffmpegVersion" to "Unknown",
                        "ffmpegPath" to null,
                        "ffmpegExecutionTest" to readableError(error),
                        "videoMergeSupported" to false,
                        "androidAbi" to androidAbiLabel(),
                        "activeEnginePath" to "Bundled Android engine",
                        "androidUpdateStatus" to lastUpdateStatus,
                        "message" to readableError(error),
                    ),
                )
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4201)
    }

    private fun updateDownloadNotification(
        action: String,
        processId: String,
        title: String,
        progress: Int,
        status: String,
        queueIndex: Int,
        queueTotal: Int,
    ) {
        when (action) {
            DownloadForegroundService.ACTION_START -> {
                lastNotificationUpdateAt = 0L
                lastNotificationProgress = -1
                lastNotificationStatus = ""
                DownloadForegroundService.start(
                    this,
                    processId,
                    title,
                    progress,
                    status,
                    queueIndex,
                    queueTotal,
                )
            }
            DownloadForegroundService.ACTION_UPDATE -> {
                if (!shouldUpdateNotification(progress, status)) {
                    return
                }
                DownloadForegroundService.update(
                    this,
                    processId,
                    title,
                    progress,
                    status,
                    queueIndex,
                    queueTotal,
                )
            }
            DownloadForegroundService.ACTION_COMPLETE,
            DownloadForegroundService.ACTION_FAILED -> {
                DownloadForegroundService.finish(
                    this,
                    action,
                    processId,
                    title,
                    progress,
                    status,
                    queueIndex,
                    queueTotal,
                )
            }
        }
    }

    private fun shouldUpdateNotification(progress: Int, status: String): Boolean {
        val now = System.currentTimeMillis()
        val changedEnough = progress != lastNotificationProgress || status != lastNotificationStatus
        val timeEnough = now - lastNotificationUpdateAt >= 750L
        if (!changedEnough && !timeEnough) {
            return false
        }
        if (!timeEnough && progress != 100 && status == lastNotificationStatus) {
            return false
        }
        lastNotificationUpdateAt = now
        lastNotificationProgress = progress
        lastNotificationStatus = status
        return true
    }

    private fun stopDownloadNotification(processId: String) {
        val intent = Intent(this, DownloadForegroundService::class.java).apply {
            action = DownloadForegroundService.ACTION_STOP
            putExtra(DownloadForegroundService.EXTRA_PROCESS_ID, processId)
        }
        startService(intent)
    }

    private fun notificationStatusFromLine(line: String): String {
        val lower = line.lowercase()
        return when {
            lower.contains("[extractaudio]") -> "Extracting audio"
            lower.contains("[metadata]") -> "Adding media details"
            lower.contains("[embedthumbnail]") -> "Adding thumbnail"
            lower.contains("[ffmpeg]") || lower.contains("[merger]") -> "Merging"
            lower.contains("media processing") -> "Preparing media"
            lower.contains("[download]") -> "Downloading"
            else -> "Working"
        }
    }

    private fun sharedPayloadFromIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val action = intent.action ?: return null

        if (action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val text = listOfNotNull(
                intent.getStringExtra(Intent.EXTRA_TEXT),
                intent.getStringExtra(Intent.EXTRA_SUBJECT),
            ).joinToString("\n").trim()
            val url = firstUrlFromText(text)
            if (text.isBlank()) {
                return mapOf(
                    "source" to "share",
                    "status" to "empty",
                    "message" to "Shared text did not include a URL.",
                )
            }
            return mapOf(
                "source" to "share",
                "status" to if (url == null) "no_url" else "ok",
                "text" to text,
                "url" to url,
                "message" to if (url == null) {
                    "No URL was found in the shared text."
                } else {
                    "URL received from another app"
                },
            )
        }

        if (action == Intent.ACTION_VIEW) {
            val text = intent.dataString?.trim().orEmpty()
            if (text.isBlank()) return null
            val url = firstUrlFromText(text)
            return mapOf(
                "source" to "view",
                "status" to if (url == null) "no_url" else "ok",
                "text" to text,
                "url" to url,
                "message" to if (url == null) {
                    "No URL was found in the opened link."
                } else {
                    "URL received from another app"
                },
            )
        }

        return null
    }

    private fun firstUrlFromText(text: String): String? {
        val match = Regex("""https?://[^\s<>"']+""").find(text) ?: return null
        return match.value.trimEnd('.', ',', ')', ']', '}', ';')
    }

    @Synchronized
    private fun initDownloader(context: Context) {
        YoutubeDL.getInstance().init(context)
        try {
            FFmpeg.getInstance().init(context)
        } catch (_: Throwable) {
            // Video mode resolves and reports FFmpeg failures without blocking yt-dlp.
        }
    }

    private fun resolveFFmpegPath(force: Boolean = false): FFmpegDiagnostic {
        if (!force) {
            lastFFmpegDiagnostic?.let { return it }
        }

        val failures = mutableListOf<String>()
        try {
            FFmpeg.getInstance().init(applicationContext)
        } catch (error: Throwable) {
            failures.add("FFmpeg module init failed: ${readableError(error)}")
        }

        val candidates = ffmpegCandidates().distinctBy { it.file.absolutePath }
        for (candidate in candidates) {
            val test = testFFmpegExecutable(candidate.file)
            if (test.available) {
                val diagnostic = FFmpegDiagnostic(
                    available = true,
                    path = candidate.file.absolutePath,
                    version = test.version,
                    executionTest = "${candidate.label}: ${test.message}",
                    failureReason = null,
                    androidAbi = androidAbiLabel(),
                    videoMergeSupported = true,
                    candidates = candidates.map { "${it.label}: ${it.file.absolutePath}" },
                )
                lastFFmpegDiagnostic = diagnostic
                return diagnostic
            }
            failures.add("${candidate.label}: ${test.message}")
        }

        val diagnostic = FFmpegDiagnostic(
            available = false,
            path = null,
            version = "Unavailable",
            executionTest = failures.joinToString(" | ").ifBlank { "No FFmpeg candidates found." },
            failureReason = failures.joinToString(" | ").ifBlank { "No FFmpeg candidates found." },
            androidAbi = androidAbiLabel(),
            videoMergeSupported = false,
            candidates = candidates.map { "${it.label}: ${it.file.absolutePath}" },
        )
        lastFFmpegDiagnostic = diagnostic
        return diagnostic
    }

    private fun ffmpegCandidates(): List<FFmpegCandidate> {
        val noBackupRoot = File(noBackupFilesDir, "youtubedl-android")
        val ffmpegPackage = File(noBackupRoot, "packages/ffmpeg")
        val nativeDir = File(applicationInfo.nativeLibraryDir)
        return listOfNotNull(
            reflectedYoutubeDLFFmpegPath()?.let {
                FFmpegCandidate("youtubedl-android internal FFmpeg", it)
            },
            FFmpegCandidate("Bundled native libffmpeg.so", File(nativeDir, "libffmpeg.so")),
            FFmpegCandidate("FFmpeg package usr/bin", File(ffmpegPackage, "usr/bin/ffmpeg")),
            FFmpegCandidate("FFmpeg package bin", File(ffmpegPackage, "bin/ffmpeg")),
            FFmpegCandidate("FFmpeg package root", File(ffmpegPackage, "ffmpeg")),
            FFmpegCandidate("App files ffmpeg", File(filesDir, "ffmpeg")),
            FFmpegCandidate("App files bin/ffmpeg", File(filesDir, "bin/ffmpeg")),
            FFmpegCandidate("App no-backup ffmpeg", File(noBackupFilesDir, "ffmpeg")),
        )
    }

    private fun reflectedYoutubeDLFFmpegPath(): File? {
        return try {
            val field = YoutubeDL::class.java.getDeclaredField("ffmpegPath")
            field.isAccessible = true
            field.get(null) as? File
        } catch (_: Throwable) {
            null
        }
    }

    private fun testFFmpegExecutable(file: File): FFmpegTestResult {
        if (!file.exists()) {
            return FFmpegTestResult(false, "Unavailable", "missing at ${file.absolutePath}")
        }
        if (!file.isFile) {
            return FFmpegTestResult(false, "Unavailable", "not a file: ${file.absolutePath}")
        }
        if (!file.canExecute()) {
            file.setExecutable(true, false)
        }
        if (!file.canExecute()) {
            return FFmpegTestResult(false, "Unavailable", "not executable: ${file.absolutePath}")
        }

        return try {
            val process = ProcessBuilder(file.absolutePath, "-version")
                .redirectErrorStream(true)
                .apply {
                    val env = environment()
                    env["LD_LIBRARY_PATH"] = androidLdLibraryPath()
                    env["PATH"] = androidExecutablePath()
                }
                .start()
            if (!process.waitFor(10, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                return FFmpegTestResult(false, "Unavailable", "ffmpeg -version timed out")
            }
            val output = process.inputStream.bufferedReader().readText().trim()
            val firstLine = output.lineSequence().firstOrNull { it.isNotBlank() } ?: "No output"
            if (process.exitValue() == 0) {
                FFmpegTestResult(true, firstLine, "ffmpeg -version ok: $firstLine")
            } else {
                FFmpegTestResult(false, "Unavailable", "ffmpeg -version exited ${process.exitValue()}: $firstLine")
            }
        } catch (error: Throwable) {
            FFmpegTestResult(false, "Unavailable", readableError(error))
        }
    }

    private fun androidLdLibraryPath(): String {
        val packageRoot = File(noBackupFilesDir, "youtubedl-android/packages")
        return listOfNotNull(
            System.getenv("LD_LIBRARY_PATH"),
            applicationInfo.nativeLibraryDir,
            File(packageRoot, "python/usr/lib").absolutePath,
            File(packageRoot, "ffmpeg/usr/lib").absolutePath,
            File(packageRoot, "aria2c/usr/lib").absolutePath,
        ).filter { it.isNotBlank() }.joinToString(":")
    }

    private fun androidExecutablePath(): String {
        val packageRoot = File(noBackupFilesDir, "youtubedl-android/packages")
        return listOfNotNull(
            System.getenv("PATH"),
            applicationInfo.nativeLibraryDir,
            File(packageRoot, "ffmpeg/usr/bin").absolutePath,
            File(packageRoot, "ffmpeg/bin").absolutePath,
            File(packageRoot, "python/usr/bin").absolutePath,
        ).filter { it.isNotBlank() }.joinToString(":")
    }

    private fun androidAbiLabel(): String {
        val supportedAbis = Build.SUPPORTED_ABIS
        return if (supportedAbis.isEmpty()) {
            "Unknown"
        } else {
            supportedAbis.joinToString(", ")
        }
    }

    @Synchronized
    private fun updateYoutubeDLIfNeeded(processId: String) {
        if (updateAttempted) return
        updateAttempted = true

        sendProgress(processId, 0f, "Preparing Download Engine...")
        try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(
                applicationContext,
                YoutubeDL.UpdateChannel.STABLE,
            )
            lastUpdateStatus = when (status) {
                YoutubeDL.UpdateStatus.DONE -> "Updated"
                YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "Already up to date"
                else -> "Checked"
            }
            lastUpdateMessage = null
            sendProgress(processId, 0f, "Download Engine is ready.")
        } catch (error: Throwable) {
            lastUpdateStatus = "Update failed but usable"
            lastUpdateMessage = readableError(error)
            sendProgress(
                processId,
                0f,
                "Download Engine is using the bundled version.",
            )
        }
    }

    private fun workDownloadDir(folderName: String? = null): File {
        val external = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        val base = File(external ?: filesDir, "DownAnyMediaWork")
        return if (folderName.isNullOrBlank()) base else File(base, folderName)
    }

    private fun publicDownloadDisplayDir(): String {
        return "/storage/emulated/0/${Environment.DIRECTORY_DOWNLOADS}/DownAnyMedia"
    }

    private fun postCompletedSafely(
        result: MethodChannel.Result,
        source: File,
        warning: String? = null,
        folderName: String? = null,
        isVideo: Boolean = false,
        selectedFormat: String? = null,
        fallbackStepsTried: List<String> = emptyList(),
        fallbackAttempted: Boolean = false,
        tempFolder: String? = null,
        ffmpegDiagnostic: FFmpegDiagnostic? = null,
        filesFound: List<String> = emptyList(),
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ) {
        try {
            postCompleted(
                result,
                source,
                warning,
                folderName,
                isVideo,
                selectedFormat,
                fallbackStepsTried,
                fallbackAttempted,
                tempFolder,
                ffmpegDiagnostic,
                filesFound,
                relativeBaseFolder,
            )
        } catch (publishError: Throwable) {
            val publishWarning =
                if (isVideo) {
                    "Video created, but publishing to Downloads failed: ${readableError(publishError)}"
                } else {
                    "Audio created, but publishing to Downloads failed: ${readableError(publishError)}"
                }
            val combinedWarning = listOfNotNull(warning, publishWarning).joinToString(" ")
            postSuccess(
                result,
                mapOf(
                    "status" to "completed",
                    "fileName" to source.name,
                    "filePath" to source.absolutePath,
                    "folderPath" to source.parentFile?.absolutePath.orEmpty(),
                    "warning" to combinedWarning,
                    "selectedFormat" to selectedFormat,
                    "fallbackStepsTried" to fallbackStepsTried,
                    "fallbackAttempted" to fallbackAttempted,
                    "finalFilePath" to source.absolutePath,
                    "tempFolder" to tempFolder,
                    "publishResult" to "Publishing failed; file remains in temp folder",
                    "ffmpegAvailable" to (ffmpegDiagnostic?.available == true),
                    "ffmpegPath" to ffmpegDiagnostic?.path,
                    "ffmpegVersion" to ffmpegDiagnostic?.version,
                    "ffmpegExecutionTest" to ffmpegDiagnostic?.executionTest,
                    "videoMergeSupported" to (ffmpegDiagnostic?.videoMergeSupported == true),
                    "androidAbi" to androidAbiLabel(),
                    "filesFound" to filesFound,
                ),
            )
        }
    }

    private fun postCompleted(
        result: MethodChannel.Result,
        source: File,
        warning: String? = null,
        folderName: String? = null,
        isVideo: Boolean = false,
        selectedFormat: String? = null,
        fallbackStepsTried: List<String> = emptyList(),
        fallbackAttempted: Boolean = false,
        tempFolder: String? = null,
        ffmpegDiagnostic: FFmpegDiagnostic? = null,
        filesFound: List<String> = emptyList(),
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ) {
        val published = publishMediaToPublicDownloads(source, folderName, isVideo, relativeBaseFolder)
        val payload = mutableMapOf<String, Any?>(
            "status" to "completed",
            "fileName" to published.fileName,
            "filePath" to published.filePath,
            "folderPath" to published.folderPath,
            "contentUri" to published.contentUri,
            "selectedFormat" to selectedFormat,
            "fallbackStepsTried" to fallbackStepsTried,
            "fallbackAttempted" to fallbackAttempted,
            "finalFilePath" to published.filePath,
            "tempFolder" to tempFolder,
            "publishResult" to "Published to Downloads",
            "ffmpegAvailable" to (ffmpegDiagnostic?.available == true),
            "ffmpegPath" to ffmpegDiagnostic?.path,
            "ffmpegVersion" to ffmpegDiagnostic?.version,
            "ffmpegExecutionTest" to ffmpegDiagnostic?.executionTest,
            "videoMergeSupported" to (ffmpegDiagnostic?.videoMergeSupported == true),
            "androidAbi" to androidAbiLabel(),
            "filesFound" to filesFound,
        )
        if (warning != null) {
            payload["warning"] = warning
        }
        postSuccess(result, payload)
    }

    private fun publishMediaToPublicDownloads(
        source: File,
        folderName: String? = null,
        isVideo: Boolean = false,
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ): PublishedDownload {
        ensurePublicDownloadDir(folderName, relativeBaseFolder = relativeBaseFolder)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return publishMediaWithMediaStore(source, folderName, isVideo, relativeBaseFolder)
        }

        val targetDir = ensurePublicDownloadDir(
            folderName,
            requireWritable = true,
            relativeBaseFolder = relativeBaseFolder,
        )
        val target = uniqueFile(targetDir, source.name)
        source.copyTo(target, overwrite = false)
        source.delete()
        return PublishedDownload(target.name, target.absolutePath, targetDir.absolutePath)
    }

    private fun publishMediaWithMediaStore(
        source: File,
        folderName: String? = null,
        isVideo: Boolean = false,
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ): PublishedDownload {
        val relativeFolder = relativeDownloadFolder(folderName, relativeBaseFolder)
        ensurePublicDownloadDir(folderName, relativeBaseFolder = relativeBaseFolder)
        val displayName = uniqueDisplayName(relativeFolder, source.name)
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI

        var lastError: Throwable? = null
        repeat(2) { attempt ->
            var uri: Uri? = null
            try {
                if (attempt > 0) {
                    ensurePublicDownloadDir(folderName, relativeBaseFolder = relativeBaseFolder)
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mediaMimeType(source, isVideo))
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativeFolder)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                uri = resolver.insert(collection, values)
                    ?: throw IllegalStateException("Could not create file in Downloads.")

                resolver.openOutputStream(uri)?.use { output ->
                    source.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("Could not write media to Downloads.")

                val publishedValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, publishedValues, null, null)
                source.delete()

                return PublishedDownload(
                    displayName,
                    "/storage/emulated/0/$relativeFolder/$displayName",
                    "/storage/emulated/0/$relativeFolder",
                    uri.toString(),
                )
            } catch (error: Throwable) {
                lastError = error
                if (uri != null) {
                    resolver.delete(uri, null, null)
                }
            }
        }
        throw lastError ?: IllegalStateException("Could not publish media to Downloads.")
    }

    private fun publicDownloadDir(
        folderName: String? = null,
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ): File {
        return File(
            Environment.getExternalStorageDirectory(),
            relativeDownloadFolder(folderName, relativeBaseFolder),
        )
    }

    private fun ensurePublicDownloadDir(
        folderName: String? = null,
        requireWritable: Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q,
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ): File {
        val directory = publicDownloadDir(folderName, relativeBaseFolder)
        ensureDirectory(directory, "Could not recreate the download folder.")
        if (requireWritable && !directory.canWrite()) {
            throw IllegalStateException("Storage folder is not writable: ${directory.absolutePath}")
        }
        return directory
    }

    private fun defaultRelativeBaseFolder(): String {
        return "${Environment.DIRECTORY_DOWNLOADS}/DownAnyMedia"
    }

    private fun relativeDownloadFolder(
        folderName: String? = null,
        relativeBaseFolder: String = defaultRelativeBaseFolder(),
    ): String {
        val base = cleanRelativeBaseFolder(relativeBaseFolder) ?: defaultRelativeBaseFolder()
        return if (folderName.isNullOrBlank()) base else "$base/$folderName"
    }

    private fun cleanRelativeBaseFolder(value: String?): String? {
        val cleaned = value
            ?.replace('\\', '/')
            ?.trim('/')
            ?.replace(Regex("""/+"""), "/")
            ?.takeIf { it.isNotBlank() }
            ?: return null
        val normalized = when {
            cleaned == "Downloads" -> Environment.DIRECTORY_DOWNLOADS
            cleaned.startsWith("Downloads/") ->
                "${Environment.DIRECTORY_DOWNLOADS}/${cleaned.substringAfter("Downloads/")}"
            else -> cleaned
        }
        if (normalized != Environment.DIRECTORY_DOWNLOADS &&
            !normalized.startsWith("${Environment.DIRECTORY_DOWNLOADS}/")
        ) {
            return null
        }
        return normalized
    }

    private fun ensureDirectory(directory: File, errorMessage: String): File {
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("$errorMessage Check storage access and try again.")
        }
        if (!directory.isDirectory) {
            throw IllegalStateException("$errorMessage A file exists where the folder should be.")
        }
        return directory
    }

    private fun uniqueDisplayName(relativeFolder: String, fileName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return fileName

        val existing = mutableSetOf<String>()
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        val selection =
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf("$relativeFolder/", "%")
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (nameIndex >= 0) {
                    existing.add(cursor.getString(nameIndex))
                }
            }
        }

        if (!existing.contains(fileName)) return fileName

        val extension = fileName.substringAfterLast('.', "")
        val baseName = if (extension.isEmpty()) fileName else fileName.substringBeforeLast('.')
        var count = 1
        while (true) {
            val nextName = if (extension.isEmpty()) {
                "$baseName ($count)"
            } else {
                "$baseName ($count).$extension"
            }
            if (!existing.contains(nextName)) return nextName
            count += 1
        }
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val extension = fileName.substringAfterLast('.', "")
        val baseName = if (extension.isEmpty()) {
            fileName
        } else {
            fileName.substringBeforeLast('.')
        }
        var candidate = File(directory, fileName)
        var count = 1
        while (candidate.exists()) {
            val nextName = if (extension.isEmpty()) {
                "$baseName ($count)"
            } else {
                "$baseName ($count).$extension"
            }
            candidate = File(directory, nextName)
            count += 1
        }
        return candidate
    }

    private fun cleanPathSegment(value: String?): String? {
        val cleaned = value
            ?.replace(Regex("""[\\/:*?"<>|]+"""), " ")
            ?.replace(Regex("""\s+"""), " ")
            ?.trim()
            ?.take(120)
        return cleaned?.ifBlank { null }
    }

    private fun newestMedia(
        directory: File,
        startedAt: Long,
        isVideo: Boolean,
        taskId: String? = null,
    ): File? {
        val extensions = if (isVideo) {
            setOf("mp4", "mkv", "webm", "mov", "m4v")
        } else {
            setOf("mp3")
        }
        return directory
            .walkTopDown()
            .filter { file ->
                file.isFile &&
                    extensions.contains(file.extension.lowercase()) &&
                    !isTemporaryDownloadFile(file) &&
                    (taskId == null || file.name.contains(taskId)) &&
                    file.lastModified() >= startedAt - 2_000L
            }
            .maxByOrNull { it.lastModified() }
    }

    private fun filesFoundForTask(directory: File, taskId: String?): List<String> {
        if (!directory.exists()) return emptyList()
        return directory
            .walkTopDown()
            .filter { file -> file.isFile && (taskId == null || file.name.contains(taskId)) }
            .sortedByDescending { it.lastModified() }
            .take(20)
            .map { file ->
                val relative = runCatching { file.relativeTo(directory).path }.getOrElse { file.name }
                "$relative (${file.length()} bytes)"
            }
            .toList()
    }

    private fun isTemporaryDownloadFile(file: File): Boolean {
        val name = file.name.lowercase()
        val extension = file.extension.lowercase()
        return extension in setOf("part", "ytdl", "tmp", "temp", "aria2") ||
            name.endsWith(".part") ||
            name.contains(".part-") ||
            name.endsWith(".ytdl") ||
            name.endsWith(".tmp") ||
            name.endsWith(".temp")
    }

    private fun mediaMimeType(file: File, isVideo: Boolean): String {
        if (!isVideo) return "audio/mpeg"
        return when (file.extension.lowercase()) {
            "webm" -> "video/webm"
            "mkv" -> "video/x-matroska"
            "mov" -> "video/quicktime"
            "m4v" -> "video/mp4"
            else -> "video/mp4"
        }
    }

    private fun sendProgress(processId: String, progress: Float, line: String) {
        if (!shouldSendProgress(progress, line)) {
            return
        }
        mainHandler.post {
            channel?.invokeMethod(
                "downloadProgress",
                mapOf(
                    "processId" to processId,
                    "progress" to progress.toDouble(),
                    "line" to line,
                ),
            )
        }
    }

    private fun shouldSendProgress(progress: Float, line: String): Boolean {
        val now = System.currentTimeMillis()
        val lower = line.lowercase()
        val important = lower.contains("publishing") ||
            lower.contains("retrying") ||
            lower.contains("media processing") ||
            lower.contains("download engine") ||
            lower.startsWith("error") ||
            progress >= 100f
        if (important) {
            lastProgressUiUpdateAt = now
            return true
        }
        if (now - lastProgressUiUpdateAt < 500L) {
            return false
        }
        lastProgressUiUpdateAt = now
        return true
    }

    private fun openFile(call: MethodCall): Boolean {
        val contentUri = call.argument<String>("contentUri")
        val filePath = call.argument<String>("filePath")
        val uri = when {
            !contentUri.isNullOrBlank() -> Uri.parse(contentUri)
            !filePath.isNullOrBlank() -> Uri.fromFile(File(filePath))
            else -> return false
        }

        return try {
            val mimeType = if (!filePath.isNullOrBlank()) {
                mediaMimeType(File(filePath), filePath.substringAfterLast('.', "").lowercase() != "mp3")
            } else {
                "*/*"
            }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun openFolder(call: MethodCall): Boolean {
        val folderPath = call.argument<String>("folderPath")
            ?.takeIf { it.isNotBlank() }
            ?: publicDownloadDisplayDir()
        val relativePath = folderPath
            .substringAfter("/storage/emulated/0/", "${Environment.DIRECTORY_DOWNLOADS}/DownAnyMedia")
            .trim('/')

        val documentUri = Uri.parse(
            "content://com.android.externalstorage.documents/document/" +
                Uri.encode("primary:$relativePath"),
        )
        val openedFolder = try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(documentUri, "vnd.android.document/directory")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }

        if (openedFolder) {
            return true
        }

        return try {
            val intent = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun postSuccess(result: MethodChannel.Result, payload: Map<String, Any?>) {
        mainHandler.post { result.success(payload) }
    }

    private fun postError(result: MethodChannel.Result, message: String) {
        mainHandler.post { result.error("download_failed", message, null) }
    }

    private fun readableError(error: Throwable): String {
        val message = error.message?.trim().orEmpty()
        if (message.isNotBlank()) {
            return message
        }

        return when (error) {
            is YoutubeDLException -> "Download Engine failed on Android."
            else -> error.toString()
        }
    }

    private fun looksLikeOptionalMetadataFailure(message: String): Boolean {
        val lower = message.lowercase()
        return lower.contains("thumbnail") ||
            lower.contains("metadata") ||
            lower.contains("embedthumbnail") ||
            lower.contains("atomicparsley")
    }

    private data class PublishedDownload(
        val fileName: String,
        val filePath: String,
        val folderPath: String,
        val contentUri: String? = null,
    )

    private data class FFmpegCandidate(
        val label: String,
        val file: File,
    )

    private data class FFmpegTestResult(
        val available: Boolean,
        val version: String,
        val message: String,
    )

    private data class FFmpegDiagnostic(
        val available: Boolean,
        val path: String?,
        val version: String,
        val executionTest: String,
        val failureReason: String?,
        val androidAbi: String,
        val videoMergeSupported: Boolean,
        val candidates: List<String>,
    )

    private data class VideoAttempt(
        val format: String?,
        val requiresFFmpeg: Boolean,
        val label: String,
    )
}
