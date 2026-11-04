import 'package:sqflite/sqflite.dart';
import '../table_builder.dart';
import 'migration.dart';

/// v5 — Kayıtlı terazi cihazları.
///
/// Kullanıcının daha önce eşleştirdiği terazileri (BLE / Classic
/// Bluetooth / Wi-Fi) hatırlamak için: cihaz adı, adresi, bağlantı
/// türü ve son bağlanma zamanı burada tutulur. Böylece uygulama
/// açılışında otomatik olarak "son kullanılan terazi"ye yeniden
/// bağlanmayı deneyebilir.
class MigrationV5TeraziCihazlari extends Migration {
  @override
  int get version => 5;

  @override
  String get description => 'terazi_cihazlari tablosu (kayıtlı teraziler)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await TableBuilder('terazi_cihazlari')
        .id()
        .text('cihaz_adi', notNull: true)
        .text('cihaz_adresi', notNull: true) // MAC / IP
        .text('baglanti_turu', notNull: true) // 'ble' | 'classic' | 'wifi'
        .integer('port') // sadece wifi için
        .boolean('varsayilan', defaultValue: false)
        .text('son_baglanti_tarihi')
        .timestamps()
        .unique(['cihaz_adresi', 'baglanti_turu'])
        .create(db);
  }
}
