import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  // Bluetooth durumu
  Stream<BluetoothAdapterState> get stateStream => FlutterBluePlus.adapterState;
  
  // Tarama sonuçları
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  // Bağlı cihazlar
  Future<List<BluetoothDevice>> getConnectedDevices() async {
    return await FlutterBluePlus.connectedDevices;
  }

  // Eşleştirilmiş cihazlar
  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await FlutterBluePlus.bondedDevices;
  }

  // Bluetooth'u aç
  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      print("Bluetooth açma hatası: $e");
      rethrow;
    }
  }

  // Tarama başlat
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      print("Tarama başlatma hatası: $e");
      rethrow;
    }
  }

  // Tarama durdur
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print("Tarama durdurma hatası: $e");
      rethrow;
    }
  }

  // Cihaz bağlantısı
  Future<void> connectToDevice(BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false,
  }) async {
    try {
      await device.connect(
        autoConnect: autoConnect,
        timeout: timeout,
      );
    } catch (e) {
      print("Bağlantı hatası: $e");
      rethrow;
    }
  }

  // Bağlantıyı kes
  Future<void> disconnectDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
    } catch (e) {
      print("Bağlantı kesme hatası: $e");
      rethrow;
    }
  }

  // Servisleri keşfet
  Future<List<BluetoothService>> discoverServices(BluetoothDevice device) async {
    try {
      return await device.discoverServices();
    } catch (e) {
      print("Servis keşfi hatası: $e");
      rethrow;
    }
  }

  // Karakteristik bul (Geliştirilmiş)
  BluetoothCharacteristic? findCharacteristicForTransfer(List<BluetoothService> services) {
    BluetoothCharacteristic? txChar, rxChar;
    
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        final uuid = characteristic.uuid.toString().toLowerCase();
        
        // TX karakteristiği (yazma)
        if ((characteristic.properties.write || characteristic.properties.writeWithoutResponse) &&
            (uuid.contains('ffe1') || uuid.contains('fff1') || 
             uuid.contains('2a00') || uuid.contains('2a01') ||
             uuid.contains('0000ffe1') || uuid.contains('0000fff1'))) {
          txChar = characteristic;
        }
        
        // RX karakteristiği (okuma/notify)
        if ((characteristic.properties.notify || characteristic.properties.read || 
             characteristic.properties.indicate) &&
            (uuid.contains('ffe2') || uuid.contains('fff2') || 
             uuid.contains('2a02') || uuid.contains('2a03') ||
             uuid.contains('0000ffe2') || uuid.contains('0000fff2'))) {
          rxChar = characteristic;
        }
      }
    }
    
    // Eğer standart UUID'ler bulunamazsa, ilk bulunan uygun karakteristikleri kullan
    if (txChar == null) {
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            txChar = characteristic;
            break;
          }
        }
        if (txChar != null) break;
      }
    }
    
    if (rxChar == null) {
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify || characteristic.properties.read) {
            rxChar = characteristic;
            break;
          }
        }
        if (rxChar != null) break;
      }
    }
    
    // TX karakteristiği daha önemli olduğu için onu döndür
    return txChar ?? rxChar;
  }

  // Cihaz adını al
  static String getDeviceDisplayName(ScanResult result) {
    String name = result.device.platformName;
    if (name.isEmpty) {
      name = result.advertisementData.localName;
    }
    if (name.isEmpty) {
      name = result.advertisementData.advName;
    }
    if (name.isEmpty) {
      name = 'Bilinmeyen Cihaz (${result.device.remoteId.toString().substring(0, 8)})';
    }
    return name;
  }

  // UUID'leri normalize et
  static String normalizeUuid(String uuid) {
    uuid = uuid.toLowerCase().replaceAll('-', '');
    if (uuid.length == 4) {
      return '0000$uuid-0000-1000-8000-00805f9b34fb';
    } else if (uuid.length == 8) {
      return '$uuid-0000-1000-8000-00805f9b34fb';
    }
    return uuid;
  }
}