import 'package:sqflite/sqflite.dart';

import '../../../senkron/senk_tablolari.dart';
import 'migration.dart';

/// v13: ÇOKLU CİHAZ / BULUT altyapısı (Fırın ERP v12–v13'ün süt-yem sürümü).
///  • cariler, fiyatlar, yemler, cari_odemeler → `uuid` (benzersiz; mevcut satırlar doldurulur,
///    yeni satıra tetikleyiciyle verilir — repository kodu değişmez)
///  • sutler → `sabah_zaman`, `aksam_zaman`: öğün başına son değişiklik anı. İki cihaz aynı
///    günün farklı öğününü girerse BİRLEŞİR (biri diğerini ezmez).
///  • senk_gunluk: her ekleme/güncelleme/silme TETİKLEYİCİYLE yazılır (hiçbir ekran unutamaz)
///  • senk_durum / senk_kanallar / senk_bekleyen / senk_hatalar / senk_eksik_ref / senk_ayarlar
///  • Dönem kilidi tetikleyicileri, BAŞKA CİHAZDAN gelen değişiklik uygulanırken çalışmaz
///    (kilit yazan cihazda denetlendi; aksi halde "ay açıldı" bilgisi sonra gelirse kayıt kaybolurdu).
///  • Mevcut kayıtlar günlüğe "taban" (2000-01-01) zamanıyla işlenir.
class MigrationV13Senkron extends Migration {
  @override
  int get version => 13;

  @override
  String get description => 'çoklu cihaz / bulut senkron altyapısı';

  static const tabanZaman = '2000-01-01T00:00:00.000Z';

