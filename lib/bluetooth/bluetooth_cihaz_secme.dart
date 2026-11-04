import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import '../utils/permission_helper.dart';
import 'ble_service.dart';
import 'bluetooth_aktarim.dart';

class BluetoothCihazSecmeEkrani extends StatefulWidget {
  const BluetoothCihazSecmeEkrani({super.key});

  @override
  State<BluetoothCihazSecmeEkrani> createState() => _BluetoothCihazSecmeEkraniState();
}

class _BluetoothCihazSecmeEkraniState extends State<BluetoothCihazSecmeEkrani> {
  final BLEService _bleService = BLEService();
  List<BluetoothDevice> _bleDevices = [];
  bool _scanning = false;
  String _status = '';
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
    _setupBluetoothStateListener();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _bleService.stopScan();
    super.dispose();
  }

  Future<bool> _checkPermissions() async {
    try {
      // Android sürümüne göre doğru izinler (bkz. PermissionHelper).
      return await PermissionHelper.bluetoothIzinleri(yayin: true);
    } catch (e) {
      debugPrint("İzin kontrolü hatası: $e");
      return false;
    }
  }

  void _setupBluetoothStateListener() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        if (mounted) {
          _showSnackBar('Bluetooth kapalı. Lütfen açın.');
        }
      }
    });
  }

  Future<void> _loadPairedDevices() async {
    try {
      final bondedDevices = await _bleService.getBondedDevices();
      if (mounted) {
        setState(() {
          _bleDevices = bondedDevices;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Eşleştirilmiş cihazlar yüklenemedi: $e');
      }
    }
  }

  Future<void> _scanDevices() async {
    if (!mounted) return;
    
    final hasPermissions = await _checkPermissions();
    if (!hasPermissions) {
      _showSnackBar('Bluetooth ve konum izinleri gereklidir. Lütfen ayarlardan izin verin.');
      await openAppSettings();
      return;
    }

    try {
      final bluetoothState = await FlutterBluePlus.adapterState.first;
      if (bluetoothState != BluetoothAdapterState.on) {
        _showSnackBar('Lütfen Bluetooth\'u açın');
        return;
      }
    } catch (e) {
      _showSnackBar('Bluetooth durumu kontrol edilemedi: $e');
      return;
    }

    if (!mounted) return;
    
    setState(() {
      _scanning = true;
      _status = 'Cihazlar taranıyor...';
      _bleDevices.clear();
    });

    try {
      await _bleService.stopScan();
      await _bleService.startScan(timeout: const Duration(seconds: 15));
      
      _scanSubscription?.cancel();
      _scanSubscription = _bleService.scanResults.listen((results) {
        if (!mounted) return;
        
        setState(() {
          for (var result in results) {
            if (!_bleDevices.any((device) => device.remoteId == result.device.remoteId)) {
              _bleDevices.add(result.device);
            }
          }
        });
      });

      await Future.delayed(const Duration(seconds: 15));
      await _bleService.stopScan();
      
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = 'Tarama tamamlandı. ${_bleDevices.length} cihaz bulundu.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _status = 'Tarama hatası: $e';
        });
        _showSnackBar('Tarama hatası: $e');
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _showSnackBar('${device.platformName} bağlanıyor...');
      
      if (!mounted) return;
      
      // Samsung cihazlar için özel mesaj
      final isSamsung = device.platformName.toLowerCase().contains('samsung');
      if (isSamsung) {
        _showSnackBar('Samsung cihaz tespit edildi. Bağlantı biraz uzun sürebilir...');
      }
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BluetoothAktarimEkrani(
            bleDevice: device,
            isBLE: true,
          ),
        ),
      );
      
      _loadPairedDevices();
    } catch (e) {
      _showSnackBar('Bağlantı hatası: $e');
      debugPrint("Bağlantı hatası detayı: $e");
    }
  }

  Future<void> _connectViaWiFi() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BluetoothAktarimEkrani(
            isBLE: false,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Wi-Fi bağlantı hatası: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Tamam',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  Future<void> _openBluetoothSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      _showSnackBar('Ayarlar açılamadı: $e');
    }
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _scanning ? 'Cihazlar taranıyor...' : 'Cihaz bulunamadı',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (!_scanning && _bleDevices.isEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Ayarları Aç'),
                onPressed: _openBluetoothSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCount(int count) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        '$count cihaz bulundu',
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _buildBLEDeviceTile(BluetoothDevice device) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: StreamBuilder<BluetoothConnectionState>(
          stream: device.connectionState,
          initialData: BluetoothConnectionState.disconnected,
          builder: (context, snapshot) {
            final state = snapshot.data ?? BluetoothConnectionState.disconnected;
            return Icon(
              state == BluetoothConnectionState.connected 
                  ? Icons.bluetooth_connected 
                  : Icons.bluetooth,
              color: state == BluetoothConnectionState.connected 
                  ? Colors.green 
                  : Colors.blue,
            );
          },
        ),
        title: Text(
          device.platformName.isNotEmpty 
              ? device.platformName 
              : 'Bilinmeyen Cihaz',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${device.remoteId}'),
            StreamBuilder<BluetoothConnectionState>(
              stream: device.connectionState,
              initialData: BluetoothConnectionState.disconnected,
              builder: (context, snapshot) {
                final state = snapshot.data ?? BluetoothConnectionState.disconnected;
                return Text(
                  'Bağlantı: ${_getConnectionStateText(state)}',
                  style: TextStyle(
                    color: state == BluetoothConnectionState.connected 
                        ? Colors.green 
                        : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _connectToDevice(device),
          child: const Text('Bağlan'),
        ),
      ),
    );
  }

  String _getConnectionStateText(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return 'Bağlı';
      case BluetoothConnectionState.connecting:
        return 'Bağlanıyor';
      case BluetoothConnectionState.disconnected:
        return 'Bağlı Değil';
      case BluetoothConnectionState.disconnecting:
        return 'Bağlantı Kesiliyor';
      default:
        return 'Bilinmeyen';
    }
  }

  Widget _buildDeviceList() {
    if (_bleDevices.isEmpty) {
      return _buildEmptyState();
    }

    return Expanded(
      child: Column(
        children: [
          _buildDeviceCount(_bleDevices.length),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadPairedDevices,
              child: ListView.builder(
                itemCount: _bleDevices.length,
                itemBuilder: (context, index) {
                  final device = _bleDevices[index];
                  return _buildBLEDeviceTile(device);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(_scanning ? Icons.stop : Icons.search),
                  label: Text(_scanning ? 'DURDUR' : 'TARA'),
                  onPressed: _scanning ? _bleService.stopScan : _scanDevices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scanning ? Colors.orange : Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('YENİLE'),
                  onPressed: _loadPairedDevices,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('BLUETOOTH AYARLARI'),
                  onPressed: _openBluetoothSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.wifi),
                  label: const Text('Wi-Fi İLE BAĞLAN'),
                  onPressed: _connectViaWiFi,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Seçimi'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(height: 8),
                Text(
                  'Bluetooth veya Wi-Fi ile bağlanabilirsiniz.',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
                SizedBox(height: 4),
                Text(
                  'Samsung cihazlarda Wi-Fi önerilir.',
                  style: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildControlButtons(),
          const SizedBox(height: 16),
          _buildDeviceList(),
        ],
      ),
    );
  }
}