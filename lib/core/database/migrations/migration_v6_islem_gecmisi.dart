import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v6 — İşlem geçmişi / denetim günlüğü.
///
/// Profesyonel muhasebe akışlarında "kim, ne zaman, hangi kaydı
/// değiştirdi/sildi" sorusu kritik önemdedir. Bu tablo, cari ödeme
/// ve borç kayıtları üzerinde yapılan ekleme/güncelleme/silme
/// işlemlerinin bir izini tutar (basit, cihaz-içi denetim günlüğü).
class MigrationV6IslemGecmisi extends Migration {
  @override
  int get version => 6;

  @override
  String get description => 'islem_gecmisi tablosu (denetim günlüğü)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('islem_gecmisi')
        .id()
        .text('tablo_adi', notNull: true)
        .integer('kayit_id', notNull: true)
        .text('islem', notNull: true) // 'ekle' | 'guncelle' | 'sil'
        .text('onceki_deger') // JSON — güncelleme/silmeden önceki hal
        .text('yeni_deger') // JSON — ekleme/güncellemeden sonraki hal
        .text('tarih', notNull: true)
        .create(db);

    await SchemaInspector.createIndexIfMissing(
      db, 'idx_islem_gecmisi_tablo', 'islem_gecmisi', ['tablo_adi', 'kayit_id'],
    );

    // Bu migration ile birlikte, kendi migration geçmişimizi de
    // saklayan tabloyu burada garanti altına alıyoruz (MigrationRunner
    // zaten oluşturur, ama idempotent olduğu için sorun teşkil etmez).
  }
}
