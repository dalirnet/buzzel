package com.buzzel.transport

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import com.buzzel.debug.FileLogger
import com.buzzel.protocol.BluetoothServiceUUIDs
import com.buzzel.protocol.Protocol
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

@SuppressLint("MissingPermission")
class BleGattServer(
    private val context: Context,
    private val onMessageReceived: (ByteArray) -> Unit,
    private val onConnectionChanged: (Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "BleGattServer"
        private const val DEFAULT_MTU = 23
        private const val ATTRIBUTE_PROTOCOL_OVERHEAD = 3
        private const val MIN_CHUNK_SIZE = 20
        private const val NOTIFICATION_TIMEOUT_SECONDS = 5L
    }

    private var bluetoothManager: BluetoothManager? = null
    private var gattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null
    private var dataCharacteristic: BluetoothGattCharacteristic? = null
    private var isAdvertising = false
    private var lowPower = true
    private var negotiatedMtu = DEFAULT_MTU
    private var receiveBuffer = ByteArray(0)
    private var preparedWriteBuffer = ByteArray(0)
    private val receiveLock = Any()
    private val notificationSentSignal = LinkedBlockingQueue<Int>(1)
    private var subscribedToNotifications = false

    private val gattCallback =
        object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int,
            ) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    FileLogger.d(TAG, "Device connected: ${device.address}")
                    connectedDevice = device
                    subscribedToNotifications = false
                    stopAdvertising()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    FileLogger.d(TAG, "Device disconnected: ${device.address}")
                    if (connectedDevice?.address == device.address) {
                        connectedDevice = null
                        subscribedToNotifications = false
                        negotiatedMtu = DEFAULT_MTU
                        receiveBuffer = ByteArray(0)
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
                value: ByteArray,
            ) {
                if (characteristic.uuid == BluetoothServiceUUIDs.DATA_CHARACTERISTIC) {
                    if (responseNeeded) {
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

            override fun onExecuteWrite(
                device: BluetoothDevice,
                requestId: Int,
                execute: Boolean,
            ) {
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
                value: ByteArray,
            ) {
                if (descriptor.uuid == BluetoothServiceUUIDs.CCCD) {
                    descriptor.value = value
                    FileLogger.d(TAG, "CCCD written: ${value.map { it.toInt() and 0xFF }}")
                    if (responseNeeded) {
                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                    }
                    val enabled = value.size >= 2 && value[0].toInt() == 1
                    if (enabled && !subscribedToNotifications) {
                        subscribedToNotifications = true
                        FileLogger.i(TAG, "Central subscribed to notifications — reporting connected")
                        onConnectionChanged(true)
                    }
                }
            }

            override fun onMtuChanged(
                device: BluetoothDevice,
                mtu: Int,
            ) {
                FileLogger.d(TAG, "MTU changed: $mtu")
                negotiatedMtu = mtu
            }

            override fun onNotificationSent(
                device: BluetoothDevice,
                status: Int,
            ) {
                FileLogger.d(TAG, "Notification sent, status=$status")
                notificationSentSignal.offer(status)
            }
        }

    private val bluetoothMaximumPayloadSize: Int
        get() = Protocol.maximumPayloadSize(Protocol.maximumFrameSizeForMaximumTransmissionUnit(negotiatedMtu))

    private fun processReceivedData(data: ByteArray) {
        synchronized(receiveLock) {
            receiveBuffer += data
            receiveBuffer =
                FrameCodec.extractFrames(receiveBuffer, bluetoothMaximumPayloadSize) { payload ->
                    FileLogger.d(TAG, "Frame received: ${payload.size} bytes")
                    onMessageReceived(payload)
                }
        }
    }

    fun start() {
        try {
            bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter
            if (adapter == null || !adapter.isEnabled) {
                FileLogger.e(TAG, "Bluetooth not available or not enabled")
                onConnectionChanged(false)
                return
            }

            gattServer = bluetoothManager?.openGattServer(context, gattCallback)
            if (gattServer == null) {
                FileLogger.e(TAG, "Failed to open GATT server")
                onConnectionChanged(false)
                return
            }

            setupService()
            startAdvertising()
            FileLogger.d(TAG, "BLE GATT server started")
        } catch (e: SecurityException) {
            FileLogger.e(TAG, "BLE permissions not granted", e)
            onConnectionChanged(false)
        }
    }

    fun stop() {
        try {
            stopAdvertising()
            gattServer?.close()
        } catch (e: SecurityException) {
            FileLogger.e(TAG, "BLE stop failed", e)
        }
        gattServer = null
        connectedDevice = null
        FileLogger.d(TAG, "BLE GATT server stopped")
    }

    fun disconnectDevice() {
        val device = connectedDevice ?: return
        try {
            gattServer?.cancelConnection(device)
        } catch (e: SecurityException) {
            FileLogger.e(TAG, "BLE disconnect failed", e)
        }
        connectedDevice = null
        subscribedToNotifications = false
        negotiatedMtu = DEFAULT_MTU
        synchronized(receiveLock) {
            receiveBuffer = ByteArray(0)
            preparedWriteBuffer = ByteArray(0)
        }
        if (!isAdvertising) {
            startAdvertising()
        }
    }

    fun setLowPower(enabled: Boolean) {
        if (lowPower == enabled) return
        FileLogger.d(TAG, "Low power mode: $enabled")
        lowPower = enabled
        if (isAdvertising) {
            stopAdvertising()
            startAdvertising()
        }
    }

    fun sendData(data: ByteArray): Boolean {
        val device = connectedDevice ?: return false
        val characteristic = dataCharacteristic ?: return false

        val frame = FrameCodec.encode(data, bluetoothMaximumPayloadSize)

        val chunkSize = (negotiatedMtu - ATTRIBUTE_PROTOCOL_OVERHEAD).coerceAtLeast(MIN_CHUNK_SIZE)
        val chunks = frame.toList().chunked(chunkSize)
        FileLogger.d(TAG, "Sending ${data.size} bytes in ${chunks.size} chunks (mtu=$negotiatedMtu)")

        for ((i, chunk) in chunks.withIndex()) {
            notificationSentSignal.clear()
            characteristic.value = chunk.toByteArray()
            val sent = gattServer?.notifyCharacteristicChanged(device, characteristic, false)
            if (sent != true) {
                FileLogger.w(TAG, "Failed to send notification chunk $i/${chunks.size}")
                return false
            }
            val status = notificationSentSignal.poll(NOTIFICATION_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (status == null) {
                FileLogger.w(TAG, "Timeout waiting for onNotificationSent at chunk $i/${chunks.size}")
                return false
            }
            if (status != BluetoothGatt.GATT_SUCCESS) {
                FileLogger.w(TAG, "Notification failed with status $status at chunk $i/${chunks.size}")
                return false
            }
        }
        return true
    }

    val isConnected: Boolean
        get() = connectedDevice != null && subscribedToNotifications

    private fun setupService() {
        val service = BluetoothGattService(BluetoothServiceUUIDs.SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        dataCharacteristic =
            BluetoothGattCharacteristic(
                BluetoothServiceUUIDs.DATA_CHARACTERISTIC,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            ).also {
                val cccd =
                    BluetoothGattDescriptor(
                        BluetoothServiceUUIDs.CCCD,
                        BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ,
                    )
                it.addDescriptor(cccd)
                service.addCharacteristic(it)
            }

        gattServer?.addService(service)
        FileLogger.d(TAG, "GATT service configured")
    }

    private fun startAdvertising() {
        val adapter = bluetoothManager?.adapter ?: return
        val advertiser = adapter.bluetoothLeAdvertiser ?: return

        val mode =
            if (lowPower) {
                AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
            } else {
                AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
            }

        val txPower =
            if (lowPower) {
                AdvertiseSettings.ADVERTISE_TX_POWER_LOW
            } else {
                AdvertiseSettings.ADVERTISE_TX_POWER_HIGH
            }

        val settings =
            AdvertiseSettings
                .Builder()
                .setAdvertiseMode(mode)
                .setConnectable(true)
                .setTimeout(0)
                .setTxPowerLevel(txPower)
                .build()

        val data =
            AdvertiseData
                .Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(ParcelUuid(BluetoothServiceUUIDs.SERVICE))
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

    private val advertiseCallback =
        object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                FileLogger.d(TAG, "BLE advertising started (lowPower=$lowPower)")
            }

            override fun onStartFailure(errorCode: Int) {
                FileLogger.e(TAG, "BLE advertising failed: $errorCode")
            }
        }
}
