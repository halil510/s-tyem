import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sutyem_pro/utils/permission_helper.dart';

/// Android sürümüne göre doğru Bluetooth izinleri. REGRESYON: eskiden konum
/// izni her sürümde şarttı; manifest'te konum yalnız API ≤30 için tanımlı
/// olduğundan Android 12+ telefonda terazi Bluetooth ile bağlanamıyordu.
void main() {
  test('Android 12+ (API 31+): yalnız Yakındaki cihazlar izinleri, KONUM YOK', () {
    for (final sdk in [31, 33, 34, 36]) {
      final izinler = PermissionHelper.gerekenler(sdk);
      expect(izinler, containsAll([Permission.bluetoothScan, Permission.bluetoothConnect]));
      expect(izinler.any((p) => p == Permission.location || p == Permission.locationWhenInUse), isFalse,
          reason: 'API $sdk konum istememeli');
    }
    expect(PermissionHelper.gerekenler(34, yayin: true), contains(Permission.bluetoothAdvertise));
  });

  test('Android 11 ve altı: BLE taraması için konum', () {
    for (final sdk in [23, 28, 30]) {
      expect(PermissionHelper.gerekenler(sdk), [Permission.locationWhenInUse]);
    }
  });
}
