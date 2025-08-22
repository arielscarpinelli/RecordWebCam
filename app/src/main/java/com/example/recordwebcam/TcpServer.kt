package com.example.recordwebcam

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class TcpServer(
    private val onStartRecording: () -> Unit,
    private val onStopRecording: () -> Unit,
    private val onCodecSelected: (String) -> Unit
) {
    private var serverSocket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()
    private val clients = ConcurrentHashMap<Socket, ClientHandler>()
    @Volatile
    private var isRunning = false

    fun start() {
        if (isRunning) return
        isRunning = true
        executor.execute {
            try {
                serverSocket = ServerSocket(4747)
                while (isRunning) {
                    val clientSocket = serverSocket!!.accept()
                    Log.d(TAG, "Client connected: ${clientSocket.inetAddress.hostAddress}")
                    val clientHandler = ClientHandler(clientSocket)
                    clients[clientSocket] = clientHandler
                    executor.execute(clientHandler)
                }
            } catch (e: IOException) {
                if (isRunning) {
                    Log.e(TAG, "Error in server loop", e)
                }
            }
        }
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
        } catch (e: IOException) {
            Log.e(TAG, "Error closing server socket", e)
        }
        clients.keys.forEach {
            try {
                it.close()
            } catch (e: IOException) {
                // Ignore
            }
        }
        clients.clear()
        executor.shutdown()
    }

    fun broadcastFrame(data: ByteBuffer, info: MediaCodec.BufferInfo) {
        if (clients.isEmpty()) return

        // Packet format: 8-byte timestamp (ms) + 4-byte length + data
        val packetSize = 8 + 4 + info.size
        val packet = ByteBuffer.allocate(packetSize)
        packet.putLong(info.presentationTimeUs / 1000) // convert to ms
        packet.putInt(info.size)
        packet.put(data)
        packet.flip()

        val packetArray = packet.array()
        clients.values.forEach { client ->
            if (client.wantsVideo) {
                client.send(packetArray)
            }
        }
    }

    inner class ClientHandler(private val socket: Socket) : Runnable {
        @Volatile
        var wantsVideo = false
        private val inputStream = socket.getInputStream()
        private val outputStream = socket.getOutputStream()

        override fun run() {
            val buffer = ByteArray(1024)
            try {
                while (socket.isConnected && !socket.isClosed) {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead == -1) break // Connection closed

                    val request = String(buffer, 0, bytesRead, Charsets.US_ASCII)
                    Log.d(TAG, "Received: $request")

                    if (request.contains("video")) {
                        if (request.contains("/avc")) {
                            onCodecSelected(MediaFormat.MIMETYPE_VIDEO_AVC)
                        } else if (request.contains("/hvec")) {
                            onCodecSelected(MediaFormat.MIMETYPE_VIDEO_HEVC)
                        }
                        wantsVideo = true
                    } else if (request.contains("start")) {
                        onStartRecording()
                        outputStream.write("200 OK\r\n\r\n".toByteArray(Charsets.US_ASCII))
                    } else if (request.contains("stop")) {
                        onStopRecording()
                        outputStream.write("200 OK\r\n\r\n".toByteArray(Charsets.US_ASCII))
                    }
                }
            } catch (e: IOException) {
                // This is expected when the socket is closed by another thread
            } finally {
                close()
            }
        }

        fun send(data: ByteArray) {
            if (socket.isClosed) return
            try {
                outputStream.write(data)
                outputStream.flush()
            } catch (e: IOException) {
                Log.e(TAG, "Failed to send data to client", e)
                close()
            }
        }

        private fun close() {
            clients.remove(socket)
            try {
                if (!socket.isClosed) {
                    socket.close()
                }
            } catch (e: IOException) {
                // Ignore
            }
            Log.d(TAG, "Client disconnected: ${socket.inetAddress.hostAddress}")
        }
    }

    companion object {
        private const val TAG = "TcpServer"
    }
}
