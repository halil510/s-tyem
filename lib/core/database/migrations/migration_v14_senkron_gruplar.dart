import 'package:sqflite/sqflite.dart';

import '../../../senkron/senk_tablolari.dart';
import 'migration.dart';
import 'migration_v13_senkron.dart';

/// v14: Çoklu cihaz derin denetiminin (2026-11-12) şema düzeltmeleri.
///  • Gruplu birleşme: cari_fiyatlar (sut_zaman, yem_zaman), cariler (kart_zaman, rota_zaman,
///    durum_zaman). Satır bütünüyle ezilmez: Yem Fiyatı ekranı başka telefonun süt fiyatını,
///    rota kaydı başka telefondaki telefon düzeltmesini / "pasife al"ı geri almaz.
///  • senk_gunluk.tz: silmenin GERÇEK zamanı (mezar taşı). Silme yeniden gönderildiğinde
///    (ör. yankıyla diriltilen satıra karşı) zamanı korunur; silmeden eski değişiklik satırı
///    geri getiremez, silmeden yeni olan kalır.
///  • Tetikleyiciler yeniden kurulur: CASCADE ile silinen çocuklar (süt, fiyat, hakediş)
///    ebeveyn silinmeden ÖNCE doğru anahtarla günlüğe yazılır (önceden "|tarih" yazılıyordu).
/// Mevcut satırların grup zamanları boş kalır (= en eski): ilk gerçek değişiklik kazanır.
class MigrationV14SenkronGruplar extends Migration {
  @override
  int get version => 14;

  @override
  String get description => 'çoklu cihaz: gruplu birleşme, silme zamanı, CASCADE günlük düzeltmesi';

  @override
  Future<void> up(DatabaseExecutor db) async {
    Future<Set<Object?>> kolonlar(String t) async => (await db.rawQuery('PRAGMA table_info($t)')).map((c) => c['name']).toSet();
    for (final e in alanGruplari.entries) {
      final k = await kolonlar(e.key);
      for (final z in e.value.keys) {
        if (!k.contains(z)) await db.execute('ALTER TABLE ${e.key} ADD COLUMN $z TEXT');
      }
    }
    if (!(await kolonlar('senk_gunluk')).contains('tz')) await db.execute('ALTER TABLE senk_gunluk ADD COLUMN tz TEXT');
    await senkTetikleyicileriKur(db);
  }
}
