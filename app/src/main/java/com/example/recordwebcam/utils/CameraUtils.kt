package com.example.recordwebcam.utils

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import kotlin.math.round

fun getDeviceZoomRatios(camera: Camera, context: Context): List<Float> {
    val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    val cameraId = Camera2CameraInfo.from(camera.cameraInfo).cameraId
    val characteristics = cameraManager.getCameraCharacteristics(cameraId)

    // Check if it's a logical multi-camera
    val physicalCameraIds = characteristics.physicalCameraIds
    if (physicalCameraIds.isEmpty()) {
        return listOf(1.0f, 2.0f, 4.0f) // Fallback for single-camera devices
    }

    val focalLengths = mutableMapOf<String, Float>()
    for (id in physicalCameraIds) {
        val physicalChars = cameraManager.getCameraCharacteristics(id)
        val lengths = physicalChars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
        if (lengths != null && lengths.isNotEmpty()) {
            focalLengths[id] = lengths[0]
        }
    }

    if (focalLengths.isEmpty()) {
        return listOf(1.0f, 2.0f, 4.0f)
    }

    // Find the main lens (widest angle, so smallest focal length) to be our 1x reference
    // This is a simplification; a more robust method might be needed for complex camera systems.
    val mainLensFocalLength = focalLengths.values.minOrNull() ?: return listOf(1.0f)

    // Calculate zoom ratios relative to the main lens
    val opticalRatios = focalLengths.values
        .map { it / mainLensFocalLength }
        .distinct()
        .sorted()

    // Add intermediate digital zoom steps
    val finalRatios = mutableListOf<Float>()
    if (opticalRatios.isNotEmpty()) {
        finalRatios.add(opticalRatios[0])
        for (i in 0 until opticalRatios.size - 1) {
            val current = opticalRatios[i]
            val next = opticalRatios[i+1]
            // If the jump is more than 2.5x, add an intermediate step
            if (next / current > 2.5f) {
                finalRatios.add(current * 2.0f)
            }
            finalRatios.add(next)
        }
    }

    // Round to one decimal place for cleaner UI and remove duplicates
    return finalRatios.map { round(it * 10) / 10f }.distinct().sorted()
}
