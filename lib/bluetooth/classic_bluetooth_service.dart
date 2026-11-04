import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ClassicBluetoothService {
  static const MethodChannel _channel =
      MethodChannel('classic_bluetooth');

  static const EventChannel _eventChannel =
      EventChannel('classic_bluetooth_events');

  final StreamController<String> _dataController =
      StreamController<String>.broadcast();

  ClassicBluetoothService() {
    _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is String) {
        _dataController.add(event);
      }
    }, onError: (e) {
      if (kDebugMode) print("Classic event error: $e");
    });
  }

  Stream<String> get dataStream => _dataController.stream;

  Future<List<Map<String, dynamic>>> getPairedDevices() async {
    try {
      final devices =
          await _channel.invokeMethod<List<dynamic>>('getPairedDevices');
      return devices?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      if (kDebugMode) print("getPairedDevices error: $e");
      return [];
    }
  }

  Future<bool> connect(String address) async {
    try {
      final result =
          await _channel.invokeMethod('connect', {'address': address});
      return result == true;
    } catch (e) {
      if (kDebugMode) print("connect error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (e) {
      if (kDebugMode) print("disconnect error: $e");
    }
  }

  Future<bool> sendData(String data) async {
    try {
      final result =
          await _channel.invokeMethod('sendData', {'data': data});
      return result == true;
    } catch (e) {
      if (kDebugMode) print("sendData error: $e");
      return false;
    }
  }
}
