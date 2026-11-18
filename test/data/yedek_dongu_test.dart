import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sutyem_pro/core/database/app_database.dart';
import 'package:sutyem_pro/data/repositories/veri_yonetimi_repository.dart';
import 'package:sutyem_pro/data/yedek/otomatik_yedek.dart';
import 'package:sutyem_pro/data/yedek/yedek_servisi.dart';

/// ELLE YEDEK → TEMİZLE → GERİ YÜKLE döngüsü, gerçek dosya veritabanıyla
/// (ekranların kullandığı yollarla aynı: tutarliKopyala, dosyayiDegistir,
/// iceAktar). Geri yükleme sonrası her iş tablosu birebir aynı olmalı.
void main() {
  late Directory klasor;
  late AppDatabase app;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    klasor = await Directory.systemTemp.createTemp('sutyem_dongu_');
    app = AppDatabase.test(factory: databaseFactoryFfi, klasor: klasor.path);
  });

  tearDown(() async {
    await app.close();
    try {
      await klasor.delete(recursive: true);
    } catch (_) {}
  });

  const isTablolari = [
    'cariler', 'cari_fiyatlar', 'fiyatlar', 'sutler', 'yemler', 'cari_odemeler', 'donemler', 'donem_hakedisleri',
  ];

  /// Karşılaştırma için tablo içerikleri (zaman damgası gibi yedekle değişmeyen her sütun dahil).
  Future<Map<String, List<Map<String, Object?>>>> goruntu(Database db) async => {
        for (final t in isTablolari) t: await db.query(t, orderBy: 'id'),
      };

  Future<Database> ornekVeri() async {
    final db = await app.database;
    final ali = await db.insert('cariler', {'ad': 'Ali', 'soyad': 'Şahin', 'telefon': '05550000001'});
    final ayse = await db.insert('cariler', {'ad': 'Ayşe', 'soyad': 'Öztürk'});
    await db.insert('cari_fiyatlar', {'cari_id': ali, 'ay': '2026-10', 'sut_fiyat': 18.5, 'sut_yemi_fiyat': 12});
    await db.insert('fiyatlar', {'urun_turu': 'süt', 'birim_fiyat': 19, 'tarih': '2026-10-01'});
    for (var g = 1; g <= 5; g++) {
      final t = '2026-10-${g.toString().padLeft(2, '0')}';
      await db.insert('sutler', {'cari_id': ali, 'tarih': t, 'sabah': 20.5, 'aksam': 18, 'toplam': 38.5});
      await db.insert('sutler', {'cari_id': ayse, 'tarih': t, 'sabah': 11, 'aksam': 9.25, 'toplam': 20.25});
    }
    await db.insert('yemler', {'cari_id': ali, 'tarih': '2026-10-03', 'sut_yemi': 50, 'toplam': 50});
    await db.insert('cari_odemeler', {
      'cari_id': ali, 'tarih': '2026-10-15', 'islem_turu': 'odeme',
      'miktar': 1, 'birim_fiyat': 1000, 'toplam_tutar': 1000, 'odenen_tutar': 1000,
    });
    await db.insert('cari_odemeler', {
      'cari_id': ayse, 'tarih': '2026-10-20', 'islem_turu': 'tahsilat',
      'miktar': 1, 'birim_fiyat': 250, 'toplam_tutar': 250,
    });
    // Ekim dönemi kapatılmış (kilitli) olsun.
    final donem = await db.insert('donemler', {'ay': '2026-10', 'durum': 'kapali', 'kapanis_tarihi': '2026-11-01'});
    await db.insert('donem_hakedisleri', {'donem_id': donem, 'cari_id': ali, 'sut_kg': 192.5, 'donem_sonu': 2561.25});
    await db.insert('terazi_cihazlari', {'ad': 'Terazi', 'adres': 'AA:BB', 'tip': 'ble'}).catchError((_) => 0);
    return db;
  }

  Future<int> say(Database db, String t) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $t')).first['n'] as int;

  group('Veritabanını temizle', () {
    test('yalnız hareketler: süt, yem, ödeme, dönem gider; cariler ve fiyatlar kalır (kapalı dönem engellemez)', () async {
      final db = await ornekVeri();
      final s = await VeriYonetimiRepository(db).temizle(TemizlikTuru.hareketler);
      expect(s['sutler'], 10);
      expect(s['cari_odemeler'], 2);
      for (final t in ['sutler', 'yemler', 'cari_odemeler', 'donemler', 'donem_hakedisleri']) {
        expect(await say(db, t), 0, reason: t);
      }
      expect(await say(db, 'cariler'), 2);
      expect(await say(db, 'cari_fiyatlar'), 1);
      expect(await say(db, 'fiyatlar'), 1);
    });

    test('her şey: tüm veriler gider, ayarlar kalır, numaralar 1\'den başlar', () async {
      final db = await ornekVeri();
      final teraziOnce = await say(db, 'terazi_cihazlari');
      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hepsi);
      for (final t in isTablolari) {
        expect(await say(db, t), 0, reason: t);
      }
      expect(await say(db, 'terazi_cihazlari'), teraziOnce, reason: 'cihaz ayarları kalır');
      expect(await db.insert('cariler', {'ad': 'Yeni', 'soyad': ''}), 1);
    });
  });

  group('Elle yedek → temizle → geri yükle', () {
    test('DB ile Yedekle (.db) → her şeyi temizle → İçeri Al (.db): birebir geri gelir', () async {
      final db = await ornekVeri();
      final once = await goruntu(db);
      final yedekKlasoru = Directory(p.join(klasor.path, 'Download', OtomatikYedek.disKlasorAdi));
      final yedek = await OtomatikYedek.veritabaniYedekAl(
        kopyala: app.tutarliKopyala,
        dogrula: (y) => VeriYonetimiRepository.dbDosyasiniDogrula(y, factory: databaseFactoryFfi),
        hedefKlasor: yedekKlasoru,
      );

      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hepsi);
      expect(await say(db, 'cariler'), 0);

      // Ekrandaki _importDbFile ile aynı adımlar.
      await VeriYonetimiRepository.dbDosyasiniDogrula(yedek.path, factory: databaseFactoryFfi);
      await app.dosyayiDegistir((yol) async {
        final gecici = File('$yol.geri_yukleme');
        await yedek.copy(gecici.path);
        await AppDatabase.dosyayiYerineKoy(gecici, yol);
      });
      final yeni = await app.database;
      expect(await goruntu(yeni), once);
      expect((await yeni.query('donemler')).single['durum'], 'kapali', reason: 'dönem kilidi de geri gelir');
    });

    test('JSON yedek → her şeyi temizle → "Yedekteki hale getir": birebir geri gelir', () async {
      final db = await ornekVeri();
      final once = await goruntu(db);
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hepsi);
      await VeriYonetimiRepository(db).yedekYukle(json, tamamenDegistir: true);
      expect(await goruntu(db), once);
    });

    test('JSON yedek → yalnız hareketleri temizle → "Birleştir": birebir geri gelir', () async {
      final db = await ornekVeri();
      final once = await goruntu(db);
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hareketler);
      await VeriYonetimiRepository(db).yedekYukle(json);
      expect(await goruntu(db), once);
    });

    test('yedekten sonra girilen kayıt: "Yedekteki hale getir" siler, "Birleştir" korur', () async {
      final db = await ornekVeri();
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      await db.insert('sutler', {'cari_id': 1, 'tarih': '2026-11-02', 'sabah': 7, 'aksam': 0, 'toplam': 7});
      await VeriYonetimiRepository(db).yedekYukle(json);
      expect(await say(db, 'sutler'), 11);
      await VeriYonetimiRepository(db).yedekYukle(json, tamamenDegistir: true);
      expect(await say(db, 'sutler'), 10);
    });

    test('BAŞKA veritabanının yedeği birleştirilmez: kayıtlar yanlış cariye geçmez, hiçbir şey değişmez', () async {
      final db = await ornekVeri();
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      // Yeni kurulum: farklı cariler aynı numaralarla.
      await VeriYonetimiRepository(db).temizle(TemizlikTuru.hepsi);
      await db.insert('cariler', {'ad': 'Mehmet', 'soyad': 'Kaya'});
      await db.insert('sutler', {'cari_id': 1, 'tarih': '2026-11-01', 'sabah': 30, 'aksam': 0, 'toplam': 30});
      final once = await goruntu(db);
      await expectLater(VeriYonetimiRepository(db).yedekYukle(json), throwsA(isA<YedekHatasi>()));
      expect(await goruntu(db), once);
      // "Yedekteki hale getir" ise çalışır.
      await VeriYonetimiRepository(db).yedekYukle(json, tamamenDegistir: true);
      expect((await db.query('cariler', where: 'id = 1')).single['ad'], 'Ali');
    });

    test('aynı veritabanında sonradan adı değişen cari birleştirmeyi engellemez', () async {
      final db = await ornekVeri();
      final json = YedekServisi.coz(await YedekServisi.disaAktarJson(db));
      await db.update('cariler', {'ad': 'Ali Rıza'}, where: 'id = 1');
      await VeriYonetimiRepository(db).yedekYukle(json);
      expect((await db.query('cariler', where: 'id = 1')).single['ad'], 'Ali');
    });
  });
}
