package com.nasserver.nas_server

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.Intent.FLAG_ACTIVITY_NEW_TASK
import android.content.IntentFilter
import android.database.ContentObserver
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ThumbnailUtils
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream

class NasServerNativeBridge(
    context: Context,
) {
    companion object {
        private const val NSD_CHANNEL = "com.nasserver.nas_server/nsd"
        private const val SYSTEM_INFO_CHANNEL = "com.nas.server/system_info"
        private const val DEVICE_INFO_CHANNEL = "com.nasserver.nas_server/device_info"
        private const val MEDIA_STORE_CHANNEL = "com.nasserver.nas_server/mediastore"
        private const val THUMBNAIL_CHANNEL = "com.nasserver.nas_server/thumbnail"
        private const val POWER_MANAGEMENT_CHANNEL =
            "com.nasserver.nas_server/power_management"
        private const val MEDIA_CHANGE_CHANNEL = "com.nasserver.nas_server/media_change"
        private const val TLS_CHANNEL = "com.nasserver.nas_server/tls"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val nativeTlsMaterialService = NativeTlsMaterialService(appContext)

    private var registrationListener: NsdManager.RegistrationListener? = null
    private var registeredServiceName: String? = null
    private var mediaContentObserver: MediaContentObserver? = null
    private var activeMediaChangeChannel: MethodChannel? = null

    fun registerChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, NSD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "registerService" -> {
                    val serviceName = call.argument<String>("serviceName") ?: "铥棒文件S"
                    val serviceType = call.argument<String>("serviceType") ?: "_webdavs._tcp."
                    val port = call.argument<Int>("port") ?: 8080
                    val txtRecords = call.argument<Map<String, String>>("txtRecords") ?: emptyMap()
                    registerNsdService(serviceName, serviceType, port, txtRecords, result)
                }

                "unregisterService" -> {
                    unregisterNsdService(result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, SYSTEM_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> {
                    result.success(getStorageInfo())
                }

                "getMemoryInfo" -> {
                    result.success(getMemoryInfo())
                }

                "getCpuTemperature" -> {
                    result.success(getCpuTemperature())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, DEVICE_INFO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    result.success(getDeviceInfo())
                }

                "getAndroidId" -> {
                    result.success(getAndroidId())
                }

                "getModel" -> {
                    result.success(Build.MODEL)
                }

                "getSystemVersion" -> {
                    result.success(Build.VERSION.RELEASE)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, MEDIA_STORE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "queryImages" -> {
                    result.success(
                        queryMediaFiles(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            "image",
                        ),
                    )
                }

                "queryVideos" -> {
                    result.success(
                        queryMediaFiles(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            "video",
                        ),
                    )
                }

                "readMediaFile" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val rangeStart = call.argument<Number>("rangeStart")?.toLong()
                    val rangeEnd = call.argument<Number>("rangeEnd")?.toLong()
                    result.success(readMediaFile(uri, rangeStart, rangeEnd))
                }

                "getMediaFileInfo" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    result.success(getMediaFileInfo(uri))
                }

                "getMediaFileCount" -> {
                    val type = call.argument<String>("type") ?: "image"
                    result.success(getMediaFileCount(type))
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, THUMBNAIL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateThumbnail" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val size = call.argument<Int>("size") ?: 200
                    result.success(generateThumbnail(filePath, size))
                }

                "generateThumbnailFromUri" -> {
                    val contentUri = call.argument<String>("contentUri") ?: ""
                    val size = call.argument<Int>("size") ?: 200
                    result.success(generateThumbnailFromUri(contentUri, size))
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, POWER_MANAGEMENT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                "requestIgnoreBatteryOptimizations" -> {
                    result.success(requestIgnoreBatteryOptimizations())
                }

                "openAppManagementSettings" -> {
                    result.success(openAppManagementSettings())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, TLS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureTlsMaterial" -> {
                    val serverId = call.argument<String>("serverId")?.trim().orEmpty()
                    val hostLabel = call.argument<String>("hostLabel")?.trim().orEmpty()
                    val localIp = call.argument<String>("localIp")?.trim().orEmpty()

                    if (serverId.isEmpty() || hostLabel.isEmpty() || localIp.isEmpty()) {
                        result.error(
                            "INVALID_TLS_REQUEST",
                            "serverId, hostLabel and localIp are required",
                            null,
                        )
                    } else {
                        try {
                            result.success(
                                nativeTlsMaterialService.ensureTlsMaterial(
                                    serverId = serverId,
                                    hostLabel = hostLabel,
                                    localIp = localIp,
                                ),
                            )
                        } catch (error: Exception) {
                            result.error(
                                "TLS_GENERATION_ERROR",
                                error.message ?: "Failed to ensure TLS material",
                                null,
                            )
                        }
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        val mediaChangeChannel = MethodChannel(messenger, MEDIA_CHANGE_CHANNEL)
        mediaChangeChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startMediaChangeObserver" -> {
                    activeMediaChangeChannel = mediaChangeChannel
                    startMediaChangeObserver()
                    result.success(true)
                }

                "stopMediaChangeObserver" -> {
                    if (activeMediaChangeChannel === mediaChangeChannel) {
                        stopMediaChangeObserver()
                    }
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getDeviceInfo(): Map<String, Any> {
        val batteryStatus = getBatteryStatus()
        return try {
            mapOf(
                "deviceId" to getAndroidId(),
                "deviceName" to "铥棒文件S",
                "model" to Build.MODEL,
                "brand" to Build.BRAND,
                "manufacturer" to Build.MANUFACTURER,
                "systemVersion" to Build.VERSION.RELEASE,
                "batteryLevel" to batteryStatus.first,
                "batteryPercent" to batteryStatus.second,
                "isCharging" to batteryStatus.third,
            )
        } catch (_: Exception) {
            mapOf(
                "deviceId" to "nas-server-001",
                "deviceName" to "铥棒文件S",
                "model" to "Unknown",
                "brand" to "Unknown",
                "manufacturer" to "Unknown",
                "systemVersion" to "Unknown",
                "batteryLevel" to 0,
                "batteryPercent" to 0.0,
                "isCharging" to false,
            )
        }
    }

    private fun getBatteryStatus(): Triple<Int, Double, Boolean> {
        return try {
            val batteryManager =
                appContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            var batteryPercent =
                batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            if (batteryPercent < 0 || batteryPercent > 100) {
                batteryPercent = 0
            }

            val batteryIntent =
                appContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status =
                batteryIntent?.getIntExtra(
                    BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN,
                ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN

            val level =
                when (status) {
                    BatteryManager.BATTERY_STATUS_UNKNOWN -> 1
                    BatteryManager.BATTERY_STATUS_CHARGING -> 2
                    BatteryManager.BATTERY_STATUS_DISCHARGING -> 3
                    BatteryManager.BATTERY_STATUS_NOT_CHARGING -> 4
                    BatteryManager.BATTERY_STATUS_FULL -> 5
                    else -> 1
                }

            val isCharging =
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL

            Triple(level, batteryPercent.toDouble(), isCharging)
        } catch (_: Exception) {
            Triple(1, 0.0, false)
        }
    }

    private fun getAndroidId(): String {
        return try {
            Settings.Secure.getString(
                appContext.contentResolver,
                Settings.Secure.ANDROID_ID,
            ) ?: "nas-server-001"
        } catch (_: Exception) {
            "nas-server-001"
        }
    }

    private fun queryMediaFiles(contentUri: Uri, type: String): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val nasServerPath = "/sdcard/NASServer/"

        val projection =
            arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.DATA,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.MIME_TYPE,
                MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.BUCKET_ID,
                MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            )

        val selection = "${MediaStore.MediaColumns.DATA} NOT LIKE ?"
        val selectionArgs = arrayOf("$nasServerPath%")

        var cursor: Cursor? = null
        try {
            cursor =
                appContext.contentResolver.query(
                    contentUri,
                    projection,
                    selection,
                    selectionArgs,
                    null,
                )
            cursor?.let {
                val idColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val dataColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                val sizeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val mimeColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                val dateColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                val bucketIdColumn = it.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_ID)
                val bucketNameColumn =
                    it.getColumnIndexOrThrow(MediaStore.MediaColumns.BUCKET_DISPLAY_NAME)

                while (it.moveToNext()) {
                    val id = it.getLong(idColumn)
                    val data = it.getString(dataColumn) ?: ""
                    val bucketId = it.getString(bucketIdColumn) ?: ""
                    val bucketDisplayName = it.getString(bucketNameColumn) ?: "Unknown"

                    val contentUriString =
                        Uri.withAppendedPath(contentUri, id.toString()).toString()

                    val item = mutableMapOf<String, Any?>()
                    item["id"] = id
                    item["contentUri"] = contentUriString
                    item["displayName"] = it.getString(nameColumn) ?: ""
                    item["relativePath"] = getRelativePath(data, bucketDisplayName)
                    item["size"] = it.getLong(sizeColumn)
                    item["mimeType"] = it.getString(mimeColumn) ?: ""
                    item["dateModified"] = it.getLong(dateColumn) * 1000
                    item["mediaType"] = type
                    item["bucketId"] = bucketId
                    item["bucketDisplayName"] = bucketDisplayName
                    results.add(item)
                }
            }
        } catch (_: Exception) {
        } finally {
            cursor?.close()
        }

        return results
    }

    private fun getRelativePath(fullPath: String, bucketName: String): String {
        return try {
            val pathParts = fullPath.split("/")
            val bucketIndex = pathParts.indexOf(bucketName)
            if (bucketIndex >= 0 && bucketIndex < pathParts.size - 1) {
                pathParts.subList(bucketIndex, pathParts.size).joinToString("/")
            } else {
                fullPath.substringAfter("/storage/emulated/0/")
            }
        } catch (_: Exception) {
            fullPath
        }
    }

    private fun readMediaFile(
        uriString: String,
        rangeStart: Long?,
        rangeEnd: Long?,
    ): Map<String, Any?> {
        return try {
            val uri = Uri.parse(uriString)
            val pfd: ParcelFileDescriptor? =
                appContext.contentResolver.openFileDescriptor(uri, "r")

            pfd?.let {
                val totalSize = it.statSize
                lateinit var bytes: ByteArray

                if (rangeStart != null && rangeEnd != null) {
                    FileInputStream(it.fileDescriptor).use { inputStream ->
                        inputStream.channel.position(rangeStart)
                        val expectedLength =
                            (rangeEnd - rangeStart + 1).coerceAtLeast(0).toInt()
                        val tempBytes = ByteArray(expectedLength)
                        var offset = 0
                        while (offset < expectedLength) {
                            val readBytes =
                                inputStream.read(
                                    tempBytes,
                                    offset,
                                    expectedLength - offset,
                                )
                            if (readBytes <= 0) {
                                break
                            }
                            offset += readBytes
                        }
                        bytes =
                            if (offset < tempBytes.size) {
                                tempBytes.copyOf(offset)
                            } else {
                                tempBytes
                            }
                    }
                } else {
                    FileInputStream(it.fileDescriptor).use { inputStream ->
                        bytes = inputStream.readBytes()
                    }
                }

                it.close()

                return mapOf(
                    "bytes" to bytes.toList(),
                    "totalSize" to totalSize,
                )
            }

            mapOf("bytes" to listOf<Byte>(), "totalSize" to 0)
        } catch (_: Exception) {
            mapOf("bytes" to listOf<Byte>(), "totalSize" to 0)
        }
    }

    private fun getMediaFileInfo(uriString: String): Map<String, Any?> {
        return try {
            val uri = Uri.parse(uriString)
            val pfd: ParcelFileDescriptor? =
                appContext.contentResolver.openFileDescriptor(uri, "r")

            pfd?.let {
                val size = it.statSize
                it.close()
                return mapOf("size" to size)
            }

            mapOf("size" to 0)
        } catch (_: Exception) {
            mapOf("size" to 0)
        }
    }

    private fun getMediaFileCount(type: String): Int {
        val contentUri =
            when (type) {
                "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                else -> return 0
            }

        var cursor: Cursor? = null
        return try {
            cursor =
                appContext.contentResolver.query(
                    contentUri,
                    arrayOf(MediaStore.MediaColumns._ID),
                    null,
                    null,
                    null,
                )
            cursor?.count ?: 0
        } catch (_: Exception) {
            0
        } finally {
            cursor?.close()
        }
    }

    private fun getStorageInfo(): Map<String, Any> {
        return try {
            val path = android.os.Environment.getExternalStorageDirectory()
            val stat = StatFs(path.path)

            val blockSize = stat.blockSizeLong
            val totalBlocks = stat.blockCountLong
            val availableBlocks = stat.availableBlocksLong

            val totalBytes = totalBlocks * blockSize
            val freeBytes = availableBlocks * blockSize
            val usedBytes = totalBytes - freeBytes
            val usagePercent =
                if (totalBytes > 0) {
                    (usedBytes.toDouble() / totalBytes.toDouble()) * 100
                } else {
                    0.0
                }

            mapOf(
                "totalBytes" to totalBytes,
                "usedBytes" to usedBytes,
                "freeBytes" to freeBytes,
                "usagePercent" to usagePercent,
            )
        } catch (_: Exception) {
            mapOf(
                "totalBytes" to 0L,
                "usedBytes" to 0L,
                "freeBytes" to 0L,
                "usagePercent" to 0.0,
            )
        }
    }

    private fun getMemoryInfo(): Map<String, Any> {
        return try {
            val activityManager =
                appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)

            val totalBytes = memInfo.totalMem
            val availableBytes = memInfo.availMem
            val usedBytes = totalBytes - availableBytes
            val usagePercent =
                if (totalBytes > 0) {
                    (usedBytes.toDouble() / totalBytes.toDouble()) * 100
                } else {
                    0.0
                }

            mapOf(
                "totalBytes" to totalBytes,
                "usedBytes" to usedBytes,
                "freeBytes" to availableBytes,
                "usagePercent" to usagePercent,
            )
        } catch (_: Exception) {
            mapOf(
                "totalBytes" to 0L,
                "usedBytes" to 0L,
                "freeBytes" to 0L,
                "usagePercent" to 0.0,
            )
        }
    }

    private fun getCpuTemperature(): Map<String, Any> {
        return try {
            val thermalDir = File("/sys/class/thermal")
            if (thermalDir.exists()) {
                val zones = thermalDir.listFiles()
                if (zones != null) {
                    for (zone in zones) {
                        if (zone.isDirectory && zone.name.startsWith("thermal_zone")) {
                            val tempFile = File(zone, "temp")
                            if (tempFile.exists()) {
                                val tempStr = tempFile.readText().trim()
                                val temp = tempStr.toLongOrNull()
                                if (temp != null) {
                                    return mapOf("temperature" to (temp.toDouble() / 1000.0))
                                }
                            }
                        }
                    }
                }
            }
            mapOf("temperature" to 0.0)
        } catch (_: Exception) {
            mapOf("temperature" to 0.0)
        }
    }

    private fun generateThumbnail(filePath: String, size: Int): Map<String, Any?> {
        return try {
            val file = File(filePath)
            if (!file.exists()) {
                return mapOf(
                    "bytes" to listOf<Byte>(),
                    "success" to false,
                    "error" to "File not found",
                )
            }

            val extension = file.extension.lowercase()
            val isVideo = listOf("mp4", "mkv", "avi", "mov", "webm", "3gp").contains(extension)

            val thumbnail: Bitmap? =
                if (isVideo) {
                    val videoThumbnail = ThumbnailUtils.createVideoThumbnail(file, Size(size, size), null)
                    videoThumbnail?.let { scaleBitmapKeepAspectRatio(it, size) }
                } else {
                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(file.absolutePath, options)

                    val originalWidth = options.outWidth
                    val originalHeight = options.outHeight

                    val scaleFactor =
                        maxOf(originalWidth / size, originalHeight / size).coerceAtLeast(1)

                    options.apply {
                        inJustDecodeBounds = false
                        inSampleSize = scaleFactor
                    }

                    BitmapFactory.decodeFile(file.absolutePath, options)?.let { original ->
                        scaleBitmapKeepAspectRatio(original, size)
                    }
                }

            if (thumbnail != null) {
                val outputStream = ByteArrayOutputStream()
                val format =
                    when (extension) {
                        "png" -> Bitmap.CompressFormat.PNG
                        "webp" -> Bitmap.CompressFormat.WEBP
                        else -> Bitmap.CompressFormat.JPEG
                    }
                thumbnail.compress(format, 85, outputStream)
                val bytes = outputStream.toByteArray()
                thumbnail.recycle()

                mapOf("bytes" to bytes.toList(), "success" to true)
            } else {
                mapOf(
                    "bytes" to listOf<Byte>(),
                    "success" to false,
                    "error" to "Failed to generate thumbnail",
                )
            }
        } catch (e: Exception) {
            mapOf("bytes" to listOf<Byte>(), "success" to false, "error" to e.message)
        }
    }

    private fun generateThumbnailFromUri(contentUri: String, size: Int): Map<String, Any?> {
        return try {
            val uri = Uri.parse(contentUri)
            val thumbnail: Bitmap? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    appContext.contentResolver.loadThumbnail(uri, Size(size, size), null)
                } else {
                    val pfd: ParcelFileDescriptor? =
                        appContext.contentResolver.openFileDescriptor(uri, "r")
                    pfd?.let {
                        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                        BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, options)

                        val originalWidth = options.outWidth
                        val originalHeight = options.outHeight

                        val scaleFactor =
                            maxOf(originalWidth / size, originalHeight / size).coerceAtLeast(1)

                        options.apply {
                            inJustDecodeBounds = false
                            inSampleSize = scaleFactor
                        }

                        val bitmap =
                            BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, options)
                        it.close()
                        bitmap?.let { b -> scaleBitmapKeepAspectRatio(b, size) }
                    }
                }

            if (thumbnail != null) {
                val outputStream = ByteArrayOutputStream()
                thumbnail.compress(Bitmap.CompressFormat.JPEG, 85, outputStream)
                val bytes = outputStream.toByteArray()
                thumbnail.recycle()

                mapOf("bytes" to bytes.toList(), "success" to true)
            } else {
                mapOf(
                    "bytes" to listOf<Byte>(),
                    "success" to false,
                    "error" to "Failed to generate thumbnail from URI",
                )
            }
        } catch (e: Exception) {
            mapOf("bytes" to listOf<Byte>(), "success" to false, "error" to e.message)
        }
    }

    private fun scaleBitmapKeepAspectRatio(bitmap: Bitmap, maxSize: Int): Bitmap {
        val originalWidth = bitmap.width
        val originalHeight = bitmap.height

        if (originalWidth == maxSize && originalHeight == maxSize) {
            return bitmap
        }

        val aspectRatio = originalWidth.toFloat() / originalHeight.toFloat()

        val targetWidth: Int
        val targetHeight: Int

        if (aspectRatio > 1) {
            targetWidth = maxSize
            targetHeight = (maxSize / aspectRatio).toInt()
        } else {
            targetHeight = maxSize
            targetWidth = (maxSize * aspectRatio).toInt()
        }

        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
        if (scaledBitmap != bitmap) {
            bitmap.recycle()
        }
        return scaledBitmap
    }

    private fun registerNsdService(
        serviceName: String,
        serviceType: String,
        port: Int,
        txtRecords: Map<String, String>,
        result: MethodChannel.Result,
    ) {
        if (registrationListener != null) {
            unregisterNsdServiceInternal()
        }

        val serviceInfo =
            NsdServiceInfo().apply {
                this.serviceName = serviceName
                this.serviceType = serviceType
                this.port = port
                for ((key, value) in txtRecords) {
                    setAttribute(key, value)
                }
            }

        registrationListener =
            object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                    registeredServiceName = serviceInfo.serviceName
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "success" to true,
                                "serviceName" to registeredServiceName,
                            ),
                        )
                    }
                }

                override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    mainHandler.post {
                        result.error(
                            "REGISTRATION_FAILED",
                            "Failed to register service: $errorCode",
                            null,
                        )
                    }
                }

                override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                    registeredServiceName = null
                }

                override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            }

        try {
            nsdManager.registerService(
                serviceInfo,
                NsdManager.PROTOCOL_DNS_SD,
                registrationListener,
            )
        } catch (e: Exception) {
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun unregisterNsdService(result: MethodChannel.Result) {
        unregisterNsdServiceInternal()
        result.success(mapOf("success" to true))
    }

    private fun unregisterNsdServiceInternal() {
        if (registrationListener != null) {
            try {
                nsdManager.unregisterService(registrationListener)
            } catch (_: Exception) {
            }
            registrationListener = null
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        val powerManager = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(appContext.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }

        if (isIgnoringBatteryOptimizations()) {
            return true
        }

        val requestIntent =
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${appContext.packageName}")
                addFlags(FLAG_ACTIVITY_NEW_TASK)
            }
        val fallbackIntent =
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(FLAG_ACTIVITY_NEW_TASK)
            }

        return try {
            appContext.startActivity(requestIntent)
            false
        } catch (_: Exception) {
            try {
                appContext.startActivity(fallbackIntent)
                false
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun openAppManagementSettings(): Boolean {
        val intents =
            listOf(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${appContext.packageName}")
                },
                Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS),
                Intent(Settings.ACTION_APPLICATION_SETTINGS),
                Intent(Settings.ACTION_SETTINGS),
            )

        return launchFirstAvailableIntent(intents)
    }

    private fun launchFirstAvailableIntent(intents: List<Intent>): Boolean {
        for (intent in intents) {
            try {
                intent.addFlags(FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(appContext.packageManager) != null) {
                    appContext.startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun startMediaChangeObserver() {
        if (mediaContentObserver != null) {
            return
        }

        mediaContentObserver = MediaContentObserver(Handler(Looper.getMainLooper()))

        appContext.contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            mediaContentObserver!!,
        )
        appContext.contentResolver.registerContentObserver(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            true,
            mediaContentObserver!!,
        )
    }

    private fun stopMediaChangeObserver() {
        mediaContentObserver?.let {
            appContext.contentResolver.unregisterContentObserver(it)
        }
        mediaContentObserver = null
        activeMediaChangeChannel = null
    }

    private inner class MediaContentObserver(
        handler: Handler,
    ) : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            super.onChange(selfChange)
            notifyMediaChange()
        }

        override fun onChange(selfChange: Boolean, uri: Uri?) {
            super.onChange(selfChange, uri)
            notifyMediaChange()
        }

        private fun notifyMediaChange() {
            mainHandler.post {
                activeMediaChangeChannel?.invokeMethod("onMediaChanged", null)
            }
        }
    }
}
