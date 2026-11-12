import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/database/migrations/migration_v13_senkron.dart';
import 'senk_tablolari.dart';

/// Cihazlar arası taşınan tek kayıt (bulut ve yerel ağ için AYNI biçim).
class SenkKayit {
  final String tablo;
  final String anahtar;
  final String zaman; // değişikliğin yapıldığı an (UTC, ISO) — son yazan kazanır
  final String cihaz; // değişikliği yapan cihaz (eşit zamanda sıralama)
  final bool silindi;
  final Map<String, Object?>? veri; // sütunlar (yerel id YOK) + '_ref'

  const SenkKayit({required this.tablo, required this.anahtar, required this.zaman, required this.cihaz, this.silindi = false, this.veri});

  Map<String, Object?> toJson() => {'t': tablo, 'k': anahtar, 'z': zaman, 'c': cihaz, 's': silindi, if (veri != null) 'v': veri};

  factory SenkKayit.fromJson(Map<String, Object?> m) => SenkKayit(
        tablo: m['t'] as String,
        anahtar: m['k'] as String,
        zaman: m['z'] as String,
        cihaz: (m['c'] as String?) ?? '',
        silindi: m['s'] == true,
        veri: (m['v'] as Map?)?.cast<String, Object?>(),
      );

  /// Bu kayıt, (z0, c0) zamanlı yerel durumdan YENİ mi?
  bool yenidir(String z0, String c0) => zaman.compareTo(z0) > 0 || (zaman == z0 && cihaz.compareTo(c0) > 0);
}

class UygulamaSonucu {
  int uygulanan = 0, atlanan = 0, bekletilen = 0, hatali = 0;
  int get toplam => uygulanan + atlanan + bekletilen + hatali;
  @override
  String toString() => '$uygulanan alındı'
      '${bekletilen > 0 ? ', $bekletilen bekletildi' : ''}${hatali > 0 ? ', $hatali hata' : ''}';
}

/// Kayıt neden bekletildi (ebeveyni — ör. carisi — henüz yok).
class _Bekle implements Exception {
  final String neden;
  const _Bekle(this.neden);
}

/// ─────────────────────────────────────────────────────────────
/// SENKRON ÇEKİRDEĞİ — günlükten paket kurar, gelen paketi uygular.
/// Kanaldan bağımsızdır: bulut (Supabase) ve yerel ağ (WiFi) aynı kodu kullanır.
/// ─────────────────────────────────────────────────────────────
class SenkCekirdek {
  final DatabaseExecutor db;
  SenkCekirdek(this.db);

  final _kolonlar = <String, List<String>>{};
  final _anahtarOnbellek = <String, Map<int, String?>>{}; // tablo → yerel id → anahtar
  final _idOnbellek = <String, Map<String, int?>>{}; // tablo → anahtar → yerel id

  static String simdiUtc() => DateTime.now().toUtc().toIso8601String();

  /// Bu cihazın kimliğini tetikleyicilere bildirir; kimliksiz taban kayıtları ona bağlar.
  static Future<void> cihazAyarla(DatabaseExecutor db, String cihaz) async {
    await db.rawUpdate('UPDATE senk_durum SET yerel_cihaz = ? WHERE tek = 1', [cihaz]);
    await db.rawUpdate("UPDATE senk_gunluk SET cihaz = ? WHERE cihaz = ''", [cihaz]);
  }

  Future<List<String>> _kolonlarOf(String tablo) async =>
      _kolonlar[tablo] ??= (await db.rawQuery('PRAGMA table_info($tablo)')).map((c) => c['name'] as String).toList();

  Future<Map<String, String>> _iliskiler(String tablo) async {
    final k = await _kolonlarOf(tablo);
    return {
      for (final e in iliskiSutunlari.entries)
        if (k.contains(e.key) && e.value != tablo) e.key: e.value,
    };
  }

  // ───────────────────────── anahtar ↔ yerel id ─────────────────────────

  Future<String?> _anahtar(String tablo, int id) async {
    final o = _anahtarOnbellek[tablo] ??= {};
    if (o.containsKey(id)) return o[id];
    final r = await db.query(tablo, where: 'id = ?', whereArgs: [id], limit: 1);
    String? a;
    if (r.isNotEmpty) a = dogalMi(tablo) ? await _dogalAnahtarKur(tablo, r.first) : r.first['uuid'] as String?;
    return o[id] = a;
  }

