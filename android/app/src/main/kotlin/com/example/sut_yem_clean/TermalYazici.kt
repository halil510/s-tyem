package com.example.sut_yem_clean

import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Bluetooth (Classic / SPP) termal fiş yazıcısı.
 *
 * Terazinin bağlantısından (MainActivity'deki btSocket) TAMAMEN AYRIDIR:
 * her fiş için yazıcıya ayrı bağlanır, baytları yazar ve bağlantıyı kapatır.
 * Böylece fiş yazdırmak teraziyi koparmaz.
 *
 * Kanal: "termal_yazici"
 *   yazdir(address: String, bytes: ByteArray) -> true | hata
 */
class TermalYazici(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val tag = "TermalYazici"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    @Volatile
    private var mesgul = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "yazdir" -> {
                val adres = call.argument<String>("address")
                val baytlar = call.argument<ByteArray>("bytes")
                if (adres.isNullOrEmpty() || baytlar == null) {
                    result.error("GECERSIZ", "Yazıcı adresi veya veri yok", null)
                } else {
                    yazdir(adres, baytlar, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun yazdir(adres: String, baytlar: ByteArray, result: MethodChannel.Result) {
        if (mesgul) {
            result.error("MESGUL", "Yazıcı başka bir fişi yazdırıyor", null)
            return
        }
        mesgul = true
        thread {
            var soket: BluetoothSocket? = null
            try {
                val adaptor = BluetoothAdapter.getDefaultAdapter()
                    ?: throw IllegalStateException("Bu cihazda Bluetooth yok")
                if (!adaptor.isEnabled) throw IllegalStateException("Bluetooth kapalı")
                val cihaz = adaptor.getRemoteDevice(adres)
                adaptor.cancelDiscovery()

                soket = cihaz.createRfcommSocketToServiceRecord(sppUuid)
                try {
                    soket!!.connect()
                } catch (e: Exception) {
                    Log.w(tag, "Standart bağlantı olmadı, yedek yöntem deneniyor: ${e.message}")
                    try { soket?.close() } catch (_: Exception) {}
                    val m = cihaz.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    soket = m.invoke(cihaz, 1) as BluetoothSocket
                    soket!!.connect()
                }

                val cikis = soket!!.outputStream
                // Küçük parçalar: bazı ucuz yazıcıların tamponu taşmasın.
                var i = 0
                while (i < baytlar.size) {
                    val son = minOf(i + 512, baytlar.size)
                    cikis.write(baytlar, i, son - i)
                    cikis.flush()
                    i = son
                    Thread.sleep(20)
                }
                // Yazıcı tamponunu boşaltana kadar bağlantıyı hemen kesme.
                Thread.sleep(400)
                activity.runOnUiThread { result.success(true) }
            } catch (e: SecurityException) {
                Log.e(tag, "İzin yok: ${e.message}")
                activity.runOnUiThread { result.error("IZIN", "Bluetooth izni verilmemiş", null) }
            } catch (e: Exception) {
                Log.e(tag, "Yazdırma hatası: ${e.message}")
                activity.runOnUiThread {
                    result.error("YAZDIRILAMADI", e.message ?: "Yazıcıya bağlanılamadı", null)
                }
            } finally {
                try { soket?.close() } catch (_: Exception) {}
                mesgul = false
            }
        }
    }
}
