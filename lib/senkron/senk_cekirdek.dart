import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/database/migrations/migration_v13_senkron.dart';
import '../features/donem/donem_servisi.dart';
import 'senk_tablolari.dart';

/// Cihazlar arası taşınan tek kayıt (bulut ve yerel ağ için AYNI biçim).
class SenkKayit {
  final String tablo;
  final String anahtar;
  final String zaman; // değişikliğin günlüğe yazıldığı an (UTC, ISO) — satır düzeyinde son yazan kazanır
  final String cihaz; // değişikliği yapan cihaz (eşit zamanda sıralama)
  final bool silindi;

  /// Sütunlar (yerel id YOK) + '_ref'. Gruplu tablonun SİLME kaydında {'_tz': silmenin gerçek zamanı}.
  final Map<String, Object?>? veri;

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

  /// Silme kaydının gerçek zamanı (yeniden gönderilen silmede günlük zamanından eski olabilir).
  String get silmeZamani => (veri?['_tz'] as String?) ?? zaman;
}

class UygulamaSonucu {
  int uygulanan = 0, atlanan = 0, bekletilen = 0, hatali = 0, uyari = 0;
  int get toplam => uygulanan + atlanan + bekletilen + hatali;
  @override
  String toString() => '$uygulanan alındı'
      '${bekletilen > 0 ? ', $bekletilen bekletildi' : ''}${hatali > 0 ? ', $hatali hata' : ''}${uyari > 0 ? ', $uyari uyarı' : ''}';
}

/// Kayıt bekletilir (ebeveyni — ör. carisi — henüz gelmedi).
class _Bekle implements Exception {
  final String neden;
  const _Bekle(this.neden);
}

/// Kayıt geçersiz, atılır (ebeveyni bu cihazda SİLİNMİŞ: sonsuza kadar beklemesin).
class _Atla implements Exception {
  const _Atla();
}

/// Kullanıcıya gösterilen ama hata olmayan eşitleme notları bu kanal adıyla senk_hatalar'a yazılır
/// (aynı kaydın sonraki başarılı alımında silinmesinler diye ayrı kanal).
const uyariKanali = 'uyari';

/// ─────────────────────────────────────────────────────────────
/// SENKRON ÇEKİRDEĞİ — günlükten paket kurar, gelen paketi uygular.
/// Kanaldan bağımsızdır: bulut (Supabase) ve yerel ağ (WiFi) aynı kodu kullanır.
/// ─────────────────────────────────────────────────────────────
class SenkCekirdek {
  final DatabaseExecutor db;
  SenkCekirdek(this.db);

  final _kolonlar = <String, List<String>>{};
  final _anahtarOnbellek = <String, Map<int, String?>>{};
  final _idOnbellek = <String, Map<String, int?>>{};
  final _uyarilar = <(String tablo, String anahtar, String mesaj)>[];
  final _degisenKapaliAylar = <String>{};
  Set<String>? _kapaliAylar;

  static String simdiUtc() => DateTime.now().toUtc().toIso8601String();

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

  /// Kayıt bu cihazda silinmişse silmenin zamanı (mezar taşı), değilse ''.
  Future<String> _mezarZamani(String tablo, String anahtar) async {
    final r = await db.rawQuery(
        'SELECT islem, COALESCE(tz, zaman) AS t FROM senk_gunluk WHERE tablo = ? AND anahtar = ? ORDER BY id DESC LIMIT 1', [tablo, anahtar]);
    return (r.isNotEmpty && r.first['islem'] == 's') ? r.first['t'] as String : '';
  }

  // ───────────────────────────── GÖNDERİM ─────────────────────────────

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
              'SELECT islem, zaman, cihaz, kaynak, tz FROM senk_gunluk WHERE tablo = ? AND anahtar = ? ORDER BY id DESC LIMIT 1', [tablo, anahtar]))
          .first;
      if (haricKaynak != null && son['kaynak'] == haricKaynak) continue; // yankı yok
      final k = await kayitKur(tablo, anahtar, son['zaman'] as String, son['cihaz'] as String,
          silindi: son['islem'] == 's', silmeZamani: son['tz'] as String?);
      if (k != null) sonuc.add(k);
    }
    return (sonuc.reversed.toList(), sonId);
  }

  Future<SenkKayit?> kayitKur(String tablo, String anahtar, String zaman, String cihaz, {bool silindi = false, String? silmeZamani}) async {
    if (!senkTablolari.contains(tablo)) return null;
    final satir = silindi ? null : await _satir(tablo, anahtar);
    if (satir == null) {
      return SenkKayit(
          tablo: tablo, anahtar: anahtar, zaman: zaman, cihaz: cihaz, silindi: true, veri: grupluMu(tablo) ? {'_tz': silmeZamani ?? zaman} : null);
    }
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
  /// [gelen] boş verilirse yalnız bekleyenler yeniden denenir. [db] bir transaction olmalıdır.
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
    if (hepsi.isEmpty) return sonuc;
    int sira(SenkKayit k) => senkTablolari.indexOf(k.tablo);
    final ekle = hepsi.values.where((k) => !k.silindi && sira(k) >= 0).toList()..sort((a, b) => sira(a).compareTo(sira(b)));
    final sil = hepsi.values.where((k) => k.silindi && sira(k) >= 0).toList()..sort((a, b) => sira(b).compareTo(sira(a)));

    Future<void> beklet(SenkKayit k, String? hata) async {
      final a = '${k.tablo}\u0000${k.anahtar}';
      await db.rawInsert(
          'INSERT OR REPLACE INTO senk_bekleyen (kanal, tablo, anahtar, kayit_json, zaman, deneme, son_hata) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [kanal, k.tablo, k.anahtar, jsonEncode(k.toJson()), simdiUtc(), (denemeler[a] ?? 0) + 1, hata]);
    }

    Future<void> temizle(SenkKayit k) async {
      await db.delete('senk_bekleyen', where: 'kanal = ? AND tablo = ? AND anahtar = ?', whereArgs: [kanal, k.tablo, k.anahtar]);
      await db.delete('senk_hatalar', where: 'kanal = ? AND tablo = ? AND anahtar = ?', whereArgs: [kanal, k.tablo, k.anahtar]);
    }

    var cariDegisti = false;
    await db.rawUpdate('UPDATE senk_durum SET uygulaniyor = 1, kaynak = ? WHERE tek = 1', [kanal]);
    try {
      for (final k in [...ekle, ...sil]) {
        await db.execute('SAVEPOINT senk_kayit');
        try {
          final uygulandi = await _uygulaTek(k);
          await db.execute('RELEASE senk_kayit');
          await temizle(k);
          if (uygulandi) {
            sonuc.uygulanan++;
            if (k.tablo == 'cariler') cariDegisti = true;
          } else {
            sonuc.atlanan++;
          }
        } on _Atla {
          await db.execute('ROLLBACK TO senk_kayit');
          await db.execute('RELEASE senk_kayit');
          await temizle(k);
          sonuc.atlanan++;
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
          await db.insert('senk_hatalar',
              {'zaman': simdiUtc(), 'kanal': kanal, 'tablo': k.tablo, 'anahtar': k.anahtar, 'mesaj': mesaj, 'kayit_json': jsonEncode(k.toJson())});
          sonuc.hatali++;
        }
      }
    } finally {
      await db.rawUpdate('UPDATE senk_durum SET uygulaniyor = 0, kaynak = NULL, uzak_cihaz = NULL, zaman = NULL WHERE tek = 1');
    }
    // Aşağıdakiler YEREL değişikliktir (günlüğe yazılır, diğer telefonlara gider).
    if (cariDegisti) await rotaDuzelt(db);
    for (final ay in _degisenKapaliAylar.toList()..sort()) {
      final aylar = await DonemServisi.bordroyuYenile(db, ay);
      _uyarilar.add(('donemler', ay,
          'Kapalı $ay ayına başka telefondan geç kayıt geldi (o telefon kapanışı görmeden girmişti). '
              '${aylar.join(', ')} bordrosu yeniden hesaplandı; ödeme yaptıysanız kontrol edin.'));
    }
    for (final (t, a, m) in _uyarilar) {
      await db.insert('senk_hatalar', {'zaman': simdiUtc(), 'kanal': uyariKanali, 'tablo': t, 'anahtar': a, 'mesaj': m});
    }
    sonuc.uyari = _uyarilar.length;
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

  static bool _esit(Object? a, Object? b) {
    if (a is num || b is num) return _sayi(a) == _sayi(b);
    return (a ?? '').toString() == (b ?? '').toString();
  }

  static bool _dolu(Object? v) => v != null && !(v is num && v == 0) && v != '';

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
      if (id == null) {
        // Ebeveyn bu cihazda silinmiş → kayıt artık geçersiz (sonsuza kadar beklemesin).
        if ((await _mezarZamani(e.value, a)).isNotEmpty) throw const _Atla();
        throw _Bekle('${e.value} henüz yok');
      }
      veri[e.key] = id;
    }
    return veri;
  }

  // ── Kapalı dönem ──
  Future<Set<String>> _kapalilar() async =>
      _kapaliAylar ??= {for (final r in await db.query('donemler', columns: ['ay'], where: "durum = 'kapali'")) r['ay'] as String};

  Future<String?> _kapaliAyi(String tablo, Map<String, Object?>? satir) async {
    final s = donemAyiSutunu[tablo];
    final v = s == null ? null : satir?[s] as String?;
    if (v == null || v.length < 7) return null;
    final ay = v.substring(0, 7);
    return (await _kapalilar()).contains(ay) ? ay : null;
  }

  Future<bool> _carininKapaliKaydiVar(int cariId) async {
    if ((await _kapalilar()).isEmpty) return false;
    final r = await db.rawQuery('''
      SELECT EXISTS (SELECT 1 FROM donemler d WHERE d.durum = 'kapali' AND (
        EXISTS (SELECT 1 FROM sutler x WHERE x.cari_id = ? AND substr(x.tarih, 1, 7) = d.ay) OR
        EXISTS (SELECT 1 FROM yemler x WHERE x.cari_id = ? AND substr(x.tarih, 1, 7) = d.ay) OR
        EXISTS (SELECT 1 FROM cari_odemeler x WHERE x.cari_id = ? AND substr(x.tarih, 1, 7) = d.ay) OR
        EXISTS (SELECT 1 FROM cari_fiyatlar x WHERE x.cari_id = ? AND substr(x.ay, 1, 7) = d.ay))) AS v''', [cariId, cariId, cariId, cariId]);
    return (r.first['v'] as int?) == 1;
  }

  /// Uzaktan gelen SİLME kapalı dönemdeki kaydı siliyorsa: silinmez, korunur ve karşıya geri
  /// gönderilir (kapanışı görmeden silen telefonda kayıt geri gelir). Gruplu tablolarda dolu
  /// grupların zamanı "şimdi" yapılır ki karşıdaki silmeyi yensin.
  Future<void> _korumaliGeriGonder(String tablo, String anahtar, Map<String, Object?> mevcut, String neden) async {
    final g = alanGruplari[tablo];
    if (g != null) {
      final simdi = simdiUtc();
      final guncel = <String, Object?>{
        for (final e in g.entries)
          if (tablo == 'cariler' || e.value.any((c) => _dolu(mevcut[c]))) e.key: simdi,
      };
      if (guncel.isNotEmpty) {
        await db.rawUpdate('UPDATE senk_durum SET kapali = 1 WHERE tek = 1');
        try {
          await db.update(tablo, guncel, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
        } finally {
          await db.rawUpdate('UPDATE senk_durum SET kapali = 0 WHERE tek = 1');
        }
      }
    }
    await _yerelGunluk(tablo, anahtar, 'y');
    _uyarilar.add((tablo, anahtar, neden));
  }

  /// Bu cihazın değişikliği olarak günlüğe yazar (kaynak boş → tüm kanallara gider).
  Future<void> _yerelGunluk(String tablo, String anahtar, String islem, {String? tz}) => db.rawInsert(
      'INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz, kaynak, tz) SELECT ?, ?, ?, ?, yerel_cihaz, NULL, ? FROM senk_durum WHERE tek = 1',
      [tablo, anahtar, islem, simdiUtc(), tz]);

  /// true: yazıldı · false: yerel hali daha yeni/aynı, atlandı.
  Future<bool> _uygulaTek(SenkKayit k) async {
    final yerelSon =
        await db.rawQuery('SELECT zaman, cihaz FROM senk_gunluk WHERE tablo = ? AND anahtar = ? ORDER BY id DESC LIMIT 1', [k.tablo, k.anahtar]);
    final satirYeni = yerelSon.isEmpty || k.yenidir(yerelSon.first['zaman'] as String, yerelSon.first['cihaz'] as String);
    if (grupluMu(k.tablo)) return _grupBirlestir(k, satirYeni);
    if (!satirYeni) return false;
    await db.rawUpdate('UPDATE senk_durum SET zaman = ?, uzak_cihaz = ? WHERE tek = 1', [k.zaman, k.cihaz]);

    final mevcut = await _satir(k.tablo, k.anahtar);
    if (k.silindi) {
      if (mevcut == null) {
        await _gunlugeElle(k, 's');
        return true;
      }
      final ay = await _kapaliAyi(k.tablo, mevcut);
      if (ay != null) {
        await _korumaliGeriGonder(k.tablo, k.anahtar, mevcut,
            'Başka telefon KAPALI $ay ayındaki bir kaydı silmek istedi (kapanışı görmeden). Kayıt korundu ve geri gönderildi.');
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
    final ay = await _kapaliAyi(k.tablo, veri) ?? await _kapaliAyi(k.tablo, mevcut);
    if (ay != null) _degisenKapaliAylar.add(ay);
    _onbellekTemizle(k.tablo);
    return true;
  }

  /// GRUPLU BİRLEŞME (süt, cari fiyatı, cari) — bkz. senk_tablolari.dart [alanGruplari].
  ///  • İki tarafta da satır varsa: her grupta daha yeni olan kalır.
  ///  • Bir tarafta SİLİNMİŞSE (mezar taşı zamanı): süt/fiyatta silmeden yeni gruplar kalır,
  ///    eskiler boşalır; caride silmeden yeni bir değişiklik varsa satır bütünüyle kalır.
  ///  • Sonuç gelenden farklıysa (bu cihazda daha yeni bilgi vardı) sonuç YEREL değişiklik olarak
  ///    yeniden gönderilir → tüm telefonlar aynı sonuca varır. Silme, gerçek silme zamanıyla gider.
  Future<bool> _grupBirlestir(SenkKayit k, bool satirYeni) async {
    final t = k.tablo;
    final gruplar = alanGruplari[t]!;
    await db.rawUpdate('UPDATE senk_durum SET zaman = ?, uzak_cihaz = ? WHERE tek = 1', [k.zaman, k.cihaz]);
    final mevcut = await _satir(t, k.anahtar);
    final gelen = k.silindi ? null : await _veriHazirla(k);
    final tL = mevcut == null ? await _mezarZamani(t, k.anahtar) : '';
    final tG = k.silindi ? k.silmeZamani : '';
    final kolonlar = (await _kolonlarOf(t)).where((c) => c != 'id').toList();

    // Gelen grup kazanır mı? (zamanlar eşitse satır düzeyindeki sıra karar verir)
    bool gelenKazanir(String z) {
      final a = gelen != null ? ((gelen[z] as String?) ?? '') : tG;
      final b = mevcut != null ? ((mevcut[z] as String?) ?? '') : tL;
      return a.compareTo(b) > 0 || (a == b && satirYeni);
    }

    String enYeni(Map<String, Object?> s) => gruplar.keys.map((z) => (s[z] as String?) ?? '').fold('', (a, b) => a.compareTo(b) >= 0 ? a : b);

    if (mevcut == null && gelen == null) {
      // İki tarafta da yok: yalnız daha yeni silme zamanı not edilir.
      if (tG.compareTo(tL) > 0) {
        await _gunlugeElle(k, 's', tz: tG);
        return true;
      }
      return false;
    }

    bool sonucVar;
    final sonuc = <String, Object?>{};
    if (mevcut != null && gelen != null) {
      sonucVar = true;
      for (final c in kolonlar) {
        sonuc[c] = (satirYeni && gelen.containsKey(c)) ? gelen[c] : mevcut[c];
      }
      for (final e in gruplar.entries) {
        final kaynak = gelenKazanir(e.key) ? gelen : mevcut;
        for (final c in [e.key, ...e.value]) {
          sonuc[c] = kaynak[c];
        }
        // Aynı grubu iki telefon AYRI ayrı doldurmuş (ör. aynı öğüne farklı kg): kullanıcıya not.
        if (t != 'cariler' &&
            e.value.any((c) => _dolu(gelen[c]) && _dolu(mevcut[c]) && !_esit(gelen[c], mevcut[c])) &&
            _dolu(gelen[e.key]) &&
            _dolu(mevcut[e.key]) &&
            gelen[e.key] != mevcut[e.key]) {
          _uyarilar.add((t, k.anahtar, await _cakismaMetni(t, mevcut, e.value, gelen, kaynak)));
        }
      }
    } else {
      final varOlan = (mevcut ?? gelen)!;
      final gelenVar = gelen != null;
      for (final c in kolonlar) {
        if (varOlan.containsKey(c)) sonuc[c] = varOlan[c]; // olmayan sütun yazılmaz (varsayılanı kalsın)
      }
      if (parcaliSilinir.contains(t)) {
        sonucVar = false;
        final mezar = gelenVar ? tL : tG;
        for (final e in gruplar.entries) {
          final varOlanKazanir = gelenVar ? gelenKazanir(e.key) : !gelenKazanir(e.key);
          if (varOlanKazanir) {
            sonucVar = true;
          } else {
            for (final c in e.value) {
              sonuc[c] = 0.0;
            }
            sonuc[e.key] = mezar;
          }
        }
      } else {
        final mx = enYeni(varOlan);
        final mezar = gelenVar ? tL : tG;
        sonucVar = mx.compareTo(mezar) > 0 || (mx == mezar && (gelenVar ? satirYeni : !satirYeni));
      }
    }
    if (t == 'sutler') sonuc['toplam'] = _sayi(sonuc['sabah']) + _sayi(sonuc['aksam']);

    // Kapalı dönem: uzaktan gelen silme kapalı aydaki kaydı (ya da kapalı ayda kaydı olan cariyi) silemez.
    if (mevcut != null && !sonucVar) {
      final ay = await _kapaliAyi(t, mevcut);
      if (ay != null) {
        await _korumaliGeriGonder(t, k.anahtar, mevcut,
            'Başka telefon KAPALI $ay ayındaki bir kaydı silmek istedi (kapanışı görmeden). Kayıt korundu ve geri gönderildi.');
        return true;
      }
      if (t == 'cariler' && await _carininKapaliKaydiVar(mevcut['id'] as int)) {
        await _korumaliGeriGonder(t, k.anahtar, mevcut,
            'Başka telefon, KAPALI dönemde kaydı olan "${mevcut['ad']} ${mevcut['soyad']}" carisini silmek istedi. '
                'Cari korundu ve geri gönderildi (silmek yerine pasife alın).');
        return true;
      }
    }

    // Yerel veritabanına yaz.
    var degisti = false;
    if (sonucVar && mevcut != null) {
      final fark = {
        for (final c in kolonlar)
          if (c != 'uuid' && sonuc.containsKey(c) && !_esit(sonuc[c], mevcut[c])) c: sonuc[c],
      };
      if (fark.isNotEmpty) {
        await db.update(t, fark, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
        degisti = true;
      }
    } else if (sonucVar) {
      if (!dogalMi(t)) sonuc['uuid'] = k.anahtar;
      await db.insert(t, sonuc);
      degisti = true;
    } else if (mevcut != null) {
      await db.delete(t, where: 'rowid = ?', whereArgs: [mevcut['_rowid']]);
      await db.rawUpdate('UPDATE senk_gunluk SET tz = ? WHERE id = (SELECT MAX(id) FROM senk_gunluk WHERE tablo = ? AND anahtar = ?)',
          [tG, t, k.anahtar]);
      degisti = true;
    }
    if (degisti) {
      final ay = await _kapaliAyi(t, sonucVar ? sonuc : mevcut);
      if (ay != null) _degisenKapaliAylar.add(ay);
      _onbellekTemizle(t);
    }

    // Sonuç gelenden farklıysa bu cihazın bildiği daha yeni bilgi karşıya geri gönderilir.
    bool gelenleAyni;
    if (gelen == null) {
      gelenleAyni = !sonucVar;
    } else {
      gelenleAyni = sonucVar && gruplar.entries.every((e) => _esit(sonuc[e.key], gelen[e.key]) && e.value.every((c) => _esit(sonuc[c], gelen[c])));
    }
    if (!gelenleAyni) {
      await _yerelGunluk(t, k.anahtar, sonucVar ? 'y' : 's', tz: sonucVar ? null : (mevcut == null ? tL : tG));
      return true;
    }
    return degisti;
  }

  Future<String> _cakismaMetni(
      String t, Map<String, Object?> yerel, List<String> kolonlar, Map<String, Object?> gelen, Map<String, Object?> kazanan) async {
    final cari = await db.query('cariler', columns: ['ad', 'soyad'], where: 'id = ?', whereArgs: [yerel['cari_id']]);
    final ad = cari.isEmpty ? '' : '${cari.first['ad']} ${cari.first['soyad']}'.trim();
    String deger(Map<String, Object?> s) => kolonlar.map((c) => '${s[c] ?? 0}').join('/');
    final ne = t == 'sutler' ? '${yerel['tarih']} ${kolonlar.first == 'sabah' ? 'sabah' : 'akşam'} sütü' : '${yerel['ay']} fiyatı';
    return 'Çakışma: $ad $ne iki telefonda farklı girildi (bu telefon ${deger(yerel)}, diğeri ${deger(gelen)}). '
        'Son girilen ${deger(kazanan)} geçerli oldu; doğru değilse Cari Detay → Düzenle ile düzeltin.';
  }

  void _onbellekTemizle(String tablo) {
    _anahtarOnbellek.remove(tablo);
    _idOnbellek.remove(tablo);
  }

  Future<void> _gunlugeElle(SenkKayit k, String islem, {String? tz}) => db.rawInsert(
      'INSERT INTO senk_gunluk (tablo, anahtar, islem, zaman, cihaz, kaynak, tz) SELECT ?, ?, ?, ?, ?, kaynak, ? FROM senk_durum WHERE tek = 1',
      [k.tablo, k.anahtar, islem, k.zaman, k.cihaz, tz ?? (islem == 's' ? k.silmeZamani : null)]);

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

  /// Eskimiş günlük satırlarını siler (her kayıt için yalnız SON değişiklik — silmelerde mezar taşı — kalır).
  Future<int> budama() => db.rawDelete('DELETE FROM senk_gunluk WHERE id NOT IN (SELECT MAX(id) FROM senk_gunluk GROUP BY tablo, anahtar)');

  /// YEDEKTEN GERİ YÜKLEME (JSON ya da .db) sonrası: günlük "taban" zamanla yeniden kurulur,
  /// kanal sayaçları sıfırlanır. Geri yüklenen eski veri diğer cihazlardaki DAHA YENİ kayıtları
  /// ezmez/silmez; onlar bu cihaza geri gelir. Grup zamanları korunur (yedekte varsa); başka
  /// telefonda sonradan SİLİNMİŞ kayıt, o telefonun mezar taşı daha yeni olduğundan geri gelmez.
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
    // Yerel ağ: bu telefon "tam" ister (kendi eski kayıtlarının son halini de alır); ana cihazsa
    // yeni taban nesli bağlı telefonlara "her şeyini yeniden gönder" der.
    await db.rawInsert("INSERT OR REPLACE INTO senk_ayarlar (anahtar, deger) VALUES ('tam_yeniden', '1')");
    await db.rawInsert("INSERT OR REPLACE INTO senk_ayarlar (anahtar, deger) VALUES ('taban_nesil', ?)", [simdiUtc()]);
  }
}
