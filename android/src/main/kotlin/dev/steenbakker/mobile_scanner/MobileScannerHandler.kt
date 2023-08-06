package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.net.Uri
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import dev.steenbakker.mobile_scanner.objects.DetectionSpeed
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.view.TextureRegistry
import java.io.File
import android.util.Log

class MobileScannerHandler(
    private val activity: Activity,
    private val barcodeHandler: BarcodeHandler,
    binaryMessenger: BinaryMessenger,
    private val permissions: MobileScannerPermissions,
    private val addPermissionListener: (RequestPermissionsResultListener) -> Unit,
    textureRegistry: TextureRegistry): MethodChannel.MethodCallHandler {

    private val analyzerCallback: AnalyzerCallback = { barcodes: List<Map<String, Any?>>?->
    val barcodeMap: MutableList<Map<String, Any?>> = mutableListOf()
       barcodeHandler.publishEvent(mapOf(
                "name" to "barcode",
                "data" to barcodeMap
            ))
        analyzerResult?.success(true)
    }

    private var analyzerResult: MethodChannel.Result? = null

    private val callback: MobileScannerCallback = {  image: ByteArray?, width: Int?, height: Int? ->
    val barcodeMap: MutableList<Map<String, Any?>> = mutableListOf()
        if (image != null) {
            barcodeHandler.publishEvent(mapOf(
                "name" to "barcode",
                "data" to barcodeMap,
                "image" to image,
                "width" to width!!.toDouble(),
                "height" to height!!.toDouble()
            ))
        } else {
            barcodeHandler.publishEvent(mapOf(
                "name" to "barcode",
                "data" to barcodeMap
            ))
        }
    }

    private val errorCallback: MobileScannerErrorCallback = {error: String ->
        barcodeHandler.publishEvent(mapOf(
            "name" to "error",
            "data" to error,
        ))
    }

    private var methodChannel: MethodChannel? = null

    private var mobileScanner: MobileScanner? = null

    private val torchStateCallback: TorchStateCallback = {state: Int ->
        barcodeHandler.publishEvent(mapOf("name" to "torchState", "data" to state))
    }

    private val zoomScaleStateCallback: ZoomScaleStateCallback = {zoomScale: Double ->
        barcodeHandler.publishEvent(mapOf("name" to "zoomScaleState", "data" to zoomScale))
    }

    init {
        methodChannel = MethodChannel(binaryMessenger,
            "dev.steenbakker.mobile_scanner/scanner/method")
        methodChannel!!.setMethodCallHandler(this)
        mobileScanner = MobileScanner(activity, textureRegistry, callback, errorCallback)
    }

    fun dispose(activityPluginBinding: ActivityPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        mobileScanner = null

        val listener: RequestPermissionsResultListener? = permissions.getPermissionListener()

        if(listener != null) {
            activityPluginBinding.removeRequestPermissionsResultListener(listener)
        }

    }

    @ExperimentalGetImage
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (mobileScanner == null) {
            result.error("MobileScanner", "Called ${call.method} before initializing.", null)
            return
        }
        when (call.method) {
            "state" -> result.success(permissions.hasCameraPermission(activity))
            "request" -> permissions.requestPermission(
                activity,
                addPermissionListener,
                object: MobileScannerPermissions.ResultCallback {
                    override fun onResult(errorCode: String?, errorDescription: String?) {
                        when(errorCode) {
                            null -> result.success(true)
                            MobileScannerPermissions.CAMERA_ACCESS_DENIED -> result.success(false)
                            else -> result.error(errorCode, errorDescription, null)
                        }
                    }
                })
            "start" -> start(call, result)
            "stop" -> stop(result)
            "analyzeImage" -> analyzeImage(call, result)
            "updateScanWindow" -> updateScanWindow(call)
            else -> result.notImplemented()
        }
    }

    @ExperimentalGetImage
    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val torch: Boolean = call.argument<Boolean>("torch") ?: false
        val facing: Int = call.argument<Int>("facing") ?: 0
        val formats: List<Int>? = call.argument<List<Int>>("formats")
        val returnImage: Boolean = call.argument<Boolean>("returnImage") ?: false
        val speed: Int = call.argument<Int>("speed") ?: 1
        val timeout: Int = call.argument<Int>("timeout") ?: 250

        val position =
            if (facing == 0) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA

        val detectionSpeed: DetectionSpeed = DetectionSpeed.values().first { it.intValue == speed}

        try {
            mobileScanner!!.start(returnImage, position, torch, detectionSpeed, torchStateCallback, zoomScaleStateCallback, mobileScannerStartedCallback = {
                result.success(mapOf(
                    "textureId" to it.id,
                    "size" to mapOf("width" to it.width, "height" to it.height),
                    "torchable" to it.hasFlashUnit
                ))
            },
                timeout.toLong())

        } catch (e: AlreadyStarted) {
            result.error(
                "MobileScanner",
                "Called start() while already started",
                null
            )
        } catch (e: NoCamera) {
            result.error(
                "MobileScanner",
                "No camera found or failed to open camera!",
                null
            )
        } catch (e: TorchError) {
            result.error(
                "MobileScanner",
                "Error occurred when setting torch!",
                null
            )
        } catch (e: CameraError) {
            result.error(
                "MobileScanner",
                "Error occurred when setting up camera!",
                null
            )
        } catch (e: Exception) {
            result.error(
                "MobileScanner",
                "Unknown error occurred..",
                null
            )
        }
    }

    private fun stop(result: MethodChannel.Result) {
        try {
            mobileScanner!!.stop()
            result.success(null)
        } catch (e: AlreadyStopped) {
            result.success(null)
        }
    }

    private fun analyzeImage(call: MethodCall, result: MethodChannel.Result) {
    }

    private fun updateScanWindow(call: MethodCall) {
        mobileScanner!!.scanWindow = call.argument<List<Float>?>("rect")
    }
}
