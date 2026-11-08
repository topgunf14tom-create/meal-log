package __PACKAGE__

// tool/setup.sh（setup.ps1）が android/ 生成後にこのファイルで上書きする。
// ヘルスコネクト（端末内）から体重・体脂肪・歩数・運動を読み取り、Dart 側へ渡す。
// 読み取りのみで、書き込みや外部送信はしない。

import android.content.Intent
import android.os.Bundle
import java.io.File
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.LeanBodyMassRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.records.metadata.DataOrigin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.reflect.KClass

class MainActivity : FlutterActivity() {
    private val scope = MainScope()
    private var pendingRequest: MethodChannel.Result? = null
    private val permissionContract = PermissionController.createRequestPermissionResultContract()

    /** Dart 側のキー → ヘルスコネクトの読み取り権限 */
    private val permissionKeys: Map<String, String> = mapOf(
        "weight" to HealthPermission.getReadPermission(WeightRecord::class),
        "bodyFat" to HealthPermission.getReadPermission(BodyFatRecord::class),
        "leanMass" to HealthPermission.getReadPermission(LeanBodyMassRecord::class),
        "height" to HealthPermission.getReadPermission(HeightRecord::class),
        "steps" to HealthPermission.getReadPermission(StepsRecord::class),
        "exercise" to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        "activeKcal" to HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        "distance" to HealthPermission.getReadPermission(DistanceRecord::class),
        // 30日より前のデータを読む権限（対応していない端末では許可されないだけ）
        "history" to "android.permission.health.READ_HEALTH_DATA_HISTORY",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashRecorder()
        super.onCreate(savedInstanceState)
    }

