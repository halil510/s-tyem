import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/cari_model.dart';
import 'uretici_fisi.dart';

/// Fiş yazıcısı ayarları (cihazda saklanır).
class FisAyarlari {
  final String? yaziciAdres;
  final String? yaziciAdi;

  /// Satırdaki karakter sayısı: 32 (58 mm), 40 (80 mm — varsayılan) veya 48 (80 mm geniş).
  final int genislik;
  final String isletmeAdi;
  final bool turkceKodSayfasi;

  const FisAyarlari({
    this.yaziciAdres,
    this.yaziciAdi,
    this.genislik = 40,
    this.isletmeAdi = '',
    this.turkceKodSayfasi = false,
  });

  static const gecerliGenislikler = [32, 40, 48];

  bool get yaziciSecili => yaziciAdres != null && yaziciAdres!.isNotEmpty;

  static const _adres = 'fis_yazici_adres',
      _ad = 'fis_yazici_adi',
      _genislik = 'fis_genislik',
      _isletme = 'fis_isletme_adi',
      _turkce = 'fis_turkce_kod_sayfasi';

  static Future<FisAyarlari> yukle() async {
    final p = await SharedPreferences.getInstance();
    return FisAyarlari(
      yaziciAdres: p.getString(_adres),
      yaziciAdi: p.getString(_ad),
      genislik: gecerliGenislikler.contains(p.getInt(_genislik)) ? p.getInt(_genislik)! : 40,
      isletmeAdi: p.getString(_isletme) ?? '',
      turkceKodSayfasi: p.getBool(_turkce) ?? false,
    );
  }

  Future<void> kaydet() async {
    final p = await SharedPreferences.getInstance();
    if (yaziciSecili) {
      await p.setString(_adres, yaziciAdres!);
      await p.setString(_ad, yaziciAdi ?? yaziciAdres!);
    } else {
      await p.remove(_adres);
      await p.remove(_ad);
    }
    await p.setInt(_genislik, genislik);
    await p.setString(_isletme, isletmeAdi.trim());
    await p.setBool(_turkce, turkceKodSayfasi);
  }

  FisAyarlari kopyala({
    String? yaziciAdres,
    String? yaziciAdi,
    int? genislik,
    String? isletmeAdi,
    bool? turkceKodSayfasi,
  }) =>
      FisAyarlari(
        yaziciAdres: yaziciAdres ?? this.yaziciAdres,
        yaziciAdi: yaziciAdi ?? this.yaziciAdi,
        genislik: genislik ?? this.genislik,
        isletmeAdi: isletmeAdi ?? this.isletmeAdi,
        turkceKodSayfasi: turkceKodSayfasi ?? this.turkceKodSayfasi,
      );
}

class YaziciHatasi implements Exception {
  final String mesaj;
  const YaziciHatasi(this.mesaj);
  @override
  String toString() => mesaj;
}

/// Bluetooth termal yazıcıya baytları gönderir (Android: TermalYazici.kt).
/// Terazinin bağlantısını kullanmaz; her fiş için ayrı bağlanıp kapatır.
class TermalYaziciServisi {
  static const _kanal = MethodChannel('termal_yazici');

  static Future<void> yazdir(FisAyarlari ayar, List<FisSatiri> satirlar) async {
    if (!ayar.yaziciSecili) throw const YaziciHatasi('Önce fiş yazıcısını seçin.');
    final baytlar = EscPos.fis(satirlar, turkceKodSayfasi: ayar.turkceKodSayfasi);
    try {
      await _kanal.invokeMethod<bool>('yazdir', {
        'address': ayar.yaziciAdres,
        'bytes': Uint8List.fromList(baytlar),
      });
    } on PlatformException catch (e) {
      throw YaziciHatasi(switch (e.code) {
        'MESGUL' => 'Yazıcı önceki fişi yazdırıyor, birazdan tekrar deneyin.',
        'IZIN' => 'Bluetooth izni verilmemiş.',
        _ => 'Yazıcıya bağlanılamadı (${ayar.yaziciAdi ?? ayar.yaziciAdres}). '
            'Yazıcı açık ve eşleştirilmiş mi?',
      });
    } on MissingPluginException {
      throw const YaziciHatasi('Fiş yazdırma bu cihazda desteklenmiyor.');
    }
  }
}

/// Bir carinin bir günlük süt kaydından fiş üretir; o gün kayıt yoksa null.
Future<UreticiFisi?> sutFisiOlustur(
  DatabaseExecutor db, {
  required Cari cari,
  required String tarih, // yyyy-MM-dd
  required String isletmeAdi,
  DateTime? simdi,
}) async {
  final kayit = await db.query('sutler',
      where: 'cari_id = ? AND tarih = ?', whereArgs: [cari.id, tarih], limit: 1);
  if (kayit.isEmpty) return null;
  final ayBasi = '${tarih.substring(0, 7)}-01';
  final ay = await db.rawQuery(
    'SELECT COALESCE(SUM(toplam), 0) AS t FROM sutler WHERE cari_id = ? AND tarih BETWEEN ? AND ?',
    [cari.id, ayBasi, tarih],
  );
  final k = kayit.first;
  return UreticiFisi(
    isletmeAdi: isletmeAdi,
    fisNo: k['id'] as int?,
    tarih: DateFormat('yyyy-MM-dd').parse(tarih),
    basimZamani: simdi ?? DateTime.now(),
    ureticiAdi: '${cari.ad} ${cari.soyad}',
    sabah: (k['sabah'] as num?)?.toDouble() ?? 0,
    aksam: (k['aksam'] as num?)?.toDouble() ?? 0,
    buAyKg: (ay.first['t'] as num?)?.toDouble() ?? 0,
  );
}
