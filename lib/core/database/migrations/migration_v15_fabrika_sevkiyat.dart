import 'package:sqflite/sqflite.dart';

import '../table_builder.dart';
import 'migration.dart';
import 'migration_v13_senkron.dart';

/// v15 — TANK, FABRİKAYA SEVKİYAT ve FABRİKA CARİ HESABI.
///
/// - `fabrikalar`: sütün teslim edildiği fabrikalar (birden çok olabilir).
/// - `sevkiyatlar`: fabrikaya her teslim bir satır (günde birden çok olabilir).
///   Tutar saklanmaz: `kg × birim_fiyat` (satır bazında kuruşa yuvarlanır) canlı hesaplanır;
///   fabrika fiyatı sonradan açıklarsa `birim_fiyat` 0 girilip sonra uygulanabilir.
/// - `fabrika_hareketleri`: fabrikadan alınan ödeme ('tahsilat'), fabrikanın kestiği tutar
///   ('kesinti': kalite, nakliye…), fabrikanın eklediği tutar ('ek': prim, fark).
///   Fabrika bakiyesi = sevk tutarı + ek − tahsilat − kesinti (> 0: fabrika bize borçlu).
/// - `tank_sayimlari`: gün sonunda tankta kalan süt (günde TEK satır). Fire hesabında
///   ertesi güne kalan süt kayıp sayılmasın diye.
///
/// Fabrika silinirken hareketi varsa veritabanı izin vermez (RESTRICT): para kaydı
/// sessizce silinmesin. Bu tablolar üretici hakedişini etkilemediği için kapalı dönem
/// kilidi YOKTUR (fabrika fiyatı çoğu zaman ay kapandıktan sonra açıklanır); her yazma
/// denetim kaydına (islem_gecmisi) geçer.
class MigrationV15FabrikaSevkiyat extends Migration {
  @override
  int get version => 15;

  @override
  String get description => 'fabrikalar + sevkiyatlar + fabrika_hareketleri + tank_sayimlari';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('fabrikalar')
        .id()
        .text('ad', notNull: true)
        .text('telefon')
        .text('adres')
        .text('not_metni')
        .boolean('aktif', defaultValue: true)
        .text('uuid')
        .timestamps()
        .create(db);

    await TableBuilder('sevkiyatlar')
        .id()
        .integer('fabrika_id', notNull: true)
        .text('tarih', notNull: true) // 'yyyy-MM-dd'
        .text('saat') // 'HH:mm' (isteğe bağlı)
        .real('kg', notNull: true)
        .real('birim_fiyat') // ₺/kg; 0 = fiyat henüz belli değil
        .text('fis_no')
        .text('plaka')
        .text('aciklama')
        .text('uuid')
        .timestamps()
        .foreignKey('fabrika_id', refTable: 'fabrikalar', onDelete: 'RESTRICT')
        .create(db);

    await TableBuilder('fabrika_hareketleri')
        .id()
        .integer('fabrika_id', notNull: true)
        .text('tarih', notNull: true) // 'yyyy-MM-dd'
        .raw("tur TEXT NOT NULL CHECK (tur IN ('tahsilat', 'kesinti', 'ek'))")
        .real('tutar', notNull: true)
        .text('aciklama')
        .text('uuid')
        .timestamps()
        .foreignKey('fabrika_id', refTable: 'fabrikalar', onDelete: 'RESTRICT')
        .create(db);

    await TableBuilder('tank_sayimlari')
        .id()
        .text('tarih', notNull: true) // 'yyyy-MM-dd'
        .real('kalan_kg', notNull: true)
        .text('aciklama')
        .timestamps()
        .unique(['tarih'])
        .create(db);

    for (final t in ['fabrikalar', 'sevkiyatlar', 'fabrika_hareketleri']) {
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_${t}_uuid ON $t (uuid)');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sevkiyatlar_tarih ON sevkiyatlar (tarih)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sevkiyatlar_fabrika ON sevkiyatlar (fabrika_id, tarih)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fabrika_hareketleri_fabrika ON fabrika_hareketleri (fabrika_id, tarih)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_fabrika_hareketleri_tarih ON fabrika_hareketleri (tarih)');

    // Çoklu cihaz: yeni tablolar senk_tablolari.dart listesinde; tetikleyiciler yeniden kurulur.
    await senkTetikleyicileriKur(db);

    // KARIŞIK SÜRÜM: bu telefon eski sürümdeyken başka telefonun fabrika/sevkiyat kayıtlarını
    // aldıysa, bilmediği tablo olduğu için ATTI ama okuma sayacı ilerledi → güncellense de bir
    // daha çekmezdi. (1) Okuma sayaçları sıfırlanır: bulut ve ana cihazdan her şey bir kez yeniden
    // alınır (eldekiler zamanı aynı olduğundan atlanır). (2) Bu telefon yerel ağda ANA cihazsa
    // nesli değişir: bağlı telefonlar ellerindekini bir kez yeniden gönderir (yedeğe dönüşteki yol).
    await db.rawUpdate('UPDATE senk_kanallar SET son_cekilen = 0');
    await db.rawInsert("INSERT OR REPLACE INTO senk_ayarlar (anahtar, deger) VALUES ('taban_nesil', ?)",
        [DateTime.now().toUtc().toIso8601String()]);
  }
}
