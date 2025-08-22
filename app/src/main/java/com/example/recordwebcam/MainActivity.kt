package com.example.recordwebcam

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Button
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.preference.PreferenceManager
import com.example.recordwebcam.utils.getDeviceZoomRatios
import com.example.recordwebcam.utils.getIpAddress
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var cameraHandler: CameraHandler
    private lateinit var videoEncoder: VideoEncoder
    private lateinit var tcpServer: TcpServer

    private lateinit var previewView: PreviewView
    private lateinit var recordButton: ImageButton
    private lateinit var ipAddressTextView: TextView
    private lateinit var zoomButton: Button
    private lateinit var flipCameraButton: ImageButton
    private lateinit var settingsButton: ImageButton

    private var isRecording = false
    private var isStreaming = false
    private var currentCodec = MediaFormat.MIMETYPE_VIDEO_AVC

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySettings()
        setContentView(R.layout.activity_main)

        previewView = findViewById(R.id.previewView)
        recordButton = findViewById(R.id.recordButton)
        ipAddressTextView = findViewById(R.id.ipAddressTextView)
        zoomButton = findViewById(R.id.zoomButton)
        flipCameraButton = findViewById(R.id.flipCameraButton)
        settingsButton = findViewById(R.id.settingsButton)

        if (allPermissionsGranted()) {
            startApp()
        } else {
            ActivityCompat.requestPermissions(
                this, REQUIRED_PERMISSIONS, REQUEST_CODE_PERMISSIONS
            )
        }

        recordButton.setOnClickListener {
            toggleRecording()
        }

        zoomButton.setOnClickListener {
            toggleZoom()
        }

        flipCameraButton.setOnClickListener {
            cameraHandler.switchCamera()
        }

        settingsButton.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }
    }

    private fun startApp() {
        // Initialize components
        cameraHandler = CameraHandler(
            this,
            this,
            previewView.surfaceProvider,
            onFrameAvailable = { imageProxy ->
                // Pass the frame to the encoder
                if (::videoEncoder.isInitialized) {
                    videoEncoder.encodeFrame(imageProxy)
                }
            },
            onCameraInitialized = { width, height ->
                runOnUiThread {
                    setupVideoEncoder(width, height)
                }
            }
        )

        tcpServer = TcpServer(
            onStartRecording = { runOnUiThread { toggleRecording() } },
            onStopRecording = { runOnUiThread { toggleRecording() } },
            onCodecSelected = { mimeType ->
                runOnUiThread {
                    if (isRecording || isStreaming) {
                        Toast.makeText(this, "Cannot change codec while recording or streaming", Toast.LENGTH_SHORT).show()
                    } else {
                        currentCodec = mimeType
                        // Re-setup the encoder with the new codec, dimensions will be retrieved again
                        cameraHandler.startCamera()
                        Toast.makeText(this, "Codec set to ${mimeType.substringAfter('/')}", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        )

        // Start components
        cameraHandler.startCamera()
        tcpServer.start()

        // Display IP address
        ipAddressTextView.text = "IP: ${getIpAddress()}"
    }

    private fun setupVideoEncoder(width: Int, height: Int) {
        if (::videoEncoder.isInitialized) {
            videoEncoder.stopEncoding()
        }
        videoEncoder = VideoEncoder(
            width,
            height,
            currentCodec
        ) { buffer, info ->
            // Pass the encoded data to the server
            isStreaming = true
            tcpServer.broadcastFrame(buffer, info)
        }
        videoEncoder.startEncoding()
        updateUi()
    }

    private fun updateUi() {
        updateZoomUi()
        flipCameraButton.isEnabled = cameraHandler.hasFrontCamera() && cameraHandler.hasBackCamera()
    }

    private fun toggleZoom() {
        val camera = cameraHandler.camera ?: return
        val zoomState = camera.cameraInfo.zoomState.value ?: return
        val currentZoomRatio = zoomState.zoomRatio
        val maxZoom = zoomState.maxZoomRatio

        val zoomLevels = getDeviceZoomRatios(camera, this)
        var nextZoomRatio = zoomLevels.firstOrNull { it > currentZoomRatio }

        if (nextZoomRatio == null || nextZoomRatio > maxZoom) {
            nextZoomRatio = zoomLevels.getOrElse(0) { 1.0f }
        }

        cameraHandler.setZoomRatio(nextZoomRatio)
        updateZoomUi()
    }

    private fun updateZoomUi() {
        val currentZoomRatio = cameraHandler.camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1.0f
        zoomButton.text = String.format("%.1fx", currentZoomRatio)
    }

    private fun toggleRecording() {
        isRecording = !isRecording
        if (isRecording) {
            val videoFile = createVideoFile()
            videoEncoder.startRecording(videoFile)
            recordButton.setImageResource(R.drawable.ic_stop)
        } else {
            videoEncoder.stopRecording { file ->
                // Check settings to see if we should save to gallery
                val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
                if (sharedPreferences.getBoolean("save_to_camera_roll", true)) {
                    saveVideoToGallery(file)
                }
            }
            recordButton.setImageResource(R.drawable.ic_record)
        }
    }

    private fun allPermissionsGranted() = REQUIRED_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(baseContext, it) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            if (allPermissionsGranted()) {
                startApp()
            } else {
                Toast.makeText(this, "Permissions not granted by the user.", Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if(::cameraHandler.isInitialized) cameraHandler.stopCamera()
        if(::videoEncoder.isInitialized) videoEncoder.stopEncoding()
        if(::tcpServer.isInitialized) tcpServer.stop()
    }

    private fun createVideoFile(): File {
        val sdf = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US)
        val date = sdf.format(Date())
        val file = File(filesDir, "video_$date.mp4")
        return file
    }

    private fun saveVideoToGallery(videoFile: File) {
        val contentValues = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, videoFile.name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/RecordWebCam")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }

        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)

        uri?.let {
            try {
                resolver.openOutputStream(it).use { outputStream ->
                    videoFile.inputStream().use { inputStream ->
                        inputStream.copyTo(outputStream!!)
                    }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    contentValues.clear()
                    contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                    resolver.update(it, contentValues, null, null)
                }
                Toast.makeText(this, "Video saved to gallery", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Error saving video: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun applySettings() {
        val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(this)
        val forceLandscape = sharedPreferences.getBoolean("force_landscape_start", false)
        if (forceLandscape) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
    }

    companion object {
        private const val REQUEST_CODE_PERMISSIONS = 10
        private val REQUIRED_PERMISSIONS = if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            arrayOf(
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.ACCESS_WIFI_STATE,
                Manifest.permission.INTERNET,
                Manifest.permission.ACCESS_NETWORK_STATE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            )
        } else {
            arrayOf(
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.ACCESS_WIFI_STATE,
                Manifest.permission.INTERNET,
                Manifest.permission.ACCESS_NETWORK_STATE
            )
        }
    }
}
