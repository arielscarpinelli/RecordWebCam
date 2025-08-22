package com.example.recordwebcam

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import androidx.camera.core.ImageProxy
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue

class VideoEncoder(
    private val width: Int,
    private val height: Int,
    private val mimeType: String,
    private val onEncodedData: (ByteBuffer, MediaCodec.BufferInfo) -> Unit
) {

    private lateinit var mediaCodec: MediaCodec
    private var mediaMuxer: MediaMuxer? = null
    private var videoTrackIndex: Int = -1
    private var isRecording = false
    private val frameQueue = ConcurrentLinkedQueue<ImageProxy>()
    private var outputFile: File? = null

    fun startRecording(outputFile: File) {
        this.outputFile = outputFile
        try {
            mediaMuxer = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            isRecording = true
        } catch (e: Exception) {
            Log.e(TAG, "MediaMuxer creation failed", e)
        }
    }

    fun stopRecording(onFinished: (File) -> Unit) {
        if (isRecording) {
            isRecording = false
            mediaMuxer?.stop()
            mediaMuxer?.release()
            mediaMuxer = null
            outputFile?.let { onFinished(it) }
            outputFile = null
        }
    }

    fun startEncoding() {
        val mediaFormat = MediaFormat.createVideoFormat(mimeType, width, height).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000) // 6 Mbps
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1) // 1 second
        }

        mediaCodec = MediaCodec.createEncoderByType(mimeType)
        mediaCodec.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                val imageProxy = frameQueue.poll() ?: return

                val inputBuffer = codec.getInputBuffer(index)
                if (inputBuffer != null) {
                    val i420Bytes = imageProxyToI420(imageProxy)
                    inputBuffer.clear()
                    inputBuffer.put(i420Bytes)
                    codec.queueInputBuffer(index, 0, i420Bytes.size, imageProxy.timestamp, 0)
                }
                imageProxy.close()
            }

            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                val outputBuffer = codec.getOutputBuffer(index)
                if (outputBuffer != null) {
                    onEncodedData(outputBuffer, info)

                    if (isRecording && videoTrackIndex != -1) {
                        mediaMuxer?.writeSampleData(videoTrackIndex, outputBuffer, info)
                    }
                }
                codec.releaseOutputBuffer(index, false)
            }

            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                Log.e(TAG, "MediaCodec error", e)
            }

            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                if (isRecording) {
                    videoTrackIndex = mediaMuxer?.addTrack(format) ?: -1
                    mediaMuxer?.start()
                }
            }
        })
        mediaCodec.configure(mediaFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        mediaCodec.start()
    }

    fun stopEncoding() {
        mediaCodec.stop()
        mediaCodec.release()
    }

    private fun imageProxyToI420(image: ImageProxy): ByteArray {
        val width = image.width
        val height = image.height
        val yBuffer = image.planes[0].buffer
        val uBuffer = image.planes[1].buffer
        val vBuffer = image.planes[2].buffer

        val yRowStride = image.planes[0].rowStride
        val uRowStride = image.planes[1].rowStride
        val vRowStride = image.planes[2].rowStride

        val i420 = ByteArray(width * height * 3 / 2)
        var i420Pos = 0

        // Copy Y plane
        if (yRowStride == width) {
            yBuffer.get(i420, i420Pos, width * height)
            i420Pos += width * height
        } else {
            for (row in 0 until height) {
                yBuffer.position(row * yRowStride)
                yBuffer.get(i420, i420Pos, width)
                i420Pos += width
            }
        }

        // Copy U plane
        val uWidth = width / 2
        val uHeight = height / 2
        if (uRowStride == uWidth) {
            uBuffer.get(i420, i420Pos, uWidth * uHeight)
            i420Pos += uWidth * uHeight
        } else {
            for (row in 0 until uHeight) {
                uBuffer.position(row * uRowStride)
                uBuffer.get(i420, i420Pos, uWidth)
                i420Pos += uWidth
            }
        }

        // Copy V plane
        val vWidth = width / 2
        val vHeight = height / 2
        if (vRowStride == vWidth) {
            vBuffer.get(i420, i420Pos, vWidth * vHeight)
        } else {
            for (row in 0 until vHeight) {
                vBuffer.position(row * vRowStride)
                vBuffer.get(i420, i420Pos, vWidth)
                i420Pos += vWidth
            }
        }

        return i420
    }

    fun encodeFrame(imageProxy: ImageProxy) {
        if (imageProxy.format != android.graphics.ImageFormat.YUV_420_888) {
            imageProxy.close()
            return
        }
        frameQueue.offer(imageProxy)
    }

    companion object {
        private const val TAG = "VideoEncoder"
    }
}