  Future<String?> _dogalAnahtarKur(String tablo, Map<String, Object?> satir) async {
    final parcalar = <String>[];
    for (final c in dogalAnahtarlar[tablo]!) {
      final ebeveyn = iliskiSutunlari[c];
      final v = satir[c];
      if (ebeveyn != null) {
        parcalar.add(v == null ? '' : (await _anahtar(ebeveyn, v as int)) ?? '');
      } else {
        parcalar.add(v?.toString() ?? '');
      }
    }
    return parcalar.join('|');
  }

  Future<Map<String, Object?>?> _satir(String tablo, String anahtar) async {
    final w = await _dogalKosul(tablo, anahtar);
    if (w == null) return null;
    final r = await db.rawQuery('SELECT rowid AS _rowid, * FROM $tablo WHERE ${w.$1} LIMIT 1', w.$2);
    return r.isEmpty ? null : r.first;
  }

  /// Doğal anahtar → WHERE. İçindeki ilişki parçası yerelde yoksa null.
  Future<(String, List<Object?>)?> _dogalKosul(String tablo, String anahtar) async {
    final d = dogalAnahtarlar[tablo];
    if (d == null) return ('uuid = ?', [anahtar]);
    final parcalar = anahtar.split('|');
    if (parcalar.length != d.length) return null;
    final kosul = <String>[];
    final args = <Object?>[];
    for (var i = 0; i < d.length; i++) {
      final ebeveyn = iliskiSutunlari[d[i]];
      Object? v = parcalar[i];
      if (ebeveyn != null) {
        v = await _yerelId(ebeveyn, parcalar[i]);
        if (v == null) return null;
      }
      kosul.add('${d[i]} = ?');
      args.add(v);
    }
    return (kosul.join(' AND '), args);
  }

  Future<int?> _yerelId(String tablo, String anahtar) async {
    final o = _idOnbellek[tablo] ??= {};
    if (o.containsKey(anahtar)) return o[anahtar];
    final s = await _satir(tablo, anahtar);
    final id = s?['id'] as int?;
    if (id != null) o[anahtar] = id;
    return id;
  }

  // ───────────────────────────── GÖNDERİM ─────────────────────────────

  /// [sonra]dan sonraki günlükten, [haricKaynak] dışından gelmiş değişiklikleri kayıt
  /// olarak kurar. Aynı kayda ait birden çok değişiklik tek kayda iner (son hali gider).
  Future<(List<SenkKayit>, int)> gonderilecekler({required int sonra, required String? haricKaynak, int limit = 300}) async {
    final g = await db.rawQuery('SELECT id, tablo, anahtar FROM senk_gunluk WHERE id > ? ORDER BY id LIMIT ?', [sonra, limit]);
    if (g.isEmpty) return (const <SenkKayit>[], sonra);
    final sonId = g.last['id'] as int;
    final goruldu = <String>{};
    final sonuc = <SenkKayit>[];
    for (final r in g.reversed) {
      final tablo = r['tablo'] as String, anahtar = r['anahtar'] as String;
      if (!goruldu.add('$tablo\u0000$anahtar')) continue;
      final son = (await db.rawQuery(
              'SELECT islem, zaman, cihaz, kaynak FROM senk_gunluk WHERE tablo = ? AND anahtar = ? ORDER BY id DESC LIMIT 1', [tablo, anahtar]))
          .first;
      if (haricKaynak != null && son['kaynak'] == haricKaynak) continue; // yankı yok
      final k = await kayitKur(tablo, anahtar, son['zaman'] as String, son['cihaz'] as String, silindi: son['islem'] == 's');
      if (k != null) sonuc.add(k);
    }
    return (sonuc.reversed.toList(), sonId);
  }

  Future<SenkKayit?> kayitKur(String tablo, String anahtar, String zaman, String cihaz, {bool silindi = false}) async {
    if (!senkTablolari.contains(tablo)) return null;
    final satir = silindi ? null : await _satir(tablo, anahtar);
    if (satir == null) return SenkKayit(tablo: tablo, anahtar: anahtar, zaman: zaman, cihaz: cihaz, silindi: true);
    final v = Map<String, Object?>.from(satir)
      ..remove('id')
      ..remove('_rowid');
    final ref = <String, Object?>{};
    for (final e in (await _iliskiler(tablo)).entries) {
      final id = v.remove(e.key) as int?;
      ref[e.key] = id == null ? null : await _anahtar(e.value, id);
    }
    if (ref.isNotEmpty) v['_ref'] = ref;
    return SenkKayit(tablo: tablo, anahtar: anahtar, zaman: zaman, cihaz: cihaz, veri: v);
  }

  Future<int> bekleyenSayisi({required int sonra, required String? haricKaynak}) async =>
      Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM senk_gunluk WHERE id > ? AND (kaynak IS NULL OR kaynak <> ?)', [sonra, haricKaynak ?? ''])) ??
      0;

