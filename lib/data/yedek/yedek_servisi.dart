import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Yedek okunamadığında / uygulanamadığında fırlatılır. Mesaj doğrudan
/// kullanıcıya gösterilebilir. Bu hata fırlatıldığında veritabanında
/// HİÇBİR değişiklik yapılmamış olur (transaction geri alınır).
class YedekHatasi implements Exception {
  final String mesaj;
  const YedekHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// İçe aktarma sonucu: tablo başına işlenen satır sayısı.
class YedekOzeti {
  final Map<String, int> tabloSayilari;
  const YedekOzeti(this.tabloSayilari);
  int get toplam => tabloSayilari.values.fold(0, (a, b) => a + b);
}

/// ─────────────────────────────────────────────────────────────
/// YEDEK SERVİSİ — JSON yedek alma / geri yükleme için TEK kaynak
/// ─────────────────────────────────────────────────────────────
///
/// Eski Bluetooth ve JSON içe aktarma kodundaki iki ciddi hata burada
/// giderilmiştir:
///
/// 1. Yedek yalnızca cariler/sutler/yemler içeriyordu; ödeme, tahsilat ve
///    cari fiyatları YEDEKLENMİYORDU.
/// 2. İçe aktarma `INSERT OR REPLACE` kullanıyordu. SQLite'ta REPLACE,
///    çakışan satırı önce SİLER; yabancı anahtarlar `ON DELETE CASCADE`
///    olduğundan bir cariyi "yeniden yazmak" o carinin TÜM ödeme ve fiyat
///    kayıtlarını sessizce siliyordu. Ayrıca satır hataları yutuluyor,
///    yarım kalmış bir geri yükleme "başarılı" görünüyordu.
///
/// Artık: tüm iş tabloları yedeklenir; içe aktarma tek transaction'dır
/// (ya hep ya hiç), REPLACE kullanılmaz, her hata geri alma ile sonuçlanır.
class YedekServisi {
  YedekServisi._();

  static const uygulamaKodu = 'sut_yem';

  /// v1: yalnızca cariler/sutler/yemler. v2: tüm iş tabloları.
  /// v3: + dönemler ve kapanmış dönem bordroları.
  static const formatSurumu = 3;

  /// Yabancı anahtar sırasına göre (önce ebeveyn tablo).
  static const tablolar = [
    'cariler',
    'cari_fiyatlar',
    'fiyatlar',
    'sutler',
    'yemler',
    'cari_odemeler',
    'donemler',
    'donem_hakedisleri',
  ];

  /// "Tam yedek" sayılmak için gereken tablolar (format v2). Dönem
  /// tabloları sonradan eklendi; onları içermeyen v2 yedeği de tamdır
  /// (geri yüklenince dönemler açık kalır, veri kaybı olmaz).
  static const _zorunluTablolar = [
    'cariler',
    'cari_fiyatlar',
    'fiyatlar',
    'sutler',
    'yemler',
    'cari_odemeler',
  ];

  /// Tarih sütunu gün biçiminde (`yyyy-MM-dd`) tutulan tablolar.
  static const _gunTarihliTablolar = {'sutler', 'yemler', 'cari_odemeler'};

  // ──────────────────────────────────────────
  // DIŞA AKTAR
  // ──────────────────────────────────────────

  static Future<Map<String, dynamic>> disaAktar(DatabaseExecutor db) async {
    final veri = <String, dynamic>{};
    final sayilar = <String, int>{};
    for (final tablo in tablolar) {
      final satirlar = await db.query(tablo, orderBy: 'id ASC');
      veri[tablo] = satirlar;
      sayilar[tablo] = satirlar.length;
    }
    final surum = Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;
    veri['meta'] = {
      'app': uygulamaKodu,
      'format_version': formatSurumu,
      'schema_version': surum,
      'created_at': DateTime.now().toIso8601String(),
      'total_records': sayilar.values.fold(0, (a, b) => a + b),
      'tables': sayilar,
    };
    return veri;
  }

  /// [db] bir [Database] ise tablolar TEK transaction içinde okunur: yedek
  /// alınırken bir kayıt yazılsa bile yedek tutarlı bir anlık görüntüdür
  /// (ör. süt kaydı var ama ödemesi yarım değil).
  static Future<String> disaAktarJson(DatabaseExecutor db) async {
    final veri = db is Database
        ? await db.transaction((txn) => disaAktar(txn))
        : await disaAktar(db);
    return jsonEncode(veri);
  }

  // ──────────────────────────────────────────
  // DOĞRULA / ÇÖZ
  // ──────────────────────────────────────────

  /// JSON metnini çözer ve yapısını doğrular.
  static Map<String, dynamic> coz(String jsonMetni) {
    final Object? veri;
    try {
      veri = jsonDecode(jsonMetni);
    } on FormatException {
      throw const YedekHatasi('Dosya geçerli bir JSON değil.');
    }
    if (veri is! Map<String, dynamic> || veri['meta'] is! Map) {
      throw const YedekHatasi('Bu dosya bir Süt-Yem yedeği değil (meta bilgisi yok).');
    }
    if (veri['cariler'] is! List) {
      throw const YedekHatasi('Yedekte cari listesi bulunamadı.');
    }
    for (final tablo in tablolar) {
      final liste = veri[tablo];
      if (liste == null) continue;
      if (liste is! List || liste.any((s) => s is! Map)) {
        throw YedekHatasi('Yedekteki "$tablo" bölümü bozuk.');
      }
    }
    return veri;
  }

  /// Yedek tüm iş tablolarını içeriyor mu? (v2 ve sonrası)
  static bool tamYedekMi(Map<String, dynamic> veri) =>
      _zorunluTablolar.every((t) => veri[t] is List);

  // ──────────────────────────────────────────
  // İÇE AKTAR
  // ──────────────────────────────────────────

  /// Yedeği veritabanına uygular.
  ///
  /// [tamamenDegistir] = false (varsayılan, "geri yükle/birleştir"):
  ///   `id`'si eşleşen satırlar güncellenir, yeniler eklenir; yedekte
  ///   olmayan mevcut kayıtlara DOKUNULMAZ. Aynı cihazın yedeğini geri
  ///   yüklemek için uygundur.
  ///
  /// [tamamenDegistir] = true ("cihazdan cihaza aktarım"):
  ///   Mevcut tüm iş verileri silinir ve yedektekiler konur. Yalnızca
  ///   [tamYedekMi] olan yedeklerde izinlidir — eski biçimli bir yedekle
  ///   tamamen değiştirme, ödeme ve fiyat kayıtlarını kaybettirirdi.
  static Future<YedekOzeti> iceAktar(
    Database db,
    Map<String, dynamic> veri, {
    bool tamamenDegistir = false,
  }) async {
    if (tamamenDegistir && !tamYedekMi(veri)) {
      throw const YedekHatasi(
        'Bu yedek eski biçimde: ödeme, tahsilat ve fiyat kayıtlarını içermiyor. '
        'Mevcut verilerin kaybolmaması için aktarım durduruldu. '
        'Gönderen cihazdaki uygulamayı güncelleyip yeniden yedek alın.',
      );
    }

    return db.transaction((txn) async {
      if (tamamenDegistir) {
        // Kapalı dönem kilidi (tetikleyiciler) silmeyi engellemesin; yedekteki
        // dönem durumları aşağıda yeniden yazılır.
        await txn.update('donemler', {'durum': 'acik'});
        for (final tablo in tablolar.reversed) {
          await txn.delete(tablo);
        }
      }

      final sayilar = <String, int>{};
      for (final tablo in tablolar) {
        final satirlar = veri[tablo];
        if (satirlar is! List) continue;
        final kolonlar = await _kolonlar(txn, tablo);
        var sira = 0;
        for (final ham in satirlar) {
          sira++;
          final satir = _temizle(tablo, Map<String, dynamic>.from(ham as Map), kolonlar);
          try {
            await _yaz(txn, tablo, satir);
          } on DatabaseException catch (e) {
            throw YedekHatasi(
              '"$tablo" tablosunun $sira. kaydı aktarılamadı, hiçbir değişiklik yapılmadı. '
              'Ayrıntı: ${_kisaHata(e)}',
            );
          }
        }
        sayilar[tablo] = satirlar.length;
      }
      return YedekOzeti(sayilar);
    });
  }

  static Future<Set<String>> _kolonlar(DatabaseExecutor db, String tablo) async {
    final bilgi = await db.rawQuery('PRAGMA table_info($tablo)');
    return {for (final k in bilgi) k['name'] as String};
  }

  /// Yalnızca hedef tabloda var olan sütunları alır (farklı şema
  /// sürümleri arasında aktarım), boş metinleri null yapar ve tarihleri
  /// gün biçimine indirger.
  static Map<String, Object?> _temizle(
    String tablo,
    Map<String, dynamic> satir,
    Set<String> kolonlar,
  ) {
    final temiz = <String, Object?>{};
    satir.forEach((anahtar, deger) {
      if (!kolonlar.contains(anahtar)) return;
      if (deger is String && deger.isEmpty) {
        temiz[anahtar] = null;
      } else if (deger is num || deger is String || deger == null) {
        temiz[anahtar] = deger;
      } else if (deger is bool) {
        temiz[anahtar] = deger ? 1 : 0;
      } else {
        temiz[anahtar] = deger.toString();
      }
    });
    final tarih = temiz['tarih'];
    if (_gunTarihliTablolar.contains(tablo) && tarih is String && tarih.length > 10) {
      temiz['tarih'] = tarih.substring(0, 10);
    }
    return temiz;
  }

  /// REPLACE KULLANMADAN upsert: önce `id` ile güncellemeyi dener, sonra
  /// doğal anahtarla (süt: cari+gün, fiyat: cari+ay), olmazsa ekler.
  static Future<void> _yaz(Transaction txn, String tablo, Map<String, Object?> satir) async {
    final id = satir['id'];
    final idsiz = Map<String, Object?>.from(satir)..remove('id');

    if (id != null) {
      final guncellenen = await txn.update(tablo, idsiz, where: 'id = ?', whereArgs: [id]);
      if (guncellenen > 0) return;
    }

    final dogalAnahtar = switch (tablo) {
      'sutler' => ['cari_id', 'tarih'],
      'cari_fiyatlar' => ['cari_id', 'ay'],
      'donemler' => ['ay'],
      'donem_hakedisleri' => ['donem_id', 'cari_id'],
      _ => const <String>[],
    };
    if (dogalAnahtar.isNotEmpty && dogalAnahtar.every((k) => satir[k] != null)) {
      final guncellenen = await txn.update(
        tablo,
        idsiz,
        where: dogalAnahtar.map((k) => '$k = ?').join(' AND '),
        whereArgs: [for (final k in dogalAnahtar) satir[k]],
      );
      if (guncellenen > 0) return;
    }

    await txn.insert(tablo, satir);
  }

  static String _kisaHata(DatabaseException e) {
    final metin = e.toString();
    if (metin.contains('DONEM_KAPALI')) return 'kaydın tarihi bu cihazda kapatılmış bir döneme ait';
    if (metin.contains('FOREIGN KEY')) return 'kaydın bağlı olduğu cari yedekte yok';
    if (metin.contains('NOT NULL')) return 'zorunlu bir alan boş';
    if (metin.contains('UNIQUE')) return 'aynı kayıt iki kez var';
    return metin.length > 160 ? '${metin.substring(0, 160)}…' : metin;
  }
}
