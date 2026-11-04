import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/database/app_database.dart';
import '../data/repositories/veri_yonetimi_repository.dart';
import '../data/yedek/yedek_servisi.dart';

/// Bluetooth / Wi-Fi aktarımı için yedek dosyası oluşturma ve uygulama.
///
/// Asıl iş [YedekServisi]'ndedir: tüm iş tabloları (cariler, süt, yem,
/// ödeme/tahsilat, fiyatlar) yedeklenir ve geri yükleme tek
/// transaction'dır — hata olursa mevcut veriler olduğu gibi kalır.
class BluetoothUtils {
  /// Aktarılabilecek en büyük yedek boyutu.
  static const maksimumYedekBayt = 25 * 1024 * 1024;

  static Future<String> createBackupJsonFile() async {
    final repo = VeriYonetimiRepository(await AppDatabase.instance.database);
    final bytes = utf8.encode(await repo.yedekJson());

    if (bytes.length > maksimumYedekBayt) {
      throw Exception('Yedek dosyası çok büyük (${formatBytes(bytes.length)}).');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/sut_yem_yedek_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsBytes(bytes, flush: true);

    if (kDebugMode) debugPrint('Yedek oluşturuldu: ${file.path} (${formatBytes(bytes.length)})');
    return file.path;
  }

  /// Gelen yedeği bu cihazın verilerinin YERİNE koyar (cihazdan cihaza
  /// aktarım). Eski biçimli (ödeme/fiyat içermeyen) yedeklerde
  /// [YedekHatasi] fırlatır ve hiçbir şeyi silmez.
  static Future<YedekOzeti> applyBackupJsonFile(String path) async {
    final veri = YedekServisi.coz(await File(path).readAsString());
    final repo = VeriYonetimiRepository(await AppDatabase.instance.database);
    return repo.yedekYukle(veri, tamamenDegistir: true);
  }

  static bool validateBackupData(String jsonString) {
    try {
      YedekServisi.coz(jsonString);
      return true;
    } on YedekHatasi {
      return false;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  static Future<void> logBluetoothError(String error, String context) async {
    try {
      final dir = await getTemporaryDirectory();
      final logFile = File('${dir.path}/bluetooth_errors.txt');
      final timestamp = DateTime.now().toIso8601String();
      
      final logEntry = '''
[$timestamp] - $context
Hata: $error
----------------------------------------
''';
      
      await logFile.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      debugPrint("Loglama hatası: $e");
    }
  }
}