    /** 落ちたときの原因を保存し、次回起動時に Dart 側で表示する */
    private fun installCrashRecorder() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        if (previous is CrashRecorder) return
        Thread.setDefaultUncaughtExceptionHandler(CrashRecorder(File(filesDir, CRASH_FILE), previous))
    }

    private class CrashRecorder(
        private val file: File,
        private val previous: Thread.UncaughtExceptionHandler?,
    ) : Thread.UncaughtExceptionHandler {
        override fun uncaughtException(t: Thread, e: Throwable) {
            try {
                file.writeText(
                    "${java.util.Date()} / Android ${android.os.Build.VERSION.RELEASE} (SDK ${android.os.Build.VERSION.SDK_INT}) / " +
                        "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}\n\n" + e.stackTraceToString().take(6000)
                )
            } catch (_: Exception) {
            }
            previous?.uncaughtException(t, e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun sdkStatus(): String = when (HealthConnectClient.getSdkStatus(this)) {
        HealthConnectClient.SDK_AVAILABLE -> "available"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update_required"
        else -> "unavailable"
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "status") {
            result.success(sdkStatus())
            return
        }
        if (call.method == "lastCrash") {
            val f = File(filesDir, CRASH_FILE)
            val text = if (f.exists()) f.readText() else null
            f.delete()
            result.success(text)
            return
        }
        if (call.method == "openSettings") {
            try {
                startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
            return
        }
        if (sdkStatus() != "available") {
            result.error("unavailable", "ヘルスコネクトが使えません", null)
            return
        }
        val client = HealthConnectClient.getOrCreate(this)
        if (call.method == "request") {
            pendingRequest?.error("cancelled", "別の権限リクエストが始まりました", null)
            try {
                pendingRequest = result
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Android 14 以降はヘルスコネクトが OS に組み込まれ、通常の権限リクエストで許可画面が出る
                    requestPermissions(permissionKeys.values.toTypedArray(), REQUEST_CODE)
                } else {
                    val intent = permissionContract.createIntent(this, permissionKeys.values.toSet())
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, REQUEST_CODE)
                }
            } catch (e: Throwable) {
                pendingRequest = null
                result.error("request_failed", "${e.javaClass.simpleName}: ${e.message}", e.stackTraceToString().take(3000))
            }
            return
        }
        scope.launch {
            try {
                when (call.method) {
                    "granted" -> result.success(grantedKeys(client))
                    "readBody" -> result.success(readBody(client, call))
                    "readSessions" -> result.success(readSessions(client, call))
                    "aggregate" -> result.success(aggregate(client, call))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("health_error", e.message ?: e.toString(), null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE) deliverGranted()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE) deliverGranted()
    }

    /** 権限画面が閉じたあと、許可済みの権限を Dart 側へ返す */
    private fun deliverGranted() {
        val r = pendingRequest ?: return
        pendingRequest = null
        scope.launch {
            try {
                r.success(grantedKeys(HealthConnectClient.getOrCreate(this@MainActivity)))
            } catch (e: Exception) {
                r.error("health_error", e.message ?: e.toString(), null)
            }
        }
    }

    private suspend fun grantedKeys(client: HealthConnectClient): List<String> {
        val granted = client.permissionController.getGrantedPermissions()
        return permissionKeys.filterValues { it in granted }.keys.toList()
    }

    private fun range(call: MethodCall, startKey: String = "start", endKey: String = "end"): TimeRangeFilter {
        val s = (call.argument<Number>(startKey) ?: 0).toLong()
        val e = (call.argument<Number>(endKey) ?: System.currentTimeMillis()).toLong()
        return TimeRangeFilter.between(Instant.ofEpochMilli(s), Instant.ofEpochMilli(e))
    }

    /** 権限が無い種類は空リストにする（他の種類は読めるように） */
    private suspend fun <T : Record> readAll(
        client: HealthConnectClient,
        type: KClass<T>,
        filter: TimeRangeFilter,
        origins: Set<DataOrigin> = emptySet(),
    ): List<T> {
        val out = mutableListOf<T>()
        var token: String? = null
        try {
            do {
                val resp = client.readRecords(
                    ReadRecordsRequest(recordType = type, timeRangeFilter = filter, dataOriginFilter = origins, pageToken = token)
                )
                out.addAll(resp.records)
                token = resp.pageToken
            } while (!token.isNullOrEmpty())
        } catch (e: SecurityException) {
            return emptyList()
        }
        return out
    }

    private suspend fun readBody(client: HealthConnectClient, call: MethodCall): Map<String, Any> {
        val f = range(call)
        return mapOf(
            "weight" to readAll(client, WeightRecord::class, f).map {
                mapOf("time" to it.time.toEpochMilli(), "value" to it.weight.inKilograms, "origin" to it.metadata.dataOrigin.packageName)
            },
            "bodyFat" to readAll(client, BodyFatRecord::class, f).map {
                mapOf("time" to it.time.toEpochMilli(), "value" to it.percentage.value, "origin" to it.metadata.dataOrigin.packageName)
            },
            "leanMass" to readAll(client, LeanBodyMassRecord::class, f).map {
                mapOf("time" to it.time.toEpochMilli(), "value" to it.mass.inKilograms, "origin" to it.metadata.dataOrigin.packageName)
            },
            "height" to readAll(client, HeightRecord::class, f).map {
                mapOf("time" to it.time.toEpochMilli(), "value" to it.height.inMeters, "origin" to it.metadata.dataOrigin.packageName)
            },
        )
    }

    private suspend fun readSessions(client: HealthConnectClient, call: MethodCall): List<Map<String, Any?>> {
        val f = range(call)
        val sessions = readAll(client, ExerciseSessionRecord::class, f)
        // 履歴画面用：運動ごとの距離・活動カロリー（同じアプリが記録した、時間の重なる分を合計）
        val withMetrics = call.argument<Boolean>("metrics") == true && sessions.isNotEmpty()
        val origins = sessions.map { it.metadata.dataOrigin }.toSet()
        val distances = if (withMetrics) readAll(client, DistanceRecord::class, f, origins) else emptyList()
        val calories = if (withMetrics) readAll(client, ActiveCaloriesBurnedRecord::class, f, origins) else emptyList()
        return sessions.map { s ->
            val pkg = s.metadata.dataOrigin.packageName
            fun share(start: Instant, end: Instant): Double {
                val total = end.toEpochMilli() - start.toEpochMilli()
                val from = maxOf(start.toEpochMilli(), s.startTime.toEpochMilli())
                val to = minOf(end.toEpochMilli(), s.endTime.toEpochMilli())
                if (to <= from) return 0.0
                return if (total <= 0) 1.0 else (to - from).toDouble() / total
            }
            val dist = distances.filter { it.metadata.dataOrigin.packageName == pkg }
                .sumOf { it.distance.inMeters * share(it.startTime, it.endTime) }
            val kcal = calories.filter { it.metadata.dataOrigin.packageName == pkg }
                .sumOf { it.energy.inKilocalories * share(it.startTime, it.endTime) }
            mapOf(
                "start" to s.startTime.toEpochMilli(),
                "end" to s.endTime.toEpochMilli(),
                "type" to exerciseKey(s.exerciseType),
                "title" to s.title,
                "origin" to pkg,
                "distanceM" to (if (withMetrics && dist > 0) dist else null),
                "kcal" to (if (withMetrics && kcal > 0) kcal else null),
            )
        }
    }

    /** 区間ごとの歩数・活動カロリー合計（ヘルスコネクト側で重複が除かれる）。権限が無ければ null */
    private suspend fun aggregate(client: HealthConnectClient, call: MethodCall): List<Map<String, Any?>> {
        val granted = client.permissionController.getGrantedPermissions()
        val canSteps = permissionKeys["steps"] in granted
        val canKcal = permissionKeys["activeKcal"] in granted
        val ranges = call.argument<List<List<Number>>>("ranges") ?: emptyList()
        return ranges.map { r ->
            val f = TimeRangeFilter.between(Instant.ofEpochMilli(r[0].toLong()), Instant.ofEpochMilli(r[1].toLong()))
            val steps = if (canSteps) {
                client.aggregate(AggregateRequest(metrics = setOf(StepsRecord.COUNT_TOTAL), timeRangeFilter = f))[StepsRecord.COUNT_TOTAL]
            } else null
            val kcal = if (canKcal) {
                client.aggregate(
                    AggregateRequest(metrics = setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL), timeRangeFilter = f)
                )[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories
            } else null
            mapOf("steps" to steps, "kcal" to kcal)
        }
    }

    private fun exerciseKey(type: Int): String = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "running"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> "walking"
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> "hiking"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "biking"
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL,
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> "swimming"
        ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING,
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING -> "strength"
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> "hiit"
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "yoga"
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING,
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWBOARDING -> "snow"
        else -> "other"
    }

    companion object {
        private const val CHANNEL = "meal_log/health"
        private const val REQUEST_CODE = 7301
        private const val CRASH_FILE = "last_crash.txt"
    }
}
