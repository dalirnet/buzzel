package com.buzzel.transport

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import com.buzzel.protocol.BleUuids
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

@SuppressLint("MissingPermission")
class BleGattServer(
    private val context: Context,
    private val onMessageReceived: (ByteArray) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit
) {
    companion object {
        private const val TAG = "BleGattServer"
        private const val DEFAULT_MTU = 23
        private const val ATT_OVERHEAD = 3
        private const val MIN_CHUNK_SIZE = 20
        private const val NOTIFICATION_TIMEOUT_SEC = 5L
        private const val MAX_FRAME_SIZE = 1_000_000
    }

    private var bluetoothManager: BluetoothManager? = null
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var smsCharacteristic: BluetoothGattCharacteristic? = null
    private var statusCharacteristic: BluetoothGattCharacteristic? = null
    private var isAdvertising = false
    private var lowPower = true
    private var negotiatedMtu = DEFAULT_MTU
    private var recvBuffer = ByteArray(0)
    private var preparedWriteBuffer = ByteArray(0)
    private val recvLock = Any()
    private val notificationSentSignal = LinkedBlockingQueue<Int>(1)

    private val gattCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Device connected: ${device.address}")
                connectedDevice = device
                onConnectionChanged(true)
                stopAdvertising()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Device disconnected: ${device.address}")
                if (connectedDevice?.address == device.address) {
                    connectedDevice = null
                    negotiatedMtu = DEFAULT_MTU
                    recvBuffer = ByteArray(0)
                    preparedWriteBuffer = ByteArray(0)
                    onConnectionChanged(false)
                    startAdvertising()
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid == BleUuids.CONFIG_CHAR) {
                if (responseNeeded) {
                    // For prepared writes, must echo back offset and value per BLE spec
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
                }
                if (preparedWrite) {
                    preparedWriteBuffer += value
                } else {
                    processReceivedData(value)
                }
            } else {
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null)
                }
            }
        }

        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (execute && preparedWriteBuffer.isNotEmpty()) {
                processReceivedData(preparedWriteBuffer)
            }
            preparedWriteBuffer = ByteArray(0)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (descriptor.uuid == BleUuids.CCCD) {
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == BleUuids.STATUS_CHAR) {
                val data = (statusCharacteristic?.value ?: """{"connected":true}""".toByteArray(Charsets.UTF_8))
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, data)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            Log.d(TAG, "MTU changed: $mtu")
            negotiatedMtu = mtu
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            Log.d(TAG, "Notification sent, status=$status")
            notificationSentSignal.offer(status)
        }
    }

    private fun processReceivedData(data: ByteArray) {
        synchronized(recvLock) {
            recvBuffer += data
            while (recvBuffer.size >= 4) {
                val length = (recvBuffer[0].toInt() and 0xFF shl 24) or
                        (recvBuffer[1].toInt() and 0xFF shl 16) or
                        (recvBuffer[2].toInt() and 0xFF shl 8) or
                        (recvBuffer[3].toInt() and 0xFF)
                if (length <= 0 || length > MAX_FRAME_SIZE) {
                    recvBuffer = ByteArray(0)
                    break
                }
                val totalNeeded = 4 + length
                if (recvBuffer.size < totalNeeded) break
                val payload = recvBuffer.copyOfRange(4, totalNeeded)
                recvBuffer = recvBuffer.copyOfRange(totalNeeded, recvBuffer.size)
                Log.d(TAG, "Frame received: $length bytes")
                onMessageReceived(payload)
            }
        }
    }

    fun start() {
        try {
            bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter
            if (adapter == null || !adapter.isEnabled) {
                Log.e(TAG, "Bluetooth not available or not enabled")
                return
            }

            gattServer = bluetoothManager?.openGattServer(context, gattCallback)
            if (gattServer == null) {
                Log.e(TAG, "Failed to open GATT server")
                return
            }

            setupService()
            startAdvertising()
            Log.d(TAG, "BLE GATT server started")
        } catch (e: SecurityException) {
            Log.e(TAG, "BLE permissions not granted", e)
        }
    }

    fun stop() {
        try {
            stopAdvertising()
            gattServer?.close()
        } catch (e: SecurityException) {
            Log.e(TAG, "BLE stop failed", e)
        }
        gattServer = null
        connectedDevice = null
        Log.d(TAG, "BLE GATT server stopped")
    }

    /** Force-disconnect the current BLE client and restart advertising. */
    fun disconnectDevice() {
        val device = connectedDevice ?: return
        try {
            gattServer?.cancelConnection(device)
        } catch (e: SecurityException) {
            Log.e(TAG, "BLE disconnect failed", e)
        }
        connectedDevice = null
        negotiatedMtu = DEFAULT_MTU
        synchronized(recvLock) {
            recvBuffer = ByteArray(0)
            preparedWriteBuffer = ByteArray(0)
        }
        if (!isAdvertising) {
            startAdvertising()
        }
    }

    /** Switch between low-power (idle) and high-power (active) advertising */
    fun setLowPower(enabled: Boolean) {
        if (lowPower == enabled) return
        lowPower = enabled
        if (isAdvertising) {
            stopAdvertising()
            startAdvertising()
        }
    }

    fun sendData(data: ByteArray): Boolean {
        val device = connectedDevice ?: return false
        val characteristic = smsCharacteristic ?: return false

        // Frame: 4-byte big-endian length prefix + payload
        val length = data.size
        val frame = ByteArray(4 + length)
        frame[0] = ((length shr 24) and 0xFF).toByte()
        frame[1] = ((length shr 16) and 0xFF).toByte()
        frame[2] = ((length shr 8) and 0xFF).toByte()
        frame[3] = (length and 0xFF).toByte()
        System.arraycopy(data, 0, frame, 4, length)

        // BLE MTU chunking (MTU minus 3 bytes ATT overhead)
        val chunkSize = (negotiatedMtu - ATT_OVERHEAD).coerceAtLeast(MIN_CHUNK_SIZE)
        val chunks = frame.toList().chunked(chunkSize)

        for ((i, chunk) in chunks.withIndex()) {
            notificationSentSignal.clear()
            characteristic.value = chunk.toByteArray()
            val sent = gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            if (sent != true) {
                Log.w(TAG, "Failed to send notification chunk $i/${chunks.size}")
                return false
            }
            // Wait for onNotificationSent before sending next chunk
            if (i < chunks.size - 1) {
                val status = notificationSentSignal.poll(NOTIFICATION_TIMEOUT_SEC, TimeUnit.SECONDS)
                if (status == null) {
                    Log.w(TAG, "Timeout waiting for onNotificationSent at chunk $i/${chunks.size}")
                    return false
                }
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    Log.w(TAG, "Notification failed with status $status at chunk $i/${chunks.size}")
                    return false
                }
            }
        }
        return true
    }

    fun updateStatus(statusJson: ByteArray) {
        statusCharacteristic?.value = statusJson
        val device = connectedDevice
        if (device != null && statusCharacteristic != null) {
            gattServer?.notifyCharacteristicChanged(device, statusCharacteristic!!, false)
        }
    }

    val isConnected: Boolean
        get() = connectedDevice != null

    private fun setupService() {
        val service = BluetoothGattService(BleUuids.SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        // Config characteristic — Mac writes messages here (config, ready, goodbye, pong)
        val configChar = BluetoothGattCharacteristic(
            BleUuids.CONFIG_CHAR,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        service.addCharacteristic(configChar)

        // SMS characteristic — Android notifies Mac with SMS/ping/queue data
        smsCharacteristic = BluetoothGattCharacteristic(
            BleUuids.SMS_CHAR,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            0
        ).also {
            val cccd = BluetoothGattDescriptor(
                BleUuids.CCCD,
                BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ
            )
            it.addDescriptor(cccd)
            service.addCharacteristic(it)
        }

        // Status characteristic — readable status
        statusCharacteristic = BluetoothGattCharacteristic(
            BleUuids.STATUS_CHAR,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        ).also {
            val cccd = BluetoothGattDescriptor(
                BleUuids.CCCD,
                BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ
            )
            it.addDescriptor(cccd)
            service.addCharacteristic(it)
        }

        gattServer?.addService(service)
    }

    private fun startAdvertising() {
        val adapter = bluetoothManager?.adapter ?: return
        val advertiser = adapter.bluetoothLeAdvertiser ?: return

        val mode = if (lowPower)
            AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
        else
            AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY

        val txPower = if (lowPower)
            AdvertiseSettings.ADVERTISE_TX_POWER_LOW
        else
            AdvertiseSettings.ADVERTISE_TX_POWER_HIGH

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(mode)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(txPower)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(BleUuids.SERVICE))
            .build()

        advertiser.startAdvertising(settings, data, advertiseCallback)
        isAdvertising = true
    }

    private fun stopAdvertising() {
        if (!isAdvertising) return
        val advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser ?: return
        advertiser.stopAdvertising(advertiseCallback)
        isAdvertising = false
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.d(TAG, "BLE advertising started (lowPower=$lowPower)")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "BLE advertising failed: $errorCode")
        }
    }
}
