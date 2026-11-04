import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/migration_runner.dart';

/// Bir migration (şema güncellemesi) başarısız oldu. Veritabanı dosyasına
/// DOKUNULMADI: veriler yerinde, şema son başarılı sürümde duruyor.
/// Bir sonraki açılışta aynı migration yeniden denenir.
class VeritabaniGuncellemeHatasi implements Exception {
  final Object neden;
  final StackTrace? yigin;
  final int mevcutSurum;
  final int hedefSurum;

  const VeritabaniGuncellemeHatasi(
    this.neden, {
    this.yigin,
    required this.mevcutSurum,
    required this.hedefSurum,
  });

  @override
  String toString() =>
      'Veritabanı güncellemesi başarısız (v$mevcutSurum → v$hedefSurum): $neden';
}

/// Veritabanı açılamadı ve bunun nedeni dosya bozulması DEĞİL
/// (ör. dosya kilitli, disk dolu, izin yok). Dosyaya dokunulmadı.
class VeritabaniAcilisHatasi implements Exception {
  final Object neden;
  final StackTrace? yigin;
  const VeritabaniAcilisHatasi(this.neden, {this.yigin});

  @override
  String toString() => 'Veritabanı açılamadı: $neden';
}

/// ─────────────────────────────────────────────────────────────
/// APP DATABASE
/// ─────────────────────────────────────────────────────────────
///
/// Veritabanını açar ve [MigrationRunner] ile şemayı günceller.
///
/// VERİ GÜVENLİĞİ KURALI: Dosya yalnızca **gerçekten bozuksa**
/// (SQLite "malformed" / "not a database" ya da `PRAGMA quick_check`
/// başarısız) kenara alınıp yeni boş veritabanı kurulur; eski dosya
/// silinmez, [kurtarmaYedegi] yoluna taşınır ve kullanıcıya gösterilir.
/// Migration hatası ya da başka bir açılış hatası veritabanına ASLA
/// dokunmaz — [VeritabaniGuncellemeHatasi] / [VeritabaniAcilisHatasi]
/// fırlatılır.
class AppDatabase {
  AppDatabase._internal()
      : _factory = null,
        _sabitKlasor = null,
        _migrationRunner = MigrationRunner();

  /// Testler için: gerçek dosya sistemi üzerinde, verilen fabrika ve
  /// klasörle çalışan bağımsız bir örnek.
  @visibleForTesting
  AppDatabase.test({
    required DatabaseFactory factory,
    required String klasor,
    MigrationRunner? migrationRunner,
  })  : _factory = factory,
        _sabitKlasor = klasor,
        _migrationRunner = migrationRunner ?? MigrationRunner();

  static final AppDatabase instance = AppDatabase._internal();

  static const String dbAdi = 'sut_yem.db';

  final DatabaseFactory? _factory;
  final String? _sabitKlasor;
  final MigrationRunner _migrationRunner;

  Database? _database;
  Future<Database>? _acilis;

  /// Bu oturumda bozuk dosya kenara alındıysa, eski dosyanın yeni yolu.
  /// Kullanıcıya bir kez gösterildikten sonra [kurtarmaBildirildi] çağrılır.
  String? get kurtarmaYedegi => _kurtarmaYedegi;
  String? _kurtarmaYedegi;
  void kurtarmaBildirildi() => _kurtarmaYedegi = null;

  DatabaseFactory get _fabrika => _factory ?? databaseFactory;

  Future<Database> get database {
    final db = _database;
    if (db != null && db.isOpen) return Future.value(db);
    // Aynı anda gelen çağrılar tek bir açılışı paylaşır; hata olursa
    // bir sonraki çağrı yeniden dener.
    return _acilis ??= _ac().then((db) {
      _database = db;
      return db;
    }).whenComplete(() => _acilis = null);
  }

  Future<String> _yol() async {
    final klasor = _sabitKlasor ?? await getDatabasesPath();
    try {
      await Directory(klasor).create(recursive: true);
    } catch (_) {
      // Dizin zaten var olabilir.
    }
    return join(klasor, dbAdi);
  }

