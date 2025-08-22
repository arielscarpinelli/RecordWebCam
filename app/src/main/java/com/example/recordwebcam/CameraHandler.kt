package com.example.recordwebcam

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log
import android.util.Size
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraHandler(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val preview: Preview.SurfaceProvider,
    private val onFrameAvailable: (ImageProxy) -> Unit,
    private val onCameraInitialized: (Int, Int) -> Unit
) {

    private var cameraProvider: ProcessCameraProvider? = null
    var camera: Camera? = null
        private set
    private lateinit var cameraExecutor: ExecutorService
    var lensFacing = CameraSelector.LENS_FACING_BACK

    fun startCamera() {
        if (::cameraExecutor.isInitialized && !cameraExecutor.isShutdown) {
            cameraExecutor.shutdown()
        }
        cameraExecutor = Executors.newSingleThreadExecutor()
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            bindCameraUseCases()
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: throw IllegalStateException("Camera initialization failed.")

        val cameraSelector = CameraSelector.Builder()
            .requireLensFacing(lensFacing)
            .build()

        // Must unbind the use-cases before rebinding them.
        cameraProvider.unbindAll()

        val camera = cameraProvider.bindToLifecycle(lifecycleOwner, cameraSelector)
        val supportedResolutions = getSupportedResolutions(camera)
        val targetResolution = selectBestResolution(supportedResolutions)

        Log.d(TAG, "Selected resolution: $targetResolution")

        val previewUseCase = Preview.Builder()
            .setTargetResolution(targetResolution)
            .build()
            .also {
                it.setSurfaceProvider(preview)
            }

        val imageAnalysisUseCase = ImageAnalysis.Builder()
            .setTargetResolution(targetResolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        imageAnalysisUseCase.setAnalyzer(cameraExecutor) { imageProxy ->
            onFrameAvailable(imageProxy)
            // The ImageProxy is now closed by the consumer (VideoEncoder)
        }

        try {
            cameraProvider.unbindAll()
            this.camera = cameraProvider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                previewUseCase,
                imageAnalysisUseCase
            )
            onCameraInitialized(targetResolution.width, targetResolution.height)
        } catch (exc: Exception) {
            Log.e(TAG, "Use case binding failed", exc)
        }
    }

    private fun getSupportedResolutions(camera: Camera): List<Size> {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = Camera2CameraInfo.from(camera.cameraInfo).cameraId
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        return map?.getOutputSizes(ImageAnalysis::class.java)?.toList() ?: emptyList()
    }

    private fun selectBestResolution(supportedResolutions: List<Size>): Size {
        val resolution4k = Size(3840, 2160)
        val resolution1080p = Size(1920, 1080)

        if (supportedResolutions.contains(resolution4k)) {
            return resolution4k
        }
        if (supportedResolutions.contains(resolution1080p)) {
            return resolution1080p
        }
        return supportedResolutions.maxByOrNull { it.width * it.height } ?: resolution1080p
    }

    fun switchCamera() {
        lensFacing = if (CameraSelector.LENS_FACING_FRONT == lensFacing) {
            CameraSelector.LENS_FACING_BACK
        } else {
            CameraSelector.LENS_FACING_FRONT
        }
        startCamera()
    }

    fun hasFrontCamera(): Boolean {
        return cameraProvider?.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) ?: false
    }

    fun hasBackCamera(): Boolean {
        return cameraProvider?.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) ?: false
    }

    fun setZoomRatio(zoomRatio: Float) {
        camera?.cameraControl?.setZoomRatio(zoomRatio)
    }

    fun stopCamera() {
        cameraProvider?.unbindAll()
        if (::cameraExecutor.isInitialized) {
            cameraExecutor.shutdown()
        }
    }

    companion object {
        private const val TAG = "CameraHandler"
    }
}
