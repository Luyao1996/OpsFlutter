package com.netbarops.netbar_ops_flutter

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {

    private val channelName = "com.netbarops/exit_reasons"

    // Max bytes of tombstone/ANR trace to read back to Dart.
    private val maxTraceBytes = 16 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getExitReasons" -> result.success(getExitReasons())
                    else -> result.notImplemented()
                }
            }
    }

    private fun getExitReasons(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return out
        }
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            // most recent first; cap at 8 records
            val reasons = am.getHistoricalProcessExitReasons(packageName, 0, 8)
            for (info in reasons) {
                val map = HashMap<String, Any?>()
                map["timestamp"] = info.timestamp
                map["reason"] = info.reason
                map["reasonName"] = reasonName(info.reason)
                map["status"] = info.status
                map["importance"] = info.importance
                map["pid"] = info.pid
                map["processName"] = info.processName
                map["description"] = info.description ?: ""
                map["trace"] = readTrace(info)
                out.add(map)
            }
        } catch (e: Exception) {
            // swallow; reporting must never crash the app
        }
        return out
    }

    private fun readTrace(info: ApplicationExitInfo): String {
        // Only CRASH_NATIVE / ANR carry a trace input stream.
        val reason = info.reason
        if (reason != ApplicationExitInfo.REASON_CRASH_NATIVE &&
            reason != ApplicationExitInfo.REASON_ANR
        ) {
            return ""
        }
        return try {
            val stream = info.traceInputStream ?: return ""
            val reader = BufferedReader(InputStreamReader(stream))
            val sb = StringBuilder()
            val buf = CharArray(4096)
            while (sb.length < maxTraceBytes) {
                val n = reader.read(buf)
                if (n < 0) break
                sb.append(buf, 0, n)
            }
            reader.close()
            if (sb.length >= maxTraceBytes) {
                sb.append("\n...(trace truncated at ").append(maxTraceBytes).append(" bytes)")
            }
            sb.toString()
        } catch (e: Exception) {
            ""
        }
    }

    private fun reasonName(reason: Int): String {
        return when (reason) {
            ApplicationExitInfo.REASON_UNKNOWN -> "UNKNOWN"
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
            ApplicationExitInfo.REASON_CRASH -> "CRASH"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            else -> "REASON_$reason"
        }
    }
}