  Future<Database> _ac() async {
    final yol = await _yol();

    Database db;
    try {
      db = await _dosyayiAc(yol);
      await _butunlukDenetle(db);
    } catch (e, stack) {
      if (!bozulmaHatasiMi(e)) {
        throw VeritabaniAcilisHatasi(e, yigin: stack);
      }
      if (kDebugMode) debugPrint('[AppDatabase] Dosya bozuk, kenara alınıyor: $e');
      await _bozukDosyayiKenaraAl(yol);
      db = await _dosyayiAc(yol);
    }

    await _guncelle(db);
    return db;
  }

  Future<Database> _dosyayiAc(String yol) => _fabrika.openDatabase(
        yol,
        options: OpenDatabaseOptions(
          // Sürüm yönetimi sqflite'ın onUpgrade'ine değil MigrationRunner'a
          // aittir (PRAGMA user_version).
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );

  /// Bozuksa [_BozukDosya] fırlatır; başka hatalar olduğu gibi geçer.
  Future<void> _butunlukDenetle(Database db) async {
    List<Map<String, Object?>> sonuc;
    try {
      sonuc = await db.rawQuery('PRAGMA quick_check');
    } catch (_) {
      await db.close();
      rethrow;
    }
    final ilk = sonuc.isEmpty ? null : sonuc.first.values.first?.toString();
    if (ilk != 'ok') {
      await db.close();
      throw _BozukDosya('quick_check: $ilk');
    }
  }

  Future<void> _guncelle(Database db) async {
    final mevcut = await _migrationRunner.currentVersion(db);
    try {
      await _migrationRunner.run(db);
    } catch (e, stack) {
      await db.close();
      throw VeritabaniGuncellemeHatasi(
        e,
        yigin: stack,
        mevcutSurum: mevcut,
        hedefSurum: MigrationRunner.targetVersion,
      );
    }
  }

  /// Bozuk dosyayı (ve -wal/-shm/-journal eklerini) silmeden yeniden
  /// adlandırır. Yeniden adlandırma başarısız olursa yeni veritabanı
  /// KURULMAZ — eski dosyanın üzerine asla yazılmaz.
  Future<void> _bozukDosyayiKenaraAl(String yol) async {
    final damga = DateTime.now().millisecondsSinceEpoch;
    final hedef = join(dirname(yol), 'sut_yem_bozuk_$damga.db');
    try {
      final ana = File(yol);
      if (await ana.exists()) await ana.rename(hedef);
      for (final ek in const ['-wal', '-shm', '-journal']) {
        final f = File('$yol$ek');
        if (await f.exists()) await f.rename('$hedef$ek');
      }
    } catch (e, stack) {
      throw VeritabaniAcilisHatasi(
        'Bozuk veritabanı kenara alınamadı, işlem durduruldu: $e',
        yigin: stack,
      );
    }
    _kurtarmaYedegi = hedef;
  }

  /// Uygulanan migration geçmişini döner (ayarlar/teşhis ekranında
  /// gösterilebilir).
  Future<List<Map<String, Object?>>> migrationHistory() async {
    final db = await database;
    return _migrationRunner.history(db);
  }

  int get schemaVersion => MigrationRunner.targetVersion;

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// SQLite'ın dosya bozulmasını bildiren hataları (SQLITE_CORRUPT=11,
  /// SQLITE_NOTADB=26) diğerlerinden (kilit, disk dolu, izin) ayırır.
  @visibleForTesting
  static bool bozulmaHatasiMi(Object e) {
    if (e is _BozukDosya) return true;
    if (e is! DatabaseException) return false;
    final m = e.toString().toLowerCase();
    return m.contains('malformed') ||
        m.contains('not a database') ||
        m.contains('corrupt') ||
        RegExp(r'code (11|26)\b').hasMatch(m);
  }
}

class _BozukDosya implements Exception {
  final String detay;
  const _BozukDosya(this.detay);
  @override
  String toString() => 'Bozuk veritabanı dosyası ($detay)';
}
