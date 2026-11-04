package com.example.sut_yem_clean

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private val CHANNEL = "classic_bluetooth"
    private val EVENT_CHANNEL = "classic_bluetooth_events"
    private val TAG = "ClassicBluetooth"

    private var btAdapter: BluetoothAdapter? = null
    private var btSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var inputStream: InputStream? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isReading = false
    private var connectThread: Thread? = null
    private var readThread: Thread? = null

    // SPP UUID for serial communication
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            btAdapter = BluetoothAdapter.getDefaultAdapter()
            Log.d(TAG, "Bluetooth adapter initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth adapter error: ${e.message}")
        }

        // MethodChannel for commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPairedDevices" -> getPairedDevices(result)
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address.isNullOrEmpty()) {
                        result.error("INVALID_ADDRESS", "MAC address is null or empty", null)
                    } else {
                        connect(address, result)
                    }
                }
                "disconnect" -> {
                    disconnect()
                    result.success(true)
                }
                "sendData" -> {
                    val data = call.argument<String>("data")
                    if (data != null) {
                        sendData(data, result)
                    } else {
                        result.error("INVALID_DATA", "Data is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Termal fiş yazıcısı — terazi bağlantısından bağımsız (bkz. TermalYazici.kt)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "termal_yazici")
            .setMethodCallHandler(TermalYazici(this))

        // EventChannel for data streaming
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d(TAG, "EventChannel listener attached")
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d(TAG, "EventChannel listener cancelled")
                    eventSink = null
                }
            }
        )
    }

    private fun getPairedDevices(result: MethodChannel.Result) {
        try {
            if (btAdapter == null) {
                result.error("NO_BLUETOOTH", "Bluetooth not available", null)
                return
            }

            val pairedDevices: Set<BluetoothDevice> = btAdapter!!.bondedDevices
            val devicesList = mutableListOf<Map<String, String>>()

            for (device in pairedDevices) {
                devicesList.add(mapOf(
                    "name" to (device.name ?: "Unknown Device"),
                    "address" to device.address
                ))
            }

            Log.d(TAG, "Found ${devicesList.size} paired devices")
            result.success(devicesList)
        } catch (e: Exception) {
            Log.e(TAG, "getPairedDevices error: ${e.message}")
            result.error("GET_DEVICES_ERROR", e.message, null)
        }
    }

    private fun connect(address: String, result: MethodChannel.Result) {
    // Cancel previous connection attempts
    connectThread?.interrupt()

    connectThread = thread {
        try {
            Log.d(TAG, "Attempting to connect to: $address")

            // Get the remote device
            val device = btAdapter!!.getRemoteDevice(address)
            Log.d(TAG, "Device found: ${device.name}")

            // Create socket
            btSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)

            // Cancel discovery to speed up connection
            btAdapter!!.cancelDiscovery()

            // Connect with timeout
            btSocket!!.connect()
            Log.d(TAG, "Connected successfully")

            // Get streams
            outputStream = btSocket!!.outputStream
            inputStream = btSocket!!.inputStream

            // Start reading data
            startReading()

            // Return success on main thread
            activity.runOnUiThread {
                Log.d(TAG, "Success! Returning to Flutter with result")
                result.success(true)
            }

        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception: ${e.message}")
            activity.runOnUiThread {
                result.error("SECURITY_ERROR", "Bluetooth permission denied", null)
            }
        } catch (e: IOException) {
            Log.e(TAG, "Connection IO error: ${e.message}")
            // Try fallback method for some devices
            tryFallbackConnection(address, result)
        } catch (e: Exception) {
            Log.e(TAG, "Connection error: ${e.message}")
            activity.runOnUiThread {
                result.error("CONNECTION_ERROR", e.message, null)
            }
        }
    }
}


    private fun tryFallbackConnection(address: String, result: MethodChannel.Result) {
        thread {
            try {
                Log.d(TAG, "Trying fallback connection method")
                val device = btAdapter!!.getRemoteDevice(address)
                
                // Alternative connection method for some devices
                val method = device::class.java.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                btSocket = method.invoke(device, 1) as BluetoothSocket
                
                btAdapter!!.cancelDiscovery()
                btSocket!!.connect()
                
                outputStream = btSocket!!.outputStream
                inputStream = btSocket!!.inputStream
                
                startReading()
                
                activity.runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Fallback connection failed: ${e.message}")
                activity.runOnUiThread {
                    result.error("CONNECTION_FAILED", "All connection methods failed", null)
                }
            }
        }
    }

    private fun startReading() {
        isReading = true
        readThread = thread {
            val buffer = ByteArray(1024)
            var bytes: Int

            Log.d(TAG, "Starting data reading thread")

            while (isReading && !Thread.currentThread().isInterrupted) {
                try {
                    bytes = inputStream!!.read(buffer)
                    if (bytes > 0) {
                        val data = String(buffer, 0, bytes).trim()
                        Log.d(TAG, "Received data: $data")
                        
                        // Send to Flutter
                        activity.runOnUiThread {
                            eventSink?.success(data)
                        }
                    }
                } catch (e: IOException) {
                    Log.e(TAG, "Read error: ${e.message}")
                    if (isReading) {
                        disconnect()
                    }
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "Read exception: ${e.message}")
                    break
                }
                
                // Small delay to prevent busy waiting
                Thread.sleep(100)
            }
            
            Log.d(TAG, "Data reading thread stopped")
        }
    }

    private fun sendData(data: String, result: MethodChannel.Result) {
        thread {
            try {
                if (outputStream == null || btSocket == null || !btSocket!!.isConnected) {
                    activity.runOnUiThread {
                        result.error("NOT_CONNECTED", "Not connected to device", null)
                    }
                    return@thread
                }

                Log.d(TAG, "Sending data: $data")
                outputStream!!.write(data.toByteArray())
                outputStream!!.flush()
                
                activity.runOnUiThread {
                    result.success(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Send data error: ${e.message}")
                activity.runOnUiThread {
                    result.error("SEND_ERROR", e.message, null)
                }
            }
        }
    }

    private fun disconnect() {
        Log.d(TAG, "Disconnecting...")
        
        isReading = false
        
        // Stop threads
        connectThread?.interrupt()
        readThread?.interrupt()
        
        // Close streams
        try {
            inputStream?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing input stream: ${e.message}")
        }
        
        try {
            outputStream?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing output stream: ${e.message}")
        }
        
        // Close socket
        try {
            btSocket?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing socket: ${e.message}")
        }
        
        // Clear references
        inputStream = null
        outputStream = null
        btSocket = null
        
        Log.d(TAG, "Disconnected successfully")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Activity destroyed, cleaning up Bluetooth")
        disconnect()
    }
}