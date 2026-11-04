import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'bluetooth_utils.dart';

class WiFiTransferService {
  static HttpServer? _server;
  static bool _serverRunning = false;

  static Future<void> showWiFiTransferDialog(BuildContext context, String filePath) async {
    final localIP = await _getLocalIP();
    if (!context.mounted) return;
    if (localIP.isEmpty) {
      _showError(context, 'IP adresi alınamadı. Wi-Fi bağlı olduğunuzdan emin olun.');
      return;
    }
    
    final url = 'http://$localIP:8080/download';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Wi-Fi İle Paylaş'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Diğer cihazda bu QR kodu tarayın veya linke tıklayın:'),
              const SizedBox(height: 20),
              QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: () {
                  // Clipboard'a kopyala
                  // TODO: Clipboard işlemi eklenebilir
                },
                child: SelectableText(
                  url,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Adımlar:\n'
                '1. Her iki cihaz da aynı Wi-Fi ağında olmalı\n'
                '2. Diğer cihazda tarayıcıyı açın\n'
                '3. Yukarıdaki QR kodu tarayın veya URL\'yi girin\n'
                '4. Dosya otomatik indirilecek\n'
                '5. İşlem bitince "Sunucuyu Durdur" butonuna basın',
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              StreamBuilder<bool>(
                stream: _serverStatusStream(),
                initialData: _serverRunning,
                builder: (context, snapshot) {
                  return Column(
                    children: [
                      if (snapshot.data == true)
                        const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.green, size: 12),
                            SizedBox(width: 8),
                            Text('Sunucu çalışıyor', style: TextStyle(color: Colors.green)),
                          ],
                        )
                      else
                        const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.red, size: 12),
                            SizedBox(width: 8),
                            Text('Sunucu durdu', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _stopServer();
              Navigator.pop(context);
            },
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: _serverRunning ? null : () async {
              Navigator.pop(context);
              await _startHttpServer(filePath, context);
              _showSuccess(context, 'Sunucu başlatıldı! Diğer cihazdan bağlanabilirsiniz.');
            },
            child: Text(_serverRunning ? 'Sunucu Çalışıyor' : 'Sunucuyu Başlat'),
          ),
          if (_serverRunning)
            TextButton(
              onPressed: () {
                _stopServer();
                _showInfo(context, 'Sunucu durduruldu.');
              },
              child: const Text('Sunucuyu Durdur', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  static Stream<bool> _serverStatusStream() async* {
    while (true) {
      yield _serverRunning;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  static Future<String> _getLocalIP() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && 
              !addr.address.startsWith('127.') &&
              !addr.address.startsWith('169.254.')) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print("IP alma hatası: $e");
    }
    return '';
  }

  static Future<void> _startHttpServer(String filePath, BuildContext context) async {
    try {
      _stopServer(); // Önceki sunucuyu durdur
      
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _server = server;
      _serverRunning = true;
      
      print('HTTP sunucusu başlatıldı: ${server.address}:${server.port}');

      server.listen((request) async {
        try {
          if (request.uri.path == '/download') {
            final file = File(filePath);
            if (await file.exists()) {
              request.response.headers.contentType = ContentType('application', 'json');
              request.response.headers.add('Content-Disposition', 
                'attachment; filename="sut_yem_yedek_${DateTime.now().millisecondsSinceEpoch}.json"');
              
              await file.openRead().pipe(request.response);
              
              // İndirme tamamlandı mesajı göster
              _showSuccess(context, 'Dosya indirildi!');
            } else {
              request.response.statusCode = HttpStatus.notFound;
              request.response.write('Dosya bulunamadı');
              await request.response.close();
            }
          } else if (request.uri.path == '/status') {
            request.response.write(json.encode({'status': 'running'}));
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        } catch (e) {
          print('Request error: $e');
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        }
      }, onError: (e) {
        print('Server error: $e');
        _serverRunning = false;
      }, onDone: () {
        print('Server stopped');
        _serverRunning = false;
      });

      // 10 dakika sonra otomatik durdur
      Timer(const Duration(minutes: 10), () {
        _stopServer();
        _showInfo(context, 'Sunucu otomatik durduruldu.');
      });

    } catch (e) {
      print('HTTP sunucusu hatası: $e');
      _showError(context, 'Sunucu başlatılamadı: $e');
      _serverRunning = false;
    }
  }

  static void _stopServer() {
    if (_server != null) {
      try {
        _server!.close();
        _server = null;
        _serverRunning = false;
        print('HTTP sunucusu durduruldu');
      } catch (e) {
        print('Server stop error: $e');
      }
    }
  }

  static Future<void> sendViaWiFiDirect(BuildContext context) async {
    try {
      // Önceki sunucuyu durdur
      _stopServer();
      
      // Tam yedek (tüm iş tabloları). Eskiden burada yedek HİÇ
      // oluşturulmuyordu; olmayan bir dosya paylaşılıp karşı taraf
      // "Dosya bulunamadı" alıyordu.
      final backupPath = await BluetoothUtils.createBackupJsonFile();
      if (!context.mounted) return;
      await showWiFiTransferDialog(context, backupPath);
    } catch (e) {
      _showError(context, 'Wi-Fi transfer hatası: $e');
    }
  }

  static void _showError(BuildContext context, String message) {
    if (!context.mounted) return; // ekran kapandıysa mesaj gösterme (çökme)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  static void _showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void _showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}