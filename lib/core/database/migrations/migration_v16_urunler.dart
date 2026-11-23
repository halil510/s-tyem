import 'package:sqflite/sqflite.dart';

import '../../../models/urun_model.dart';
import 'migration.dart';
import 'migration_v13_senkron.dart';

/// v16 — ÜRÜNLER (yem türleri artık sabit değil; gübre, saman… eklenebilir).
///
/// - `urunler`: ad, birim (kg / çuval / adet…), sıra, aktif. Eski 6 yem türü SABİT
///   kimlikle ([sistemUrunleri]) eklenir: iki telefon ayrı ayrı güncellense de
///   ürünler eşitlemede İKİ KEZ oluşmaz.
/// - `yemler.urun_id` + `yemler.miktar`: her yem satırı artık TEK ürün + miktar.
///   Bir teslimatta birden çok ürün = birden çok satır. Eski satır (6 sütunlu)
///   bölünür: ilk dolu tür satırın kendisinde kalır (aynı id/uuid), diğerleri yeni
///   satır olur (uuid = eski uuid + '~' + ürün kimliği → iki telefonda AYNI). Tamamen
///   boş (0 kg) eski satır silinir (tutarı zaten 0'dı).
/// - `cari_urun_fiyatlari`: cari + ürün + ay ('yyyy-MM' ya da eski veriden 'yyyy-MM-dd')
///   birim fiyatı. Eski `cari_fiyatlar` yem fiyatlarından yalnız DEĞİŞİM NOKTALARI
///   aktarılır → her kaydın tutarı kuruşu kuruşuna aynı kalır (testli).
///
/// Eski sütunlar (yemler.sut_yemi…, cari_fiyatlar.sut_yemi_fiyat…) SQLite'ta
/// silinemediği için yerinde kalır ama v16'dan sonra HİÇBİR kod onları okumaz.
/// Kapalı dönem kilidi `cari_urun_fiyatlari`'na da kurulur.
///
/// ÇOKLU CİHAZ: tüm telefonlar bu sürüme birlikte güncellenmelidir (eski sürüm yeni
/// ürün satırlarını göremez). Okuma sayaçları sıfırlanır (bkz. v15): eski sürümdeyken
/// atılan ürün/fiyat kayıtları güncellemeden sonra bir kez yeniden alınır.
class MigrationV16Urunler extends Migration {
  @override
  int get version => 16;

  @override
  String get description => 'urunler + cari_urun_fiyatlari + yemler.urun_id/miktar (eski 6 yem türü aktarılır)';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS urunler (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ad TEXT NOT NULL,
        birim TEXT NOT NULL DEFAULT 'kg',
        sira INTEGER NOT NULL DEFAULT 0,
        aktif INTEGER NOT NULL DEFAULT 1,
        uuid TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now'))
      )''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_urunler_uuid ON urunler (uuid)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cari_urun_fiyatlari (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cari_id INTEGER NOT NULL,
        urun_id INTEGER NOT NULL,
        ay TEXT NOT NULL,
        fiyat REAL NOT NULL DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now')),
        UNIQUE (cari_id, urun_id, ay),
        FOREIGN KEY (cari_id) REFERENCES cariler(id) ON DELETE CASCADE,
        FOREIGN KEY (urun_id) REFERENCES urunler(id) ON DELETE CASCADE
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cari_urun_fiyatlari_ay ON cari_urun_fiyatlari (ay)');

    final yk = (await db.rawQuery('PRAGMA table_info(yemler)')).map((c) => c['name']).toSet();
    // Ürünü olan yem satırı varken ürün silinemez (RESTRICT): geçmiş kayıt sahipsiz kalmasın.
    if (!yk.contains('urun_id')) {
      await db.execute('ALTER TABLE yemler ADD COLUMN urun_id INTEGER REFERENCES urunler(id) ON DELETE RESTRICT');
    }
    if (!yk.contains('miktar')) await db.execute('ALTER TABLE yemler ADD COLUMN miktar REAL NOT NULL DEFAULT 0');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_yemler_urun ON yemler (urun_id)');

    // Dönüştürme kapalı aylardaki satırlara da yazar: kilit tetikleyicileri geçici kaldırılır,
    // sonda (cari_urun_fiyatlari dahil) yeniden kurulur. Senkron tetikleyicileri ÇALIŞIR:
    // değişiklikler bulut/yerel ağ kopyasına da gider (iki telefon aynı sonucu üretir).
    for (final t in ['yemler', 'cari_fiyatlar']) {
      for (final s in ['ekle', 'guncelle', 'sil']) {
        await db.execute('DROP TRIGGER IF EXISTS trg_${t}_donem_$s');
      }
    }
    // Yeni tabloların eşitleme tetikleyicileri ÖNCE kurulur: aktarılan ürün ve fiyatlar günlüğe yazılsın.
    await senkTetikleyicileriKur(db);

    await sistemUrunleriniEkle(db);
    // Hazır 6 ürün her telefonda AYNI kimlikle kurulur; günlük zamanı "taban" (en eski) olur. Yoksa
    // aylar sonra kurulan yeni telefonun kurulum anı, başka telefonda yapılmış gerçek bir değişikliği
    // (ad düzeltme, pasife alma) eşitlemede ezerdi. (Tablo bu migration'da kuruldu: tüm satırlar hazır ürün.)
    await db.rawUpdate("UPDATE senk_gunluk SET zaman = ? WHERE tablo = 'urunler'", [MigrationV13Senkron.tabanZaman]);
    await eskiYemleriDonustur(db);
    await eskiYemFiyatlariniDonustur(db);

    await donemKilitleriniKur(db);

    // KARIŞIK SÜRÜM (bkz. v15): eski sürümdeyken atılan kayıtlar bir kez yeniden alınsın.
    await db.rawUpdate('UPDATE senk_kanallar SET son_cekilen = 0');
    await db.rawInsert("INSERT OR REPLACE INTO senk_ayarlar (anahtar, deger) VALUES ('taban_nesil', ?)",
        [DateTime.now().toUtc().toIso8601String()]);
  }
}

/// Eski 6 yem türünü (yoksa) sabit kimlikleriyle ekler. Dönen: uuid → yerel id.
/// [yalniz]: verilirse yalnız bu uuid'ler (eski yedekte gerçekten kullanılanlar).
Future<Map<String, int>> sistemUrunleriniEkle(DatabaseExecutor db, {Set<String>? yalniz}) async {
  final idler = <String, int>{};
  for (var i = 0; i < sistemUrunleri.length; i++) {
    final t = sistemUrunleri[i];
    final mevcut = await db.query('urunler', columns: ['id'], where: 'uuid = ?', whereArgs: [t.uuid], limit: 1);
    if (mevcut.isNotEmpty) {
      idler[t.uuid] = mevcut.first['id'] as int;
      continue;
    }
    if (yalniz != null && !yalniz.contains(t.uuid)) continue;
    idler[t.uuid] = await db.insert('urunler', {'ad': t.ad, 'birim': 'kg', 'sira': i + 1, 'aktif': 1, 'uuid': t.uuid});
  }
  return idler;
}

/// Eski satırdaki dolu (> 0) yem türleri, eski sütun sırasıyla.
List<(EskiYemTuru, double)> eskiYemKalemleri(Map<String, Object?> satir) => [
      for (final t in sistemUrunleri)
        if (satir[t.yemSutunu] case final num m when m.isFinite && m > 0) (t, m.toDouble()),
    ];

/// Eski satır bölünürken yeni satırın kimliği: iki telefonda (ve aynı yedeğin iki
/// yüklenişinde) AYNI çıkar → eşitlemede/birleştirmede çift satır oluşmaz.
String bolunmusYemUuid(String anaUuid, EskiYemTuru t) => '$anaUuid~${t.uuid}';

/// Eski (urun_id'siz) yem satırlarını tek ürünlü satırlara böler.
Future<void> eskiYemleriDonustur(DatabaseExecutor db) async {
  final urunIdleri = await sistemUrunleriniEkle(db);
  final eskiler = await db.query('yemler', where: 'urun_id IS NULL', orderBy: 'id');
  for (final s in eskiler) {
    final kalemler = eskiYemKalemleri(s);
    final id = s['id'] as int;
    if (kalemler.isEmpty) {
      await db.delete('yemler', where: 'id = ?', whereArgs: [id]);
      continue;
    }
    final sifir = {for (final t in sistemUrunleri) t.yemSutunu: 0.0};
    final (ilkTur, ilkMiktar) = kalemler.first;
    await db.update(
      'yemler',
      {...sifir, 'urun_id': urunIdleri[ilkTur.uuid], 'miktar': ilkMiktar, 'toplam': ilkMiktar},
      where: 'id = ?',
      whereArgs: [id],
    );
    final anaUuid = s['uuid'] as String?;
    for (final (tur, miktar) in kalemler.skip(1)) {
      await db.insert('yemler', {
        'cari_id': s['cari_id'],
        'tarih': s['tarih'],
        ...sifir,
        'urun_id': urunIdleri[tur.uuid],
        'miktar': miktar,
        'toplam': miktar,
        'aciklama': s['aciklama'],
        if (s['created_at'] != null) 'created_at': s['created_at'],
        if (s['updated_at'] != null) 'updated_at': s['updated_at'],
        if (anaUuid != null) 'uuid': bolunmusYemUuid(anaUuid, tur),
      });
    }
  }
}

/// Eski `cari_fiyatlar` satırlarından (bir carinin TÜM satırları) ürün fiyatı
/// DEĞİŞİM NOKTALARI: her tür için anahtar sırasıyla gidilir, fiyat bir öncekinden
/// farklıysa nokta yazılır (başlangıç = fiyat yok = 0). Arama kuralı ("kaydın gününe
/// kadar başlamış en son fiyat") iki yapıda da aynı olduğundan her kaydın birim
/// fiyatı birebir korunur.
List<({int cariId, EskiYemTuru tur, String ay, double fiyat})> eskiFiyatNoktalari(Iterable<Map<String, Object?>> satirlar) {
  final cariBazli = <int, List<Map<String, Object?>>>{};
  for (final s in satirlar) {
    final c = s['cari_id'], ay = s['ay'];
    if (c is! int || ay is! String || ay.isEmpty) continue;
    cariBazli.putIfAbsent(c, () => []).add(s);
  }
  final sonuc = <({int cariId, EskiYemTuru tur, String ay, double fiyat})>[];
  for (final e in cariBazli.entries) {
    final l = e.value..sort((a, b) => (a['ay'] as String).compareTo(b['ay'] as String));
    for (final t in sistemUrunleri) {
      var onceki = 0.0;
      for (final s in l) {
        final ham = s[t.fiyatSutunu];
        final v = ham is num && ham.isFinite ? ham.toDouble() : 0.0;
        if (v != onceki) sonuc.add((cariId: e.key, tur: t, ay: s['ay'] as String, fiyat: v));
        onceki = v;
      }
    }
  }
  return sonuc;
}

/// Eski yem fiyatlarını `cari_urun_fiyatlari`'na aktarır (migration).
Future<void> eskiYemFiyatlariniDonustur(DatabaseExecutor db) async {
  final noktalar = eskiFiyatNoktalari(await db.query('cari_fiyatlar'));
  if (noktalar.isEmpty) return;
  final urunIdleri = await sistemUrunleriniEkle(db);
  for (final n in noktalar) {
    final urunId = urunIdleri[n.tur.uuid]!;
    final guncellenen = await db.update('cari_urun_fiyatlari', {'fiyat': n.fiyat},
        where: 'cari_id = ? AND urun_id = ? AND ay = ?', whereArgs: [n.cariId, urunId, n.ay]);
    if (guncellenen == 0) {
      await db.insert('cari_urun_fiyatlari', {'cari_id': n.cariId, 'urun_id': urunId, 'ay': n.ay, 'fiyat': n.fiyat});
    }
  }
}
