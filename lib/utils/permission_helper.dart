import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<bool> checkBluetoothPermissions() async {
    var bluetoothConnectStatus = await Permission.bluetoothConnect.status;
    if (!bluetoothConnectStatus.isGranted) {
      bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    }

    var bluetoothScanStatus = await Permission.bluetoothScan.status;
    if (!bluetoothScanStatus.isGranted) {
      bluetoothScanStatus = await Permission.bluetoothScan.request();
    }

    var locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.locationWhenInUse.request();
    }

    return bluetoothConnectStatus.isGranted && 
           bluetoothScanStatus.isGranted && 
           locationStatus.isGranted;
  }
}