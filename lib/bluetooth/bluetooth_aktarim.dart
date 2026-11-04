import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'bluetooth_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'wifi_transfer_service.dart';
import '../core/providers/veri_surumu_provider.dart';

class BluetoothAktarimEkrani extends StatefulWidget {
  final BluetoothDevice? bleDevice;
  final Map<String, dynamic>? classicDevice;
  final bool isBLE;
  
  const BluetoothAktarimEkrani({
    super.key,
    this.bleDevice,
    this.classicDevice,
    required this.isBLE,
  });

  @override
  State<BluetoothAktarimEkrani> createState() => _BluetoothAktarimEkraniState();
}

class _BluetoothAktarimEkraniState extends State<BluetoothAktarimEkrani> {
  BluetoothConnectionState _bleConnectionState = BluetoothConnectionState.disconnected;
  bool _bleConnected = false;
  List<BluetoothService>? _services;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;

  bool _classicConnected = false;
  bool _connecting = true;
  bool _servicesDiscovered = false;
  String _status = 'Bağlanıyor...';
  double _progress = 0.0;
  int _bytesTotal = 0;
  int _bytesTransferred = 0;
  bool _isTransferring = false;
  bool _canSend = false;
  bool _canReceive = false;

  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;

  List<int> _receiveBuffer = [];
  int _expectedSize = -1;
  bool _receivingFile = false;
  Completer<Uint8List>? _receiveCompleter;
  Timer? _transferTimer;
  DateTime? _transferStartTime;

