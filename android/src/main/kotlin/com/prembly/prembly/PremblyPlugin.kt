package com.prembly.prembly

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Device signals for Prembly Transaction Monitoring. Hosted workflows run in a Flutter WebView and
 * need nothing from this class.
 *
 * Every result is a JSON string (the same shape prembly-tm-native returns), so the Dart side parses
 * one format on both platforms.
 */
class PremblyPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private lateinit var collector: SignalCollector

  // The checks touch the file system and system services, so keep them off the main thread.
  private var worker: ExecutorService? = null
  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    collector = SignalCollector(context)
    worker = Executors.newSingleThreadExecutor()
    channel = MethodChannel(binding.binaryMessenger, CHANNEL)
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getAppInfo" -> result.success(collector.appInfo().toString())
      "getDeviceId" -> run(result, "device_id_failed") { DeviceIdStore.deviceId(context) }
      "collectSignals" -> {
        val includeLocation = call.argument<Boolean>("includeLocation") ?: false
        run(result, "collect_failed") { collector.collect(includeLocation).toString() }
      }
      else -> result.notImplemented()
    }
  }

  private fun run(result: Result, errorCode: String, work: () -> String) {
    val executor = worker
    if (executor == null) {
      result.error(errorCode, "The plugin is detached.", null)
      return
    }
    executor.execute {
      try {
        val value = work()
        main.post { result.success(value) }
      } catch (error: Throwable) {
        main.post { result.error(errorCode, error.message, null) }
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    worker?.shutdown()
    worker = null
  }

  companion object {
    private const val CHANNEL = "prembly/tm"
  }
}
