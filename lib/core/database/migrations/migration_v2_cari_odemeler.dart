import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v2 — Cari bazlı hesap hareketleri tablosu (`islem_turu` ile
/// ayrıştırılır: 'sut'/'tahsilat' → kredi/alacak, 'yem'/'odeme' →
/// borç — bkz. CariOdemeRepository doc yorumu, güncel iş mantığı
/// orada tanımlıdır). Şema burada kurulduğunda tablo yalnızca 'alim'
/// ve 'odeme' değerlerini biliyordu; sonraki turlarda semantik
/// düzeltilip yeni değerler eklendi, ama sütun adları (toplam_tutar,
/// kalan_tutar vb.) geriye dönük uyumluluk için değişmedi.
class MigrationV2CariOdemeler extends Migration {
  @override
  int get version => 2;

  @override
  String get description => 'cari_odemeler tablosu (alım/ödeme hareketleri)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('cari_odemeler')
        .id()
        .integer('cari_id', notNull: true)
        .text('tarih', notNull: true)
        .text('islem_turu', notNull: true) // 'alim' | 'odeme'
        .real('miktar', notNull: true, defaultValue: '0')
        .real('birim_fiyat', notNull: true, defaultValue: '0')
        .real('toplam_tutar', notNull: true, defaultValue: '0')
        .real('odenen_tutar', defaultValue: '0')
        .real('kalan_tutar', defaultValue: '0')
        .text('aciklama')
        .timestamps()
        .foreignKey('cari_id', refTable: 'cariler')
        .create(db);
  }
}