  @override
  Future<void> up(DatabaseExecutor db) async {
    Future<Set<Object?>> kolonlar(String t) async => (await db.rawQuery('PRAGMA table_info($t)')).map((c) => c['name']).toSet();

    for (final t in uuidTablolari) {
      if (!(await kolonlar(t)).contains('uuid')) await db.execute('ALTER TABLE $t ADD COLUMN uuid TEXT');
      await db.execute('UPDATE $t SET uuid = lower(hex(randomblob(16))) WHERE uuid IS NULL');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_${t}_uuid ON $t (uuid)');
    }
    final sk = await kolonlar('sutler');
    for (final z in sutOgunleri.values) {
      if (!sk.contains(z)) await db.execute('ALTER TABLE sutler ADD COLUMN $z TEXT');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_gunluk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo TEXT NOT NULL,
        anahtar TEXT NOT NULL,
        islem TEXT NOT NULL CHECK (islem IN ('y','s')),
        zaman TEXT NOT NULL,
        cihaz TEXT NOT NULL DEFAULT '',
        kaynak TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_senk_gunluk_anahtar ON senk_gunluk (tablo, anahtar, id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_durum (
        tek INTEGER PRIMARY KEY CHECK (tek = 1),
        uygulaniyor INTEGER NOT NULL DEFAULT 0,
        kapali INTEGER NOT NULL DEFAULT 0,
        yerel_cihaz TEXT NOT NULL DEFAULT '',
        uzak_cihaz TEXT,
        zaman TEXT,
        kaynak TEXT
      )''');
    await db.rawInsert("INSERT OR IGNORE INTO senk_durum (tek, uygulaniyor, kapali, yerel_cihaz) VALUES (1, 0, 0, '')");
    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_kanallar (
        kanal TEXT PRIMARY KEY,
        son_gonderilen INTEGER NOT NULL DEFAULT 0,
        son_cekilen INTEGER NOT NULL DEFAULT 0,
        son_basari TEXT,
        son_hata TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_bekleyen (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kanal TEXT NOT NULL,
        tablo TEXT NOT NULL,
        anahtar TEXT NOT NULL,
        kayit_json TEXT NOT NULL,
        zaman TEXT NOT NULL,
        deneme INTEGER NOT NULL DEFAULT 0,
        son_hata TEXT,
        UNIQUE (kanal, tablo, anahtar)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_hatalar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        zaman TEXT NOT NULL,
        kanal TEXT,
        tablo TEXT,
        anahtar TEXT,
        mesaj TEXT NOT NULL,
        kayit_json TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS senk_eksik_ref (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tablo TEXT NOT NULL,
        anahtar TEXT NOT NULL,
        kolon TEXT NOT NULL,
        ebeveyn_tablo TEXT NOT NULL,
        ebeveyn_anahtar TEXT NOT NULL,
        UNIQUE (tablo, anahtar, kolon)
      )''');
    // Cihaza özel senkron ayarları (bulut adresi, işletme şifresi, yerel ağ rolü…).
    // Yedeğe GİRMEZ, eşitlenmez.
    await db.execute('CREATE TABLE IF NOT EXISTS senk_ayarlar (anahtar TEXT PRIMARY KEY, deger TEXT)');

    await donemKilitleriniKur(db);
    await senkTetikleyicileriKur(db);

    for (final t in senkTablolari) {
      await db.execute('''
        INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz)
        SELECT '$t', k, 'y', '$tabanZaman', '' FROM (SELECT ${anahtarIfadesi(t, 'x')} AS k FROM $t x) WHERE k IS NOT NULL''');
    }
  }
}

/// Uzaktan değişiklik uygulanmıyorsa (bu cihazın kendi işlemi) koşulu.
const _yerelIslem = 'NOT EXISTS (SELECT 1 FROM senk_durum s WHERE s.tek = 1 AND s.uygulaniyor = 1)';

/// Dönem kilidi tetikleyicileri (v9/v11 ile aynı kural) + uzaktan uygulama istisnası.
Future<void> donemKilitleriniKur(DatabaseExecutor db) async {
  const ayIfadesi = {
    'sutler': 'substr(%s.tarih, 1, 7)',
    'yemler': 'substr(%s.tarih, 1, 7)',
    'cari_odemeler': 'substr(%s.tarih, 1, 7)',
    'cari_fiyatlar': 'substr(%s.ay, 1, 7)',
  };
  String kapali(String t, String r) =>
      "EXISTS (SELECT 1 FROM donemler WHERE ay = ${ayIfadesi[t]!.replaceAll('%s', r)} AND durum = 'kapali')";
  for (final t in ayIfadesi.keys) {
    for (final s in ['ekle', 'guncelle', 'sil']) {
      await db.execute('DROP TRIGGER IF EXISTS trg_${t}_donem_$s');
    }
    await db.execute('''
      CREATE TRIGGER trg_${t}_donem_ekle BEFORE INSERT ON $t
      WHEN ${kapali(t, 'NEW')} AND $_yerelIslem
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
    await db.execute('''
      CREATE TRIGGER trg_${t}_donem_guncelle BEFORE UPDATE ON $t
      WHEN (${kapali(t, 'OLD')} OR ${kapali(t, 'NEW')}) AND $_yerelIslem
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
    await db.execute('''
      CREATE TRIGGER trg_${t}_donem_sil BEFORE DELETE ON $t
      WHEN ${kapali(t, 'OLD')} AND $_yerelIslem
      BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
  }
  await db.execute('DROP TRIGGER IF EXISTS trg_donem_hakedisleri_sil');
  await db.execute('''
    CREATE TRIGGER trg_donem_hakedisleri_sil BEFORE DELETE ON donem_hakedisleri
    WHEN EXISTS (SELECT 1 FROM donemler WHERE id = OLD.donem_id AND durum = 'kapali') AND $_yerelIslem
    BEGIN SELECT RAISE(ABORT, 'DONEM_KAPALI'); END''');
}

/// Tablonun cihazlar arası anahtarını veren SQL ifadesi ([r] = NEW/OLD/x).
String anahtarIfadesi(String tablo, String r) {
  final d = dogalAnahtarlar[tablo];
  if (d == null) return '$r.uuid';
  return d.map((c) {
    final ebeveyn = iliskiSutunlari[c];
    if (ebeveyn != null) {
      final ebeveynAnahtar = dogalMi(ebeveyn) ? anahtarIfadesi(ebeveyn, 'e') : 'e.uuid';
      return "COALESCE((SELECT $ebeveynAnahtar FROM $ebeveyn e WHERE e.id = $r.$c), '')";
    }
    return "COALESCE($r.$c, '')";
  }).join(" || '|' || ");
}

String _gunlukYaz(String tablo, String anahtar, String islem) => '''
    INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz, kaynak)
    SELECT '$tablo', $anahtar, '$islem',
      CASE WHEN d.uygulaniyor = 1 THEN d.zaman ELSE strftime('%Y-%m-%dT%H:%M:%fZ', 'now') END,
      CASE WHEN d.uygulaniyor = 1 THEN d.uzak_cihaz ELSE d.yerel_cihaz END,
      CASE WHEN d.uygulaniyor = 1 THEN d.kaynak ELSE NULL END
    FROM senk_durum d WHERE d.tek = 1 AND d.kapali = 0;''';

/// Tüm senkron tetikleyicilerini (yeniden) kurar.
Future<void> senkTetikleyicileriKur(DatabaseExecutor db) async {
  for (final t in senkTablolari) {
    for (final s in ['ins', 'upd', 'upd_eski', 'del', 'uuid', 'ogun_ins', 'ogun_upd']) {
      await db.execute('DROP TRIGGER IF EXISTS senk_${t}_$s');
    }
    final yeni = anahtarIfadesi(t, 'NEW');
    final eski = anahtarIfadesi(t, 'OLD');
    if (dogalMi(t)) {
      await db.execute('CREATE TRIGGER senk_${t}_ins AFTER INSERT ON $t BEGIN ${_gunlukYaz(t, yeni, 'y')} END');
      await db.execute('CREATE TRIGGER senk_${t}_upd AFTER UPDATE ON $t BEGIN ${_gunlukYaz(t, yeni, 'y')} END');
      // Doğal anahtar değiştiyse (ör. süt satırının tarihi düzeltildi) eski anahtar silinmiş sayılır.
      await db.execute('CREATE TRIGGER senk_${t}_upd_eski AFTER UPDATE ON $t WHEN ($eski) <> ($yeni) BEGIN ${_gunlukYaz(t, eski, 's')} END');
      await db.execute('CREATE TRIGGER senk_${t}_del AFTER DELETE ON $t BEGIN ${_gunlukYaz(t, eski, 's')} END');
    } else {
      // uuid'siz eklenen satıra (repository insert'leri) uuid verilir; bu güncelleme günlüğe yazılır.
      await db.execute(
          'CREATE TRIGGER senk_${t}_uuid AFTER INSERT ON $t WHEN NEW.uuid IS NULL BEGIN UPDATE $t SET uuid = lower(hex(randomblob(16))) WHERE rowid = NEW.rowid; END');
      await db.execute('CREATE TRIGGER senk_${t}_ins AFTER INSERT ON $t WHEN NEW.uuid IS NOT NULL BEGIN ${_gunlukYaz(t, yeni, 'y')} END');
      await db.execute('CREATE TRIGGER senk_${t}_upd AFTER UPDATE ON $t WHEN NEW.uuid IS NOT NULL BEGIN ${_gunlukYaz(t, yeni, 'y')} END');
      await db.execute(
          'CREATE TRIGGER senk_${t}_upd_eski AFTER UPDATE ON $t WHEN OLD.uuid IS NOT NULL AND OLD.uuid <> NEW.uuid BEGIN ${_gunlukYaz(t, eski, 's')} END');
      await db.execute('CREATE TRIGGER senk_${t}_del AFTER DELETE ON $t WHEN OLD.uuid IS NOT NULL BEGIN ${_gunlukYaz(t, eski, 's')} END');
    }
  }

  // Süt öğün zamanları: bu cihazda bir öğün girilince/değişince o öğünün zamanı "şimdi" olur.
  // Uzaktan uygularken (zamanı karşı cihaz verir) ve yedekten geri yüklerken (kapali) dokunulmaz.
  const yerel = "(SELECT d.uygulaniyor = 0 AND d.kapali = 0 FROM senk_durum d WHERE d.tek = 1)";
  const simdi = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
  await db.execute('''
    CREATE TRIGGER senk_sutler_ogun_ins AFTER INSERT ON sutler
    WHEN $yerel AND ((COALESCE(NEW.sabah, 0) <> 0 AND NEW.sabah_zaman IS NULL) OR (COALESCE(NEW.aksam, 0) <> 0 AND NEW.aksam_zaman IS NULL))
    BEGIN
      UPDATE sutler SET
        sabah_zaman = CASE WHEN COALESCE(NEW.sabah, 0) <> 0 AND NEW.sabah_zaman IS NULL THEN $simdi ELSE sabah_zaman END,
        aksam_zaman = CASE WHEN COALESCE(NEW.aksam, 0) <> 0 AND NEW.aksam_zaman IS NULL THEN $simdi ELSE aksam_zaman END
      WHERE rowid = NEW.rowid;
    END''');
  await db.execute('''
    CREATE TRIGGER senk_sutler_ogun_upd AFTER UPDATE OF sabah, aksam ON sutler
    WHEN $yerel AND ((NEW.sabah IS NOT OLD.sabah AND NEW.sabah_zaman IS OLD.sabah_zaman)
                  OR (NEW.aksam IS NOT OLD.aksam AND NEW.aksam_zaman IS OLD.aksam_zaman))
    BEGIN
      UPDATE sutler SET
        sabah_zaman = CASE WHEN NEW.sabah IS NOT OLD.sabah AND NEW.sabah_zaman IS OLD.sabah_zaman THEN $simdi ELSE sabah_zaman END,
        aksam_zaman = CASE WHEN NEW.aksam IS NOT OLD.aksam AND NEW.aksam_zaman IS OLD.aksam_zaman THEN $simdi ELSE aksam_zaman END
      WHERE rowid = NEW.rowid;
    END''');
}