  Future<int> sonGunlukId() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(MAX(id), 0) FROM senk_gunluk')) ?? 0;

  // ───────────────────────────── ALIM ─────────────────────────────

  /// Gelen kayıtları uygular; her kayıt AYRI (kayıt noktası) — biri hata verirse diğerleri yazılır.
  /// Ebeveyni gelmemiş ya da hata veren kayıt senk_bekleyen'de kalır, her turda yeniden denenir.
  /// [db] bir transaction olmalıdır.
  Future<UygulamaSonucu> uygula(List<SenkKayit> gelen, {required String kanal}) async {
    final sonuc = UygulamaSonucu();
    final bekleyenSatirlar = await db.query('senk_bekleyen', where: 'kanal = ?', whereArgs: [kanal]);
    final denemeler = <String, int>{
      for (final r in bekleyenSatirlar) '${r['tablo']}\u0000${r['anahtar']}': (r['deneme'] as int?) ?? 0,
    };
    final bekleyen = bekleyenSatirlar.map((r) => SenkKayit.fromJson((jsonDecode(r['kayit_json'] as String) as Map).cast<String, Object?>()));
    final hepsi = <String, SenkKayit>{};
    for (final k in [...bekleyen, ...gelen]) {
      final a = '${k.tablo}\u0000${k.anahtar}';
      final o = hepsi[a];
      if (o == null || k.yenidir(o.zaman, o.cihaz)) hepsi[a] = k;
    }
    int sira(SenkKayit k) => senkTablolari.indexOf(k.tablo);
    final ekle = hepsi.values.where((k) => !k.silindi && sira(k) >= 0).toList()..sort((a, b) => sira(a).compareTo(sira(b)));
    final sil = hepsi.values.where((k) => k.silindi && sira(k) >= 0).toList()..sort((a, b) => sira(b).compareTo(sira(a)));

    Future<void> beklet(SenkKayit k, String? hata) async {
      final a = '${k.tablo}\u0000${k.anahtar}';
      await db.rawInsert(
          'INSERT OR REPLACE INTO senk_bekleyen (kanal, tablo, anahtar, kayit_json, zaman, deneme, son_hata) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [kanal, k.tablo, k.anahtar, jsonEncode(k.toJson()), simdiUtc(), (denemeler[a] ?? 0) + 1, hata]);
    }

    var cariDegisti = false;
    await db.rawUpdate('UPDATE senk_durum SET uygulaniyor = 1, kaynak = ? WHERE tek = 1', [kanal]);
    try {
      for (final k in [...ekle, ...sil]) {
        await db.execute('SAVEPOINT senk_kayit');
        try {
          final uygulandi = await _uygulaTek(k);
          await db.execute('RELEASE senk_kayit');
          await db.delete('senk_bekleyen', where: 'kanal = ? AND tablo = ? AND anahtar = ?', whereArgs: [kanal, k.tablo, k.anahtar]);
          await db.delete('senk_hatalar', where: 'kanal = ? AND tablo = ? AND anahtar = ?', whereArgs: [kanal, k.tablo, k.anahtar]);
          if (uygulandi) {
            sonuc.uygulanan++;
            if (k.tablo == 'cariler') cariDegisti = true;
          } else {
            sonuc.atlanan++;
          }
        } on _Bekle {
          await db.execute('ROLLBACK TO senk_kayit');
          await db.execute('RELEASE senk_kayit');
          await beklet(k, null);
          sonuc.bekletilen++;
        } catch (e) {
          await db.execute('ROLLBACK TO senk_kayit');
          await db.execute('RELEASE senk_kayit');
          final mesaj = _hataMetni(e);
          await beklet(k, mesaj); // KAYBOLMAZ: sonraki turlarda yeniden denenir
          await db.delete('senk_hatalar', where: 'kanal = ? AND tablo = ? AND anahtar = ?', whereArgs: [kanal, k.tablo, k.anahtar]);
          await db.insert('senk_hatalar', {
            'zaman': simdiUtc(),
            'kanal': kanal,
            'tablo': k.tablo,
            'anahtar': k.anahtar,
            'mesaj': mesaj,
            'kayit_json': jsonEncode(k.toJson()),
          });
          sonuc.hatali++;
        }
      }
    } finally {
      await db.rawUpdate('UPDATE senk_durum SET uygulaniyor = 0, kaynak = NULL, uzak_cihaz = NULL, zaman = NULL WHERE tek = 1');
    }
    if (cariDegisti) await rotaDuzelt(db);
    return sonuc;
  }

  static String _hataMetni(Object e) {
    final s = e.toString();
    if (s.contains('DONEM_KAPALI')) return 'Kapalı dönemdeki kayıt değiştirilemedi.';
    if (s.contains('UNIQUE')) return 'Bu cihazda aynı cari/tarih ile başka kayıt var (çakışma): $s';
    if (s.contains('FOREIGN KEY')) return 'Bağlı kayıt bulunamadı ya da silinecek kaydın bağlı kayıtları var: $s';
    return s;
  }

  static double _sayi(Object? v) => (v as num?)?.toDouble() ?? 0;

  /// Gelen satırın sütunları (bilinmeyen/yeni sürüm sütunları atlanır) + ilişkiler yerel id'ye.
  Future<Map<String, Object?>> _veriHazirla(SenkKayit k) async {
    final kolonlar = await _kolonlarOf(k.tablo);
    final veri = <String, Object?>{};
    final ham = k.veri ?? const {};
    for (final e in ham.entries) {
      if (e.key.startsWith('_') || e.key == 'id' || !kolonlar.contains(e.key)) continue;
      veri[e.key] = e.value;
    }
    final ref = (ham['_ref'] as Map?)?.cast<String, Object?>() ?? const {};
    for (final e in (await _iliskiler(k.tablo)).entries) {
      if (!ref.containsKey(e.key)) continue;
      final a = ref[e.key] as String?;
      if (a == null) {
        veri[e.key] = null;
        continue;
      }
      final id = await _yerelId(e.value, a);
      if (id == null) throw _Bekle('${e.value} henüz yok');
      veri[e.key] = id;
    }
    return veri;
  }

  /// true: yazıldı · false: yerel hali daha yeni/aynı, atlandı.
  Future<bool> _uygulaTek(SenkKayit k) async {
    final yerelSon =
        await db.rawQuery('SELECT zaman, cihaz FROM senk_gunluk WHERE tablo = ? AND anahtar = ? ORDER BY id DESC LIMIT 1', [k.tablo, k.anahtar]);
    final satirYeni = yerelSon.isEmpty || k.yenidir(yerelSon.first['zaman'] as String, yerelSon.first['cihaz'] as String);
    // Süt satırı öğün öğün birleşir (satır daha eski olsa bile içindeki bir öğün daha yeni olabilir).
    if (k.tablo == 'sutler' && !k.silindi) return _sutBirlestir(k, satirYeni);
    if (!satirYeni) return false;
    await db.rawUpdate('UPDATE senk_durum SET zaman = ?, uzak_cihaz = ? WHERE tek = 1', [k.zaman, k.cihaz]);

    final mevcut = await _satir(k.tablo, k.anahtar);
    if (k.silindi) {
      if (mevcut == null) {
        await _gunlugeElle(k, 's'); // satır zaten yok: "silindi" bilgisi yine günlüğe
        return true;
      }
      await db.delete(k.tablo, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
      _onbellekTemizle(k.tablo);
      return true;
    }
    final veri = await _veriHazirla(k);
    if (mevcut == null) {
      if (!dogalMi(k.tablo)) veri['uuid'] = k.anahtar;
      await db.insert(k.tablo, veri);
    } else {
      veri.remove('uuid');
      await db.update(k.tablo, veri, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
    }
    _onbellekTemizle(k.tablo);
    return true;
  }

  /// SÜT: sabah ve akşam ayrı ayrı birleşir — her öğünde DAHA YENİ girilen değer kalır.
  /// (A cihazı sabahı, B cihazı akşamı girdiyse ikisi de korunur; eskiden satırın tamamı ezilirdi.)
  /// Birleşen sonuç gelenden farklıysa (bu cihazda daha yeni bir öğün vardı) sonuç YEREL değişiklik
  /// olarak günlüğe yazılır → karşı tarafa geri gider, iki cihaz da aynı sonuca varır.
  Future<bool> _sutBirlestir(SenkKayit k, bool satirYeni) async {
    await db.rawUpdate('UPDATE senk_durum SET zaman = ?, uzak_cihaz = ? WHERE tek = 1', [k.zaman, k.cihaz]);
    final veri = await _veriHazirla(k);
    final mevcut = await _satir('sutler', k.anahtar);
    if (mevcut == null) {
      veri['toplam'] = _sayi(veri['sabah']) + _sayi(veri['aksam']);
      await db.insert('sutler', veri);
      _onbellekTemizle('sutler');
      return true;
    }
    final yeni = <String, Object?>{};
    var farkli = false;
    for (final e in sutOgunleri.entries) {
      final og = e.key, zk = e.value;
      final gz = (veri[zk] as String?) ?? '', yz = (mevcut[zk] as String?) ?? '';
      final gelenKazanir = gz.compareTo(yz) > 0 || (gz == yz && satirYeni);
      final ayni = _sayi(veri[og]) == _sayi(mevcut[og]) && gz == yz;
      if (ayni) continue;
      if (gelenKazanir) {
        yeni[og] = _sayi(veri[og]);
        yeni[zk] = veri[zk];
      } else {
        farkli = true;
      }
    }
    if (veri.containsKey('aciklama') && veri['aciklama'] != mevcut['aciklama']) {
      if (satirYeni) {
        yeni['aciklama'] = veri['aciklama'];
      } else {
        farkli = true;
      }
    }
    if (yeni.isNotEmpty) {
      final sabah = yeni.containsKey('sabah') ? yeni['sabah'] : mevcut['sabah'];
      final aksam = yeni.containsKey('aksam') ? yeni['aksam'] : mevcut['aksam'];
      yeni['toplam'] = _sayi(sabah) + _sayi(aksam);
      await db.update('sutler', yeni, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
    }
    if (farkli) {
      // Bu cihazın daha yeni öğünü karşıya gitsin (yerel değişiklik olarak, kaynak boş).
      await db.rawInsert(
          "INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz, kaynak) SELECT 'sutler', ?, 'y', ?, yerel_cihaz, NULL FROM senk_durum WHERE tek = 1",
          [k.anahtar, simdiUtc()]);
    }
    return yeni.isNotEmpty || farkli;
  }

  void _onbellekTemizle(String tablo) {
    _anahtarOnbellek.remove(tablo);
    _idOnbellek.remove(tablo);
  }

  Future<void> _gunlugeElle(SenkKayit k, String islem) => db.rawInsert(
      'INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz, kaynak) SELECT ?, ?, ?, ?, ?, kaynak FROM senk_durum WHERE tek = 1',
      [k.tablo, k.anahtar, islem, k.zaman, k.cihaz]);

  /// Toplama rotası 1..N boşluksuz (SUTYEM kural 16). İki cihaz aynı anda sıra değiştirirse
  /// çakışan/boşluklu numaralar burada düzeltilir; düzeltme her iki cihazda da AYNI sonucu
  /// verir (sıra, sonra uuid) ve yerel değişiklik olarak eşitlenir.
  static Future<void> rotaDuzelt(DatabaseExecutor db) async {
    await db.rawUpdate('UPDATE cariler SET sira = NULL WHERE COALESCE(aktif, 1) = 0 AND sira IS NOT NULL');
    final l = await db.rawQuery('SELECT id, sira FROM cariler WHERE COALESCE(aktif, 1) = 1 AND sira IS NOT NULL ORDER BY sira, uuid');
    for (var i = 0; i < l.length; i++) {
      if (l[i]['sira'] != i + 1) await db.rawUpdate('UPDATE cariler SET sira = ? WHERE id = ?', [i + 1, l[i]['id']]);
    }
  }

  /// Eskimiş günlük satırlarını siler (her kayıt için yalnız SON değişiklik kalır).
  Future<int> budama() => db.rawDelete('DELETE FROM senk_gunluk WHERE id NOT IN (SELECT MAX(id) FROM senk_gunluk GROUP BY tablo, anahtar)');

  /// YEDEKTEN GERİ YÜKLEME (JSON ya da .db) sonrası: günlük "taban" zamanla yeniden kurulur,
  /// kanal sayaçları sıfırlanır. Geri yüklenen eski veri diğer cihazlardaki DAHA YENİ kayıtları
  /// ezmez/silmez; onlar bu cihaza geri gelir. Öğün zamanları korunur (yedekte varsa).
  static Future<void> tabanYenile(DatabaseExecutor db) async {
    await db.delete('senk_gunluk');
    await db.delete('senk_bekleyen');
    await db.delete('senk_eksik_ref');
    final cihaz = (await db.rawQuery('SELECT yerel_cihaz FROM senk_durum WHERE tek = 1')).firstOrNull?['yerel_cihaz'] ?? '';
    for (final t in senkTablolari) {
      await db.rawInsert('''
        INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz)
        SELECT '$t', k, 'y', '${MigrationV13Senkron.tabanZaman}', ? FROM (SELECT ${anahtarIfadesi(t, 'x')} AS k FROM $t x) WHERE k IS NOT NULL''',
          [cihaz]);
    }
    await db.rawUpdate('UPDATE senk_kanallar SET son_gonderilen = 0, son_cekilen = 0');
  }
}
