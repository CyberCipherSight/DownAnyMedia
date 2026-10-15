package com.example.down_any_media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import com.yausername.youtubedl_android.YoutubeDL

class DownloadForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = buildNotification(
                    this,
                    intent,
                    ongoing = true,
                    status = intent.getStringExtra(EXTRA_STATUS) ?: "Preparing download...",
                )
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_UPDATE -> notificationManager(this).notify(
                NOTIFICATION_ID,
                buildNotification(this, intent, ongoing = true),
            )
            ACTION_COMPLETE -> {
                stopForegroundCompat()
                notificationManager(this).notify(
                    NOTIFICATION_ID,
                    buildNotification(this, intent, ongoing = false, completed = true),
                )
                stopSelf()
            }
            ACTION_FAILED -> {
                stopForegroundCompat()
                notificationManager(this).notify(
                    NOTIFICATION_ID,
                    buildNotification(this, intent, ongoing = false, failed = true),
                )
                stopSelf()
            }
            ACTION_CANCEL -> {
                intent.getStringExtra(EXTRA_PROCESS_ID)?.let {
                    YoutubeDL.getInstance().destroyProcessById(it)
                }
                notificationManager(this).notify(
                    NOTIFICATION_ID,
                    buildNotification(this, intent, ongoing = true, status = "Cancelling"),
                )
            }
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
    }

    companion object {
        const val ACTION_START = "com.example.down_any_media.DOWNLOAD_START"
        const val ACTION_UPDATE = "com.example.down_any_media.DOWNLOAD_UPDATE"
        const val ACTION_COMPLETE = "com.example.down_any_media.DOWNLOAD_COMPLETE"
        const val ACTION_FAILED = "com.example.down_any_media.DOWNLOAD_FAILED"
        const val ACTION_CANCEL = "com.example.down_any_media.DOWNLOAD_CANCEL"
        const val ACTION_STOP = "com.example.down_any_media.DOWNLOAD_STOP"
        const val EXTRA_PROCESS_ID = "processId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATUS = "status"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_QUEUE_INDEX = "queueIndex"
        const val EXTRA_QUEUE_TOTAL = "queueTotal"
        private const val CHANNEL_ID = "down_any_media_downloads"
        private const val NOTIFICATION_ID = 4201

        fun start(
            context: Context,
            processId: String,
            title: String,
            progress: Int,
            status: String,
            queueIndex: Int,
            queueTotal: Int,
        ) {
            val intent = notificationIntent(
                context,
                ACTION_START,
                processId,
                title,
                progress,
                status,
                queueIndex,
                queueTotal,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(
            context: Context,
            processId: String,
            title: String,
            progress: Int,
            status: String,
            queueIndex: Int,
            queueTotal: Int,
        ) {
            val intent = notificationIntent(
                context,
                ACTION_UPDATE,
                processId,
                title,
                progress,
                status,
                queueIndex,
                queueTotal,
            )
            ensureNotificationChannel(context)
            notificationManager(context).notify(
                NOTIFICATION_ID,
                buildNotification(context, intent, ongoing = true),
            )
        }

        fun finish(
            context: Context,
            action: String,
            processId: String,
            title: String,
            progress: Int,
            status: String,
            queueIndex: Int,
            queueTotal: Int,
        ) {
            context.startService(
                notificationIntent(
                    context,
                    action,
                    processId,
                    title,
                    progress,
                    status,
                    queueIndex,
                    queueTotal,
                ),
            )
        }

        private fun notificationIntent(
            context: Context,
            action: String,
            processId: String,
            title: String,
            progress: Int,
            status: String,
            queueIndex: Int,
            queueTotal: Int,
        ): Intent {
            return Intent(context, DownloadForegroundService::class.java).apply {
                this.action = action
                putExtra(EXTRA_PROCESS_ID, processId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_STATUS, status)
                putExtra(EXTRA_QUEUE_INDEX, queueIndex)
                putExtra(EXTRA_QUEUE_TOTAL, queueTotal)
            }
        }

        private fun buildNotification(
            context: Context,
            intent: Intent,
            ongoing: Boolean,
            completed: Boolean = false,
            failed: Boolean = false,
            status: String? = null,
        ): Notification {
            val title = intent.getStringExtra(EXTRA_TITLE)?.ifBlank { null } ?: "Download"
            val queueIndex = intent.getIntExtra(EXTRA_QUEUE_INDEX, 0)
            val queueTotal = intent.getIntExtra(EXTRA_QUEUE_TOTAL, 0)
            val progress = intent.getIntExtra(EXTRA_PROGRESS, -1).coerceIn(-1, 100)
            val state = status
                ?: when {
                    completed -> "Completed"
                    failed -> "Failed"
                    else -> intent.getStringExtra(EXTRA_STATUS) ?: "Downloading"
                }
            val content = if (queueIndex > 0 && queueTotal > 0) {
                "$state $queueIndex/$queueTotal"
            } else {
                state
            }

            val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            val openPendingIntent = PendingIntent.getActivity(
                context,
                0,
                openIntent,
                pendingIntentFlags(),
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(content)
                .setContentIntent(openPendingIntent)
                .setOngoing(ongoing)
                .setOnlyAlertOnce(true)
                .setAutoCancel(!ongoing)

            if (progress >= 0 && ongoing) {
                builder.setProgress(100, progress, false)
                builder.setSubText("$progress%")
            } else if (ongoing) {
                builder.setProgress(0, 0, true)
            }

            if (ongoing) {
                val cancelIntent = Intent(context, DownloadForegroundService::class.java).apply {
                    action = ACTION_CANCEL
                    putExtra(EXTRA_PROCESS_ID, intent.getStringExtra(EXTRA_PROCESS_ID))
                    putExtra(EXTRA_TITLE, title)
                }
                val cancelPendingIntent = PendingIntent.getService(
                    context,
                    1,
                    cancelIntent,
                    pendingIntentFlags(),
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    builder.addAction(
                        Notification.Action.Builder(
                            android.R.drawable.ic_menu_close_clear_cancel,
                            "Cancel",
                            cancelPendingIntent,
                        ).build(),
                    )
                } else {
                    @Suppress("DEPRECATION")
                    builder.addAction(
                        android.R.drawable.ic_menu_close_clear_cancel,
                        "Cancel",
                        cancelPendingIntent,
                    )
                }
            }

            return builder.build()
        }

        private fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "DownAnyMedia download progress"
            }
            notificationManager(context).createNotificationChannel(channel)
        }

        private fun notificationManager(context: Context): NotificationManager {
            return context.getSystemService(NotificationManager::class.java)
        }

        private fun pendingIntentFlags(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        }
    }
}
