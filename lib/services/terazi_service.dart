import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/permission_helper.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../bluetooth/classic_bluetooth_service.dart';
import '../features/terazi/services/terazi_veri_cozucu.dart';

/// Düşük seviyeli terazi bağlantısı (BLE / Classic Bluetooth / Wi-Fi).
///
/// Eskiden tekil (singleton) idi: `dispose()` ortak akışları KAPATIYOR,
/// sonra kurulan servis kapalı akışa yazmaya çalışıp çöküyordu. Artık her
/// [TeraziServicePro] kendi örneğini kullanır.
class TeraziService {
  TeraziService() {
    _cozucu = TeraziVeriCozucu((kg) {
      if (!_weightController.isClosed) _weightController.add(kg.toStringAsFixed(2));
    });
  }

  /// Parça parça gelen veriyi satırlara ayırıp kiloyu çözer.
  late final TeraziVeriCozucu _cozucu;

  // ------------------------
  // BLE
  // ------------------------
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _bleCharacteristic;
  StreamSubscription<List<int>>? _bleDataSubscription;
  StreamSubscription<BluetoothConnectionState>? _bleConnectionSubscription;

  // ------------------------
  // Classic
  // ------------------------
  final ClassicBluetoothService _classic = ClassicBluetoothService();
  StreamSubscription<String>? _classicDataSubscription;

  ClassicBluetoothService get classicService => _classic; // ✅ Getter eklendi

  // ------------------------
  // Wi-Fi
  // ------------------------
  Socket? _wifiSocket;
  StreamSubscription<List<int>>? _wifiSubscription;

  // ------------------------
  // StreamController
  // ------------------------
  final StreamController<String> _weightController = StreamController<String>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  Stream<String> get weightStream => _weightController.stream;
  Stream<String> get kgStream => weightStream; // geri uyumluluk
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => (_bleDevice != null) || (_wifiSocket != null);

  // ------------------------
  // İzin kontrol
  // ------------------------
  Future<bool> checkAndRequestPermissions() async {
    try {
      // Android 12+ konum istemez; eskiden konum şart olduğundan terazi
      // yeni telefonlarda Bluetooth ile hiç bağlanamıyordu.
      return await PermissionHelper.bluetoothIzinleri();
    } catch (e) {
      if (kDebugMode) print("İzin kontrol hatası: $e");
      return false;
    }
  }

  // ------------------------
  // BLE: Tarama
  // ------------------------
  Future<List<BluetoothDevice>> scanBLEDevices({Duration timeout = const Duration(seconds: 8)}) async {
    List<BluetoothDevice> foundDevices = [];
    try {
      if (!await checkAndRequestPermissions()) {
        throw Exception("Bluetooth izinleri alınamadı");
      }

      await FlutterBluePlus.stopScan();
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (var r in results) {
          if (!foundDevices.any((d) => d.remoteId == r.device.remoteId)) {
            foundDevices.add(r.device);
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    } catch (e) {
      if (kDebugMode) print("BLE scan hatası: $e");
      rethrow;
    }
    return foundDevices;
  }

  // ------------------------
  // BLE: Bağlanma
  // ------------------------
  Future<void> connectToBLETerazi(BluetoothDevice device) async {
    try {
      await disconnect();
      _bleDevice = device;

      _bleConnectionSubscription = device.connectionState.listen((state) {
        if (kDebugMode) print("BLE state: $state");
        if (state == BluetoothConnectionState.connected) {
          _connectionController.add(true);
        } else if (state == BluetoothConnectionState.disconnected) {
          _cleanupBLE();
          _connectionController.add(false);
          _weightController.add("0.0");
        }
      });

      await device.connect(timeout: const Duration(seconds: 12));
      await Future.delayed(const Duration(milliseconds: 500));
      final services = await device.discoverServices();
      bool characteristicFound = false;

      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify || characteristic.properties.read) {
            _bleCharacteristic = characteristic;
            characteristicFound = true;
            if (characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              _bleDataSubscription = characteristic.onValueReceived.listen((data) {
                if (data.isNotEmpty) _processWeightData(latin1.decode(data, allowInvalid: true));
              });
            }
            break;
          }
        }
        if (characteristicFound) break;
      }

      if (!characteristicFound) throw Exception("BLE karakteristik bulunamadı");
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  // ------------------------
  // Classic: Bağlanma
  // ------------------------
  Future<void> connectToClassic(String address) async {
    try {
      await disconnect();
      final ok = await _classic.connect(address);
      if (!ok) throw Exception("Classic bağlantı sağlanamadı");
      _connectionController.add(true);
      _classicDataSubscription = _classic.dataStream.listen((raw) {
        if (kDebugMode) print("Classic raw: $raw");
        _processWeightData(raw);
      });
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  // ------------------------
  // Wi-Fi: Bağlanma
  // ------------------------
  Future<void> connectWifi(String ip, int port) async {
    try {
      await disconnect();
      _wifiSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      _connectionController.add(true);

      _wifiSubscription = _wifiSocket!.listen(
        // Terazi verisi ASCII'dir; utf8 bir paketin ortasında bölünen baytta
        // hata atıp o paketi tümden kaybediyordu.
        (data) => _processWeightData(latin1.decode(data, allowInvalid: true)),
        onError: (e) {
          if (kDebugMode) print("WiFi socket error: $e");
          _connectionController.add(false);
        },
        onDone: () {
          _connectionController.add(false);
        },
      );
    } catch (e) {
      _connectionController.add(false);
      rethrow;
    }
  }

  // ------------------------
  // Veri işle
  // ------------------------
  /// Ham parçayı çözücüye verir (bkz. [TeraziVeriCozucu]: satırlara ayırma,
  /// bölünen satırları birleştirme, birden çok sayı içeren satırlar).
  void _processWeightData(String rawData) => _cozucu.ekle(rawData);

  // ------------------------
  // Disconnect / Cleanup
  // ------------------------
  Future<void> disconnect() async {
    _cozucu.sifirla();
    _cleanupBLE();
    _cleanupWiFi();
    try {
      await _classic.disconnect();
    } catch (_) {}
    _classicDataSubscription?.cancel();
    _classicDataSubscription = null;
    // dispose() sırasında akışlar kapanmış olabilir.
    if (!_weightController.isClosed) _weightController.add("0.00");
    if (!_connectionController.isClosed) _connectionController.add(false);
  }

  void _cleanupBLE() {
    _bleDataSubscription?.cancel();
    _bleConnectionSubscription?.cancel();
    _bleCharacteristic = null;
    if (_bleDevice != null) {
      try {
        _bleDevice!.disconnect();
      } catch (_) {}
      _bleDevice = null;
    }
  }

  void _cleanupWiFi() {
    try {
      _wifiSubscription?.cancel();
      _wifiSocket?.destroy();
    } catch (_) {}
    _wifiSubscription = null;
    _wifiSocket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _weightController.close();
    await _connectionController.close();
  }
}
