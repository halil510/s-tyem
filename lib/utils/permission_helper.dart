import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bluetooth izinlerinin TEK kaynağı (terazi, fiş yazıcısı, cihazlar arası aktarım).
///
/// Android sürümüne göre doğru izin istenir:
/// - Android 12+ (API 31+): "Yakındaki cihazlar" — BLUETOOTH_SCAN + BLUETOOTH_CONNECT.
///   Konum İSTENMEZ: manifest'te konum yalnız API ≤30 için tanımlı ve tarama
///   `neverForLocation` ile yapılır.
/// - Android 11 ve altı: BLE taraması için konum izni.
///
/// Eskiden 4 farklı yerde 4 farklı şekilde isteniyordu ve hepsi konum iznini ŞART
/// koşuyordu → Android 12+ telefonlarda konum izni manifest'te olmadığından
/// istek anında reddediliyor, terazi Bluetooth ile HİÇ bağlanamıyordu.
class PermissionHelper {
  /// Android API düzeyi için istenecek izinler.
  @visibleForTesting
  static List<Permission> gerekenler(int sdk, {bool yayin = false}) {
    if (sdk >= 31) {
      return [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        if (yayin) Permission.bluetoothAdvertise,
      ];
    }
    return [Permission.locationWhenInUse];
  }

  static Future<int> _androidSdk() async => (await DeviceInfoPlugin().androidInfo).version.sdkInt;

  /// Gerekli Bluetooth izinlerini ister; hepsi verildiyse true.
  /// [yayin]: cihazlar arası aktarımda bu telefon kendini duyuracaksa.
  static Future<bool> bluetoothIzinleri({bool yayin = false}) async {
    try {
      if (Platform.isIOS) return (await Permission.bluetooth.request()).isGranted;
      if (!Platform.isAndroid) return true;
      final izinler = gerekenler(await _androidSdk(), yayin: yayin);
      final sonuc = await izinler.request();
      return izinler.every((p) => sonuc[p]?.isGranted == true);
    } catch (e) {
      debugPrint('Bluetooth izin hatası: $e');
      return false;
    }
  }

  /// Kullanıcı izni "bir daha sorma" ile reddettiyse true — ayarlara yönlendirmek için.
  static Future<bool> kaliciReddedildiMi() async {
    if (!Platform.isAndroid) return false;
    for (final p in gerekenler(await _androidSdk())) {
      if (await p.isPermanentlyDenied) return true;
    }
    return false;
  }

  /// Eski ad (geriye uyumluluk).
  static Future<bool> checkBluetoothPermissions() => bluetoothIzinleri();
}
