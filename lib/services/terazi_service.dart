import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../bluetooth/classic_bluetooth_service.dart';

class TeraziService {
  static final TeraziService _instance = TeraziService._internal();
  factory TeraziService() => _instance;
  TeraziService._internal();

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
      final required = <Permission>[
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];

      final statuses = await required.request();
      for (var p in required) {
        if (statuses[p] == null || !statuses[p]!.isGranted) return false;
      }
      return true;
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
                if (data.isNotEmpty) {
                  final raw = utf8.decode(data);
                  _processWeightData(raw);
                }
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
        (data) {
          try {
            final raw = utf8.decode(data);
            _processWeightData(raw);
          } catch (e) {
            if (kDebugMode) print("WiFi decode error: $e");
          }
        },
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
  void _processWeightData(String rawData) {
    try {
      String clean = rawData.replaceAll(RegExp(r'[\r\n]'), ' ');
      final match = RegExp(r'[-+]?\d{1,}\s*[.,]?\s*\d*').firstMatch(clean);
      if (match != null) {
        String numStr = match.group(0)?.replaceAll(RegExp(r'\s+'), '') ?? '0';
        numStr = numStr.replaceAll(',', '.');
        int dotCount = '.'.allMatches(numStr).length;
        if (dotCount > 1) {
          int lastDot = numStr.lastIndexOf('.');
          numStr = numStr.substring(0, lastDot).replaceAll('.', '') + numStr.substring(lastDot);
        }
        bool isNegative = numStr.startsWith('-');
        if (isNegative) numStr = numStr.substring(1);
        final parsed = double.tryParse(numStr);
        if (parsed != null) {
          _weightController.add((isNegative ? -parsed : parsed).toStringAsFixed(2));
          return;
        }
      }
      _weightController.add("0.00");
    } catch (e) {
      _weightController.add("0.00");
    }
  }

  // ------------------------
  // Disconnect / Cleanup
  // ------------------------
  Future<void> disconnect() async {
    _cleanupBLE();
    _cleanupWiFi();
    try {
      await _classic.disconnect();
    } catch (_) {}
    _classicDataSubscription?.cancel();
    _classicDataSubscription = null;
    _weightController.add("0.00");
    _connectionController.add(false);
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

  void dispose() {
    disconnect();
    _weightController.close();
    _connectionController.close();
  }
}
