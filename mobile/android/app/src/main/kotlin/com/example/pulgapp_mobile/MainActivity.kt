package com.example.pulgapp_mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val preferences = getSharedPreferences("pulgapp", MODE_PRIVATE)
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/preferences")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAll" -> result.success(preferences.all.mapValues { it.value as String })
                    "setString" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null || value == null) result.error("invalid_arguments", "Expected key and value.", null)
                        else {
                            preferences.edit().putString(key, value).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "pulgapp/wakelock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); result.success(null) }
                    "disable" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }
}