  // Optimize edilmiş ayarlar
  static const int CHUNK_SIZE = 512;
  static const int MAX_MTU = 512;
  static const Duration CONNECT_TIMEOUT = Duration(seconds: 30);
  static const Duration DISCOVER_TIMEOUT = Duration(seconds: 20);
  static const Duration TRANSFER_TIMEOUT = Duration(minutes: 10);
  static const Duration TRANSFER_CHUNK_DELAY = Duration(milliseconds: 50);
  static const int MAX_RETRY_COUNT = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeConnection();
    });
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    _transferTimer?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _receiveCompleter?.completeError('Bağlantı kesildi');
    
    if (widget.isBLE && _bleConnected && widget.bleDevice != null) {
      try {
        widget.bleDevice!.disconnect();
      } catch (e) {
        debugPrint("Disconnect error: $e");
      }
    }
  }

  Future<void> _initializeConnection() async {
    try {
      if (widget.isBLE) {
        await _connectBLE();
      } else {
        await _connectViaWiFi();
      }
    } catch (e) {
      _updateStatus('Bağlantı hatası: ${_getErrorMessage(e)}', isError: true);
    }
  }

  Future<void> _connectBLE() async {
    if (widget.bleDevice == null) {
      _updateStatus('BLE cihazı bulunamadı', isError: true);
      return;
    }

    // Bluetooth açık mı kontrolü
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _updateStatus('Bluetooth açık değil', isError: true);
      _showMessage('Bluetooth açık mı?', isError: true);
      setState(() => _connecting = false);
      return;
    }

    // İzin kontrolü
    if (Platform.isAndroid) {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        _updateStatus('Konum izni gerekli', isError: true);
        _showMessage('Lütfen konum izni verin', isError: true);
        setState(() => _connecting = false);
        return;
      }
    }

    _updateStatus('BLE cihazına bağlanılıyor...', connecting: true);

    try {
      // Önceki bağlantıları temizle
      try {
        await widget.bleDevice!.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint("Önceki bağlantı temizleme hatası: $e");
      }

      _connectionSubscription = widget.bleDevice!.connectionState.listen((state) {
        debugPrint("Connection state changed: $state");
        if (state == BluetoothConnectionState.connected) {
          _handleConnected();
        } else if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        }
      });

      await widget.bleDevice!.connect(
        timeout: CONNECT_TIMEOUT,
        autoConnect: false,
        mtu: null,
      );

      await Future.delayed(const Duration(seconds: 1));
      await _discoverServices();

    } catch (e) {
      _updateStatus('BLE bağlantı hatası: ${_getErrorMessage(e)}', isError: true);
      setState(() => _connecting = false);
      _showMessage('Bağlantı başarısız: ${_getErrorMessage(e)}', isError: true);
    }
  }

  Future<void> _connectViaWiFi() async {
    try {
      _updateStatus('Wi-Fi bağlantısı hazırlanıyor...');
      await WiFiTransferService.sendViaWiFiDirect(context);
      setState(() {
        _connecting = false;
        _classicConnected = true;
      });
    } catch (e) {
      _updateStatus('Wi-Fi bağlantı hatası: $e', isError: true);
      setState(() => _connecting = false);
    }
  }

  void _handleConnected() {
    setState(() {
      _bleConnectionState = BluetoothConnectionState.connected;
      _bleConnected = true;
      _connecting = false;
    });
    _updateStatus('BLE Bağlandı');
  }

  void _handleDisconnected() {
    setState(() {
      _bleConnectionState = BluetoothConnectionState.disconnected;
      _bleConnected = false;
      _connecting = false;
      _canSend = false;
      _canReceive = false;
    });
    _updateStatus('Bağlantı kesildi', isError: true);
    _showMessage('Bağlantı kesildi', isError: true);
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('PlatformException')) {
      if (errorStr.contains('already_connected')) {
        return 'Cihaz zaten bağlı';
      } else if (errorStr.contains('already_disconnected')) {
        return 'Cihaz zaten bağlı değil';
      } else if (errorStr.contains('connection_failed') || errorStr.contains('code: 19')) {
        return 'Bağlantı başarısız. Cihazı yeniden başlatın veya eşleştirmeyi kontrol edin.';
      } else if (errorStr.contains('device_disconnected')) {
        return 'Cihaz bağlantısı koptu';
      } else if (errorStr.contains('service_not_found')) {
        return 'Servis bulunamadı';
      } else if (errorStr.contains('characteristic_not_found')) {
        return 'Karakteristik bulunamadı';
      } else if (errorStr.contains('write_failed')) {
        return 'Veri yazma başarısız';
      } else if (errorStr.contains('read_failed')) {
        return 'Veri okuma başarısız';
      } else if (errorStr.contains('code: 13')) {
        return 'İzin reddedildi. Bluetooth ve konum izinlerini kontrol edin.';
      } else if (errorStr.contains('code: 199')) {
        return 'Bilinmeyen hata. Cihazı yeniden başlatın veya uygulamayı güncelleyin.';
      } else if (errorStr.contains('code: 133')) {
        return 'GATT hata kodu 133. Cihazı yeniden bağlayın.';
      } else {
        return 'Bluetooth hatası: $errorStr';
      }
    }
    return errorStr;
  }

  Future<void> _discoverServices() async {
    if (widget.bleDevice == null || !_bleConnected) return;

    _updateStatus('Servisler keşfediliyor...');

    try {
      _services = await widget.bleDevice!.discoverServices()
        .timeout(DISCOVER_TIMEOUT, onTimeout: () {
          throw TimeoutException('Servis keşfi zaman aşımı');
        });
      
      debugPrint("${_services!.length} servis keşfedildi");
      
      // Karakteristikleri bul
      await _findCharacteristics();
      
      // MTU ayarla
      await _negotiateMtu();
      
      setState(() {
        _servicesDiscovered = true;
        _canSend = _txCharacteristic != null;
        _canReceive = _rxCharacteristic != null;
        _status = 'Bluetooth Hazır!';
      });
      
      _showMessage('Bağlantı hazır!');
      
    } catch (e) {
      _updateStatus('Servis keşfi hatası: ${e.toString()}', isError: true);
      _showMessage('Servis keşfi başarısız', isError: true);
    }
  }

  Future<void> _findCharacteristics() async {
    BluetoothCharacteristic? txChar, rxChar;
    for (var service in _services!) {
      for (var char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        
        // TX karakteristiği (yazma)
        if ((char.properties.write || char.properties.writeWithoutResponse) &&
            (uuid.contains('ffe1') || uuid.contains('fff1') || 
             uuid.contains('2a00') || uuid.contains('2a01') ||
             uuid.contains('0000ffe1') || uuid.contains('0000fff1'))) {
          txChar = char;
          debugPrint("TX Karakteristik bulundu: ${char.uuid}");
        }
        
        // RX karakteristiği (okuma/notify)
        if ((char.properties.notify || char.properties.read || char.properties.indicate) &&
            (uuid.contains('ffe2') || uuid.contains('fff2') || 
             uuid.contains('2a02') || uuid.contains('2a03') ||
             uuid.contains('0000ffe2') || uuid.contains('0000fff2'))) {
          rxChar = char;
          debugPrint("RX Karakteristik bulundu: ${char.uuid}");
        }
      }
    }
    
    // Eğer standart UUID'ler bulunamazsa, ilk bulunan karakteristikleri kullan
    if (txChar == null && _services!.isNotEmpty) {
      for (var service in _services!) {
        for (var char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            txChar = char;
            break;
          }
        }
        if (txChar != null) break;
      }
    }
    
    if (rxChar == null && _services!.isNotEmpty) {
      for (var service in _services!) {
        for (var char in service.characteristics) {
          if (char.properties.notify || char.properties.read) {
            rxChar = char;
            break;
          }
        }
        if (rxChar != null) break;
      }
    }
    
    if (txChar == null || rxChar == null) {
      _updateStatus('Uygun karakteristik bulunamadı', isError: true);
      throw Exception('Uygun karakteristik bulunamadı');
    }
    
    _txCharacteristic = txChar;
    _rxCharacteristic = rxChar;
    
    // Notify aktif et
    if (_rxCharacteristic!.properties.notify || _rxCharacteristic!.properties.indicate) {
      await _rxCharacteristic!.setNotifyValue(true);
      debugPrint("Notify aktif edildi");
      
      _dataSubscription = _rxCharacteristic!.onValueReceived.listen(_handleIncomingData);
    }
  }

  Future<void> _negotiateMtu() async {
    try {
      final negotiatedMtu = await widget.bleDevice!.requestMtu(MAX_MTU);
      debugPrint("MTU ayarlandı: $negotiatedMtu");
    } catch (e) {
      debugPrint("MTU ayarlama hatası: $e");
    }
  }

  void _handleIncomingData(List<int> data) {
    try {
      debugPrint("Alınan veri: ${data.length} byte");
      
      // İlk 4 byte boyut bilgisi mi kontrol et
      if (_expectedSize == -1 && data.length >= 4) {
        final sizeBytes = Uint8List.fromList(data.sublist(0, 4));
        final byteData = ByteData.view(sizeBytes.buffer);
        _expectedSize = byteData.getUint32(0, Endian.little);
        debugPrint("Beklenen dosya boyutu: $_expectedSize bytes");
        
        // Boyut bilgisini aldıktan sonra kalan veriyi buffer'a ekle
        if (data.length > 4) {
          _receiveBuffer.addAll(data.sublist(4));
          _bytesTransferred = _receiveBuffer.length;
        }
      } else {
        // Normal veri
        _receiveBuffer.addAll(data);
        _bytesTransferred = _receiveBuffer.length;
      }
      
      // İlerlemeyi güncelle
      if (_expectedSize > 0) {
        final progress = _bytesTransferred / _expectedSize;
        _updateProgress(
          progress,
          'Alınıyor: ${BluetoothUtils.formatBytes(_bytesTransferred)} / ${BluetoothUtils.formatBytes(_expectedSize)}'
        );
        
        // Tüm veri alındı mı kontrol et
        if (_bytesTransferred >= _expectedSize) {
          _finalizeReceiving();
        }
      }
      
    } catch (e) {
      debugPrint("Incoming data error: $e");
      _updateStatus('Veri alma hatası', isError: true);
    }
  }

  void _finalizeReceiving() {
    if (_receiveCompleter != null && !_receiveCompleter!.isCompleted) {
      try {
        final data = Uint8List.fromList(_receiveBuffer);
        _receiveCompleter!.complete(data);
        
        _updateStatus('Alım tamamlandı!');
        _updateProgress(1.0, 'Alım tamamlandı!');
        _showMessage('✅ Veri başarıyla alındı!');
        
      } catch (e) {
        _receiveCompleter!.completeError(e);
      } finally {
        _resetReceivingState();
      }
    }
  }

  void _resetReceivingState() {
    setState(() {
      _receivingFile = false;
      _expectedSize = -1;
      _receiveBuffer.clear();
      _receiveCompleter = null;
      _isTransferring = false;
      _bytesTransferred = 0;
    });
  }

  Future<void> _sendBackup() async {
    if (!_isReadyForTransfer) {
      _showMessage('Önce bağlantı kurulmalı');
      return;
    }

    if (_isTransferring) {
      _showMessage('Zaten transfer işlemi devam ediyor');
      return;
    }

    try {
      _isTransferring = true;
      _resetProgress();
      _updateStatus('Yedek hazırlanıyor...');

      final backupPath = await BluetoothUtils.createBackupJsonFile();
      final file = File(backupPath);
      final bytes = await file.readAsBytes();
      final totalBytes = bytes.length;
      
      if (totalBytes > 5 * 1024 * 1024) { // 5MB limit
        throw Exception('Dosya çok büyük (Max: 5MB)');
      }
      
      _bytesTotal = totalBytes;
      _updateStatus('Yedek hazır: ${BluetoothUtils.formatBytes(totalBytes)}');
      _transferStartTime = DateTime.now();

      if (widget.isBLE && _txCharacteristic != null) {
        await _sendOverBLE(bytes);
      } else {
        if (!mounted) return;
        await WiFiTransferService.showWiFiTransferDialog(context, backupPath);
      }

    } catch (e) {
      _updateStatus('Gönderim hatası: ${e.toString()}', isError: true);
      _showMessage('Gönderim hatası: ${_getErrorMessage(e)}', isError: true);
    } finally {
      _isTransferring = false;
      _transferTimer?.cancel();
    }
  }

  Future<void> _sendOverBLE(Uint8List bytes) async {
    try {
      _updateStatus('Veri gönderiliyor...');
      
      // Önce dosya boyutunu gönder (4 byte - little endian)
      final sizeBytes = ByteData(4);
      sizeBytes.setUint32(0, bytes.length, Endian.little);
      await _writeWithRetry(sizeBytes.buffer.asUint8List());
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Veriyi chunk'lar halinde gönder
      int offset = 0;
      while (offset < bytes.length) {
        final chunkEnd = offset + CHUNK_SIZE < bytes.length ? offset + CHUNK_SIZE : bytes.length;
        final chunk = bytes.sublist(offset, chunkEnd);
        
        await _writeWithRetry(chunk);
        
        offset = chunkEnd;
        _bytesTransferred = offset;
        
        // İlerlemeyi güncelle
        final progress = offset / bytes.length;
        _updateProgress(
          progress,
          'Gönderiliyor: ${BluetoothUtils.formatBytes(offset)} / ${BluetoothUtils.formatBytes(bytes.length)}'
        );
        
        // Küçük bir gecikme
        await Future.delayed(TRANSFER_CHUNK_DELAY);
      }
      
      final duration = DateTime.now().difference(_transferStartTime!);
      _updateStatus('Gönderim tamamlandı! (${duration.inSeconds}s)');
      _showMessage('✅ Veri başarıyla gönderildi!');

    } catch (e) {
      debugPrint("BLE gönderim hatası: $e");
      rethrow;
    }
  }

  Future<void> _writeWithRetry(List<int> data, {int maxRetries = MAX_RETRY_COUNT}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (_txCharacteristic!.properties.writeWithoutResponse) {
          await _txCharacteristic!.write(data, withoutResponse: true);
        } else {
          await _txCharacteristic!.write(data);
        }
        return;
      } catch (e) {
        debugPrint("Yazma denemesi $attempt/$maxRetries başarısız: $e");
        
        if (attempt == maxRetries) {
          throw Exception('Yazma işlemi başarısız: ${_getErrorMessage(e)}');
        }
        
        await Future.delayed(Duration(milliseconds: 100 * attempt));
        
        // Bağlantıyı kontrol et
        if (!_bleConnected) {
          throw Exception('Bağlantı kesildi');
        }
      }
    }
  }

  Future<void> _receiveBackup() async {
    if (!_isReadyForTransfer) {
      _showMessage('Önce bağlantı kurulmalı');
      return;
    }

    if (_isTransferring) {
      _showMessage('Zaten transfer işlemi devam ediyor');
      return;
    }

    try {
      _isTransferring = true;
      _resetProgress();
      _resetReceivingState();
      
      _receiveCompleter = Completer<Uint8List>();
      _transferStartTime = DateTime.now();
      _updateStatus('Veri bekleniyor... Karşı taraftan gönderim başlatılmalı.');
      
      // Zaman aşımı kontrolü
      _transferTimer = Timer(TRANSFER_TIMEOUT, () {
        if (!_receiveCompleter!.isCompleted) {
          _receiveCompleter!.completeError(TimeoutException('Veri alma zaman aşımı'));
        }
      });

      final data = await _receiveCompleter!.future;
      await _processReceivedData(data);
      
    } on TimeoutException catch (e) {
      _updateStatus('Zaman aşımı: ${e.toString()}', isError: true);
      _showMessage('Veri alma zaman aşımı', isError: true);
    } catch (e) {
      _updateStatus('Alım hatası: ${e.toString()}', isError: true);
      _showMessage('Alım hatası: ${_getErrorMessage(e)}', isError: true);
    } finally {
      _isTransferring = false;
      _transferTimer?.cancel();
    }
  }

  Future<void> _processReceivedData(Uint8List data) async {
    try {
      // JSON doğrulama
      final jsonStr = utf8.decode(data);
      final jsonData = json.decode(jsonStr);
      
      // Temel alanları kontrol et
      final requiredFields = ['meta', 'cariler', 'sutler', 'yemler'];
      for (var field in requiredFields) {
        if (!jsonData.containsKey(field)) {
          throw Exception('Geçersiz JSON: $field alanı eksik');
        }
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'yedek_$timestamp.json';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(data);

      final fileSize = await file.length();
      if (!mounted) return;
      _showMessage('✅ ${BluetoothUtils.formatBytes(fileSize)} boyutunda dosya alındı');

      final shouldApply = await _showApplyDialog(file.path);
      if (shouldApply == true) {
        final ozet = await BluetoothUtils.applyBackupJsonFile(file.path);
        if (mounted) veriDegistiBildir(context);
        _showMessage('✅ Yedek uygulandı: ${ozet.toplam} kayıt');
      }
      
    } catch (e) {
      throw Exception('Veri işleme hatası: ${e.toString()}');
    }
  }

  bool get _isReadyForTransfer {
    if (widget.isBLE) {
      return _bleConnected && _servicesDiscovered && _canSend && _canReceive;
    } else {
      return _classicConnected && _servicesDiscovered;
    }
  }

  void _resetProgress() {
    setState(() {
      _progress = 0.0;
      _bytesTotal = 0;
      _bytesTransferred = 0;
    });
  }

  void _updateProgress(double progress, String status) {
    setState(() {
      _progress = progress;
      _status = status;
    });
  }

  void _updateStatus(String status, {bool isError = false, bool connecting = false}) {
    setState(() {
      _status = status;
      _connecting = connecting;
    });
    if (isError) {
      debugPrint("Hata: $status");
    }
  }

  Future<bool?> _showApplyDialog(String filePath) async {
    final file = File(filePath);
    final fileSize = await file.length();
    if (!mounted) return null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Yedek Uygulama'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gelen yedek veritabanına uygulanılsın mı?'),
            const SizedBox(height: 10),
            Text('Dosya: ${p.basename(filePath)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Boyut: ${BluetoothUtils.formatBytes(fileSize)}'),
            const SizedBox(height: 10),
            const Text('⚠️ Uyarı: Mevcut verilerin üzerine yazılacaktır.', 
                 style: TextStyle(color: Colors.orange)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('VAZGEÇ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('UYGULA'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Tamam',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isBLE 
            ? 'Bluetooth Aktarım - ${widget.bleDevice?.platformName ?? "Cihaz"}'
            : 'Wi-Fi Aktarım'
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          if (_isTransferring)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Bağlantı durumu
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _bleConnected ? Colors.green[50] : 
                       _connecting ? Colors.blue[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _bleConnected ? Colors.green : 
                         _connecting ? Colors.blue : Colors.red,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _bleConnected ? Icons.bluetooth_connected : 
                    _connecting ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                    color: _bleConnected ? Colors.green : 
                           _connecting ? Colors.blue : Colors.red,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isBLE ? (widget.bleDevice?.platformName ?? 'BLE Cihaz') : 'Wi-Fi Cihaz',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: 16
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _status,
                          style: TextStyle(
                            color: _bleConnected ? Colors.green[800] : 
                                   _connecting ? Colors.blue[800] : Colors.red[800],
                            fontSize: 14,
                          ),
                        ),
                        if (_servicesDiscovered)
                          Text(
                            '${_canSend ? '✓ Gönderebilir' : '✗ Gönderemez'} • '
                            '${_canReceive ? '✓ Alabilir' : '✗ Alamaz'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_connecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // İlerleme göstergesi
            if (_isTransferring)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(_progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      if (_transferStartTime != null)
                        Text(
                          '${DateTime.now().difference(_transferStartTime!).inSeconds}s',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${BluetoothUtils.formatBytes(_bytesTransferred)} / '
                    '${BluetoothUtils.formatBytes(_bytesTotal)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              )
            else
              Text(
                _status,
                style: TextStyle(
                  fontSize: 16,
                  color: _status.contains('Hata') ? Colors.red : 
                         _status.contains('Hazır') ? Colors.green : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            
            const SizedBox(height: 30),
            
            // Butonlar
            Column(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text(
                    'VERİYİ GÖNDER', 
                    style: TextStyle(fontWeight: FontWeight.bold)
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(55),
                    backgroundColor: _canSend || !widget.isBLE ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: (_isReadyForTransfer && !_isTransferring) 
                      ? _sendBackup 
                      : null,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download_rounded),
                  label: const Text(
                    'VERİYİ AL', 
                    style: TextStyle(fontWeight: FontWeight.bold)
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(55),
                    backgroundColor: _canReceive ? Colors.blue : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: (_isReadyForTransfer && _canReceive && !_isTransferring) 
                      ? _receiveBackup 
                      : null,
                ),
              ],
            ),
            
            const Spacer(),
            
            // Hata giderme ipuçları
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 4),
                      const Text(
                        'Bluetooth Hata Giderme', 
                        style: TextStyle(fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._buildTroubleshootingTips(),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('GERİ DÖN'),
              onPressed: () {
                _cleanup();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTroubleshootingTips() {
    final tips = [
      '• Her iki cihazda Bluetooth açık olmalı',
      '• Cihazlar birbirine yakın olmalı (10m)',
      '• Samsung cihazlarda bağlantı süresi uzun olabilir',
      '• Eski bağlantıları cihaz ayarlarından silin',
      '• Uygulamayı yeniden başlatmayı deneyin',
      '• Wi-Fi kullanmak için "VERİYİ GÖNDER" butonunu kullanın',
    ];
    
    return tips.map((tip) => Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(tip, style: const TextStyle(fontSize: 12)),
    )).toList();
  }
}