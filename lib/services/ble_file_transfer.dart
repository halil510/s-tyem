import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

typedef WriteFunc = Future<void> Function(List<int> chunk, {bool withoutResponse});
typedef GetMtuFunc = Future<int?> Function();

class BleFileTransfer {
  static const int _defaultChunkSize = 20;
  static const int _maxMtu = 512;

  /// Send bytes over BLE
  static Future<void> sendFile({
    required Uint8List data,
    required WriteFunc write,
    GetMtuFunc? getMtu,
    bool supportsWriteWithoutResponse = false,
    void Function(int sent, int total)? onProgress,
    Stream<void>? cancelToken,
    Duration interChunkDelay = const Duration(milliseconds: 50),
  }) async {
    if (data.isEmpty) throw ArgumentError('data must be non-empty');

    final total = data.length;
    int chunkSize = _defaultChunkSize;
    
    try {
      final mtu = await (getMtu?.call() ?? Future.value(null));
      if (mtu != null && mtu > 23) {
        chunkSize = (mtu - 3).clamp(20, _maxMtu);
      }
    } catch (e) {
      print("MTU alma hatası: $e");
    }

    // Header gönder
    final header = 'FILE:$total\n';
    await write(utf8.encode(header), withoutResponse: supportsWriteWithoutResponse);
    await Future.delayed(const Duration(milliseconds: 100));

    int sent = 0;
    while (sent < total) {
      if (cancelToken != null) {
        try {
          await cancelToken.first.timeout(const Duration(milliseconds: 10));
        } catch (_) {}
      }

      final end = (sent + chunkSize) > total ? total : sent + chunkSize;
      final chunk = data.sublist(sent, end);
      await write(chunk, withoutResponse: supportsWriteWithoutResponse);
      sent = end;
      onProgress?.call(sent, total);

      if (interChunkDelay.inMilliseconds > 0) {
        await Future.delayed(interChunkDelay);
      }
    }

    // End marker gönder
    await write(utf8.encode('END\n'), withoutResponse: supportsWriteWithoutResponse);
  }

  /// Receive file from BLE stream
  static Future<Uint8List> receiveFile({
    required Stream<List<int>> stream,
    void Function(int received, int total)? onProgress,
    Stream<void>? cancelToken,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final completer = Completer<Uint8List>();
    final buffer = <int>[];
    int expectedSize = -1;
    bool headerReceived = false;
    bool transferComplete = false;

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Alım zaman aşımı'));
      }
    });

    StreamSubscription<List<int>>? subscription;
    
    subscription = stream.listen(
      (data) {
        if (completer.isCompleted || transferComplete) return;

        try {
          if (!headerReceived) {
            buffer.addAll(data);
            final bufferStr = utf8.decode(buffer, allowMalformed: true);
            
            if (bufferStr.contains('FILE:')) {
              final lines = bufferStr.split('\n');
              if (lines.isNotEmpty) {
                final header = lines[0];
                final sizeStr = header.substring(5).trim();
                expectedSize = int.tryParse(sizeStr) ?? -1;
                
                if (expectedSize > 0) {
                  headerReceived = true;
                  buffer.clear();
                  
                  // Header'dan sonraki veriyi ekle
                  if (bufferStr.length > header.length + 1) {
                    final remaining = bufferStr.substring(header.length + 1);
                    buffer.addAll(utf8.encode(remaining));
                  }
                  
                  onProgress?.call(buffer.length, expectedSize);
                }
              }
            }
          } else {
            buffer.addAll(data);
            onProgress?.call(buffer.length, expectedSize);
          }

          // END kontrolü
          if (buffer.length >= 4) {
            final lastBytes = buffer.sublist(buffer.length - 4);
            if (utf8.decode(lastBytes) == 'END\n') {
              transferComplete = true;
              buffer.removeRange(buffer.length - 4, buffer.length);
              
              if (expectedSize != -1 && buffer.length != expectedSize) {
                print("Uyarı: Beklenen boyut farklı: $expectedSize != ${buffer.length}");
              }
              
              completer.complete(Uint8List.fromList(buffer));
              timer.cancel();
              subscription?.cancel();
            }
          }

          // Beklenen boyuta ulaştık mı?
          if (headerReceived && expectedSize != -1 && buffer.length >= expectedSize) {
            if (!transferComplete) {
              transferComplete = true;
              completer.complete(Uint8List.fromList(buffer));
              timer.cancel();
              subscription?.cancel();
            }
          }
        } catch (e) {
          completer.completeError(e);
          timer.cancel();
          subscription?.cancel();
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
        timer.cancel();
      },
      onDone: () {
        if (!completer.isCompleted && !transferComplete) {
          completer.completeError(Exception('Bağlantı kesildi'));
        }
        timer.cancel();
      },
    );

    // Cancel token
    if (cancelToken != null) {
      cancelToken.listen((_) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('İptal edildi'));
          timer.cancel();
          subscription?.cancel();
        }
      });
    }

    return completer.future;
  }
}