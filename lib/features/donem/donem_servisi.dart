import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/repositories/denetim_kaydi.dart';
export '../../data/repositories/donem_kilidi.dart';
import '../../models/cari_fiyat_model.dart';
import '../../models/sut_model.dart';
import '../../models/yem_model.dart';
import '../../utils/sayi_format.dart';
import '../cari_hesap/models/cari_fiyat_lookup.dart';
import '../cari_hesap/providers/cari_hesap_providers.dart' show donemSutFiyati, sutTutari, yemTutari;

/// Dönem işlemi kurala aykırı (ör. bitmemiş ay kapatılmak istendi).
class DonemIslemHatasi implements Exception {
  final String mesaj;
  const DonemIslemHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Bir carinin bir aylık hakedişi.
/// dönem sonu = devir + (süt + tahsilat) − (yem + ödeme).
/// Pozitif: işletme üreticiye ödeyecek; negatif: üretici borçlu.
class HakedisSatiri {
  final int cariId;
  final double devir;
  final double sutKg;
  final double sutFiyat;
  final double sutTutar;
  final double yemKg;
  final double yemTutar;
  final double odeme;
  final double tahsilat;
  final bool fiyatEksik;

  const HakedisSatiri({
    required this.cariId,
    this.devir = 0,
    this.sutKg = 0,
    this.sutFiyat = 0,
    this.sutTutar = 0,
    this.yemKg = 0,
    this.yemTutar = 0,
    this.odeme = 0,
    this.tahsilat = 0,
    this.fiyatEksik = false,
  });

  double get ayNet => kurusaYuvarla((sutTutar + tahsilat) - (yemTutar + odeme));
  double get donemSonu => kurusaYuvarla(devir + ayNet);

  Map<String, Object?> toMap(int donemId) => {
        'donem_id': donemId,
        'cari_id': cariId,
        'devir': devir,
        'sut_kg': sutKg,
        'sut_fiyat': sutFiyat,
        'sut_tutar': sutTutar,
        'yem_kg': yemKg,
        'yem_tutar': yemTutar,
        'odeme': odeme,
        'tahsilat': tahsilat,
        'donem_sonu': donemSonu,
      };

  factory HakedisSatiri.fromMap(Map<String, Object?> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return HakedisSatiri(
      cariId: m['cari_id'] as int,
      devir: d('devir'),
      sutKg: d('sut_kg'),
      sutFiyat: d('sut_fiyat'),
      sutTutar: d('sut_tutar'),
      yemKg: d('yem_kg'),
      yemTutar: d('yem_tutar'),
      odeme: d('odeme'),
      tahsilat: d('tahsilat'),
    );
  }
}

/// Bir ayın dönem bilgisi.
class DonemBilgisi {
  final String ay;
  final bool kapali;
  final String? kapanisTarihi;
  final int acilisSayisi;

  /// Kapalıysa kapanış anındaki bordro; açıksa canlı hesap.
  final List<HakedisSatiri> satirlar;

  const DonemBilgisi({
    required this.ay,
    required this.kapali,
    this.kapanisTarihi,
    this.acilisSayisi = 0,
    this.satirlar = const [],
  });

  bool get fiyatEksikVar => satirlar.any((s) => s.fiyatEksik);
}

/// Aylık dönem kapanışı ve hakediş.
class DonemServisi {
  final Database db;
  DonemServisi(this.db);

  static final _ayFormat = DateFormat('yyyy-MM');
  static final _ayRegex = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  static String ayAnahtari(DateTime t) => _ayFormat.format(t);

  static void _ayDogrula(String ay) {
    if (!_ayRegex.hasMatch(ay)) throw DonemIslemHatasi('Geçersiz ay: "$ay"');
  }

  Future<Set<String>> kapaliAylar() async {
    final r = await db.query('donemler', columns: ['ay'], where: "durum = 'kapali'");
    return {for (final s in r) s['ay'] as String};
  }

  Future<bool> kapaliMi(String ay) async => (await kapaliAylar()).contains(ay);

  Future<DonemBilgisi> bilgi(String ay) async {
    _ayDogrula(ay);
    final r = await db.query('donemler', where: 'ay = ?', whereArgs: [ay]);
    final kayit = r.isEmpty ? null : r.first;
    final kapali = kayit?['durum'] == 'kapali';
    final satirlar = kapali
        ? (await db.query('donem_hakedisleri',
                where: 'donem_id = ?', whereArgs: [kayit!['id']], orderBy: 'cari_id'))
            .map(HakedisSatiri.fromMap)
            .toList()
        : await hesapla(ay);
    return DonemBilgisi(
      ay: ay,
      kapali: kapali,
      kapanisTarihi: kayit?['kapanis_tarihi'] as String?,
      acilisSayisi: (kayit?['acilis_sayisi'] as int?) ?? 0,
      satirlar: satirlar,
    );
  }

  /// Canlı hakediş hesabı — ekstre/bakiye ile aynı fonksiyonlar
  /// ([sutTutari], [yemTutari]) ve aynı fiyat devralma kuralı.
  Future<List<HakedisSatiri>> hesapla(String ay, [DatabaseExecutor? ex]) async {
    _ayDogrula(ay);
    final e = ex ?? db;
    final bas = '$ay-01', bit = '$ay-31';
    final lookup = CariFiyatLookup(
        (await e.query('cari_fiyatlar')).map((m) => CariFiyat.fromMap(m)).toList());

    final devir = <int, double>{};
    final sutKg = <int, double>{}, sutTl = <int, double>{};
    final yemKg = <int, double>{}, yemTl = <int, double>{};
    final odeme = <int, double>{}, tahsilat = <int, double>{};
    final eksik = <int>{};
    final sutFiyatlari = <int, Set<double>>{};
    void ekle(Map<int, double> m, int id, double v) => m[id] = (m[id] ?? 0) + v;

    for (final m in await e.query('sutler', where: 'tarih <= ?', whereArgs: [bit])) {
      final s = Sut.fromMap(m);
      final fiyat = lookup.fiyatIcin(s.cariId, s.tarih);
      final tutar = sutTutari(s, fiyat);
      if (s.tarih.compareTo(bas) < 0) {
        ekle(devir, s.cariId, tutar);
      } else {
        if (s.toplam > 0) sutFiyatlari.putIfAbsent(s.cariId, () => {}).add(fiyat.sutFiyat);
        if (s.toplam > 0 && tutar <= 0) eksik.add(s.cariId);
        ekle(sutKg, s.cariId, s.toplam);
        ekle(sutTl, s.cariId, tutar);
      }
    }
    for (final m in await e.query('yemler', where: 'tarih <= ?', whereArgs: [bit])) {
      final y = Yem.fromMap(m);
      final tutar = yemTutari(y, lookup.fiyatIcin(y.cariId, y.tarih));
      if (y.tarih.compareTo(bas) < 0) {
        ekle(devir, y.cariId, -tutar);
      } else {
        if (y.toplam > 0 && tutar <= 0) eksik.add(y.cariId);
        ekle(yemKg, y.cariId, y.toplam);
        ekle(yemTl, y.cariId, tutar);
      }
    }
    for (final m in await e.query('cari_odemeler',
        where: "islem_turu IN ('odeme','tahsilat') AND tarih <= ?", whereArgs: [bit])) {
      final id = m['cari_id'] as int;
      final tutar = kurusaYuvarla((m['toplam_tutar'] as num?)?.toDouble() ?? 0);
      final tahsil = m['islem_turu'] == 'tahsilat';
      if ((m['tarih'] as String).compareTo(bas) < 0) {
        ekle(devir, id, tahsil ? tutar : -tutar);
      } else {
        ekle(tahsil ? tahsilat : odeme, id, tutar);
      }
    }

    final idler = {
      ...sutKg.keys, ...yemKg.keys, ...odeme.keys, ...tahsilat.keys,
      ...devir.entries.where((x) => kurusaYuvarla(x.value).abs() >= 0.005).map((x) => x.key),
    }.toList()
      ..sort();
    return [
      for (final id in idler)
        HakedisSatiri(
          cariId: id,
          devir: kurusaYuvarla(devir[id] ?? 0),
          sutKg: sutKg[id] ?? 0,
          sutFiyat: donemSutFiyati(sutFiyatlari[id], sutKg[id] ?? 0, sutTl[id] ?? 0,
              lookup.fiyatIcin(id, ay).sutFiyat),
          sutTutar: kurusaYuvarla(sutTl[id] ?? 0),
          yemKg: yemKg[id] ?? 0,
          yemTutar: kurusaYuvarla(yemTl[id] ?? 0),
          odeme: kurusaYuvarla(odeme[id] ?? 0),
          tahsilat: kurusaYuvarla(tahsilat[id] ?? 0),
          fiyatEksik: eksik.contains(id),
        ),
    ];
  }

  /// Ayı kapatır: bordroyu dondurur ve o aya kayıt girişini kilitler.
  /// Yalnızca bitmiş aylar kapatılabilir; fiyatı eksik cari varsa kapatılmaz.
  Future<DonemBilgisi> kapat(String ay, {DateTime? simdi}) async {
    _ayDogrula(ay);
    final buAy = ayAnahtari(simdi ?? DateTime.now());
    if (ay.compareTo(buAy) >= 0) {
      throw const DonemIslemHatasi('Yalnızca bitmiş aylar kapatılabilir.');
    }

    await db.transaction((txn) async {
      final mevcut = await txn.query('donemler', where: 'ay = ?', whereArgs: [ay]);
      if (mevcut.isNotEmpty && mevcut.first['durum'] == 'kapali') {
        throw const DonemIslemHatasi('Bu dönem zaten kapalı.');
      }

      final satirlar = await hesapla(ay, txn);
      final eksikler = satirlar.where((s) => s.fiyatEksik).length;
      if (eksikler > 0) {
        throw DonemIslemHatasi(
            '$eksikler carinin bu ay fiyatı tanımlı değil. Fiyatları girmeden dönem kapatılamaz.');
      }

      // Devralınan fiyatı bu aya sabitle: önceki ayın fiyatı sonradan
      // değişse bile kapalı ayın tutarı değişmesin (tetikleyici korur).
      final lookup = CariFiyatLookup(
          (await txn.query('cari_fiyatlar')).map((m) => CariFiyat.fromMap(m)).toList());
      for (final s in satirlar) {
        final kendi = await txn.query('cari_fiyatlar',
            where: 'cari_id = ? AND ay = ?', whereArgs: [s.cariId, ay]);
        if (kendi.isEmpty) {
          final f = lookup.fiyatIcin(s.cariId, ay).toMap()
            ..remove('id')
            ..['cari_id'] = s.cariId
            ..['ay'] = ay;
          await txn.insert('cari_fiyatlar', f);
        }
      }

      final zaman = sqliteSimdi();
      final int donemId;
      if (mevcut.isEmpty) {
        donemId = await txn.insert('donemler', {'ay': ay, 'durum': 'acik'});
      } else {
        donemId = mevcut.first['id'] as int;
      }
      for (final s in satirlar) {
        await txn.insert('donem_hakedisleri', s.toMap(donemId));
      }
      await txn.update(
        'donemler',
        {'durum': 'kapali', 'kapanis_tarihi': zaman, 'updated_at': zaman},
        where: 'id = ?',
        whereArgs: [donemId],
      );
      await denetimKaydet(txn,
          tablo: 'donemler',
          kayitId: donemId,
          islem: 'guncelle',
          oncekiDeger: {'ay': ay, 'durum': 'acik'},
          yeniDeger: {'ay': ay, 'durum': 'kapali', 'cari_sayisi': satirlar.length});
    });
    return bilgi(ay);
  }

  /// Kapalı dönemi gerekçeyle yeniden açar. Eski bordro denetim kaydına
  /// yazılır, sonra silinir; dönem yeniden kapatılınca yeniden hesaplanır.
  Future<DonemBilgisi> yenidenAc(String ay, String gerekce) async {
    _ayDogrula(ay);
    final g = gerekce.trim();
    if (g.length < 3) throw const DonemIslemHatasi('Yeniden açma gerekçesi yazılmalı.');

    await db.transaction((txn) async {
      final r = await txn.query('donemler', where: 'ay = ?', whereArgs: [ay]);
      if (r.isEmpty || r.first['durum'] != 'kapali') {
        throw const DonemIslemHatasi('Bu dönem zaten açık.');
      }
      final id = r.first['id'] as int;
      final bordro = await txn.query('donem_hakedisleri', where: 'donem_id = ?', whereArgs: [id]);
      final zaman = sqliteSimdi();
      await txn.update(
        'donemler',
        {
          'durum': 'acik',
          'acilis_sayisi': ((r.first['acilis_sayisi'] as int?) ?? 0) + 1,
          'aciklama': g,
          'updated_at': zaman,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete('donem_hakedisleri', where: 'donem_id = ?', whereArgs: [id]);
      await denetimKaydet(txn,
          tablo: 'donemler',
          kayitId: id,
          islem: 'guncelle',
          oncekiDeger: {'ay': ay, 'durum': 'kapali', 'bordro': jsonEncode(bordro)},
          yeniDeger: {'ay': ay, 'durum': 'acik', 'gerekce': g});
    });
    return bilgi(ay);
  }
}
