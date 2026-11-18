import 'package:sqflite/sqflite.dart';

import '../yedek/yedek_servisi.dart';
import 'denetim_kaydi.dart';
import 'donem_kilidi.dart';

/// Yedekleme ekranındaki kayıt sayıları.
typedef KayitSayilari = ({int cari, int sut, int yem, int odeme});

/// Veritabanı temizliğinin kapsamı (Fırın ERP ile aynı yapı, 2026-11-19).
enum TemizlikTuru {
  /// Süt, yem, ödeme/tahsilat, dönem kapanışları silinir; cariler ve fiyatlar KALIR.
  hareketler,

  /// SIFIRDAN BAŞLA: hareketler + cariler, cari fiyatları, piyasa fiyat notları.
  /// Ayarlar (şifre, aktivasyon, yazıcı, terazi, eşitleme) ve işlem geçmişi KALIR.
  hepsi,
}

/// Toplu veri işlemleri: kayıt sayıları, yedek alma/yükleme, süt ve yem
/// kayıtlarını temizleme, dışarıdan seçilen .db dosyasını doğrulama.
/// Ekranlar bu işler için doğrudan SQL yazmaz.
class VeriYonetimiRepository {
  final Database db;
  const VeriYonetimiRepository(this.db);

  Future<KayitSayilari> kayitSayilari() async {
    final r = await db.rawQuery('''
      SELECT (SELECT COUNT(*) FROM cariler)       AS cari,
             (SELECT COUNT(*) FROM sutler)        AS sut,
             (SELECT COUNT(*) FROM yemler)        AS yem,
             (SELECT COUNT(*) FROM cari_odemeler) AS odeme
    ''');
    int s(String k) => (r.first[k] as int?) ?? 0;
    return (cari: s('cari'), sut: s('sut'), yem: s('yem'), odeme: s('odeme'));
  }

  Future<String> yedekJson() => YedekServisi.disaAktarJson(db);

  Future<YedekOzeti> yedekYukle(Map<String, dynamic> veri, {bool tamamenDegistir = false}) =>
      YedekServisi.iceAktar(db, veri, tamamenDegistir: tamamenDegistir);

  /// Tüm süt ve yem kayıtlarını siler (cariler, ödemeler, fiyatlar kalır).
  /// Kapalı dönemde kaydı varsa HİÇBİR ŞEY silinmez ([DonemKapaliHatasi]).
  /// Silinen satır sayıları denetim kaydına yazılır.
  /// VERİTABANI TEMİZLİĞİ (tek transaction: hata olursa hiçbir şey silinmez).
  /// Kapatılmış dönemler de silinir (önce açılır, kilit tetikleyicileri
  /// engellemesin). ÇAĞIRAN önce güvenlik yedeği almalıdır.
  /// Dönüş: tablo → silinen satır sayısı.
  Future<Map<String, int>> temizle(TemizlikTuru tur) => db.transaction((txn) async {
        final silinen = <String, int>{};
        await txn.update('donemler', {'durum': 'acik'});
        final tablolar = [
          'donem_hakedisleri',
          'donemler',
          'cari_odemeler',
          'yemler',
          'sutler',
          if (tur == TemizlikTuru.hepsi) ...['cari_fiyatlar', 'fiyatlar', 'cariler'],
        ];
        for (final t in tablolar) {
          silinen[t] = await txn.delete(t);
        }
        // Numaralar sıfırdan başlasın.
        final sira = await txn.rawQuery("SELECT 1 FROM sqlite_master WHERE name = 'sqlite_sequence'");
        if (sira.isNotEmpty) {
          await txn.execute(
              "DELETE FROM sqlite_sequence WHERE name IN (${tablolar.map((t) => "'$t'").join(',')})");
        }
        final fk = await txn.rawQuery('PRAGMA foreign_key_check');
        if (fk.isNotEmpty) {
          throw StateError('Temizlik tamamlanamadı (kopuk ilişki: ${fk.first['table']}). Hiçbir kayıt silinmedi.');
        }
        await denetimKaydet(txn,
            tablo: 'sutler',
            kayitId: 0,
            islem: 'sil',
            oncekiDeger: {'toplu_temizlik': tur.name, ...silinen});
        return silinen;
      });

  /// [odemelerDahil]: carilerin ödeme / tahsilat hareketleri (cari_odemeler) de
  /// silinir (2026-11-19: yalnız süt/yem silinince ödemeler kalıp bakiyeler
  /// anlamsızlaşıyordu). Cariler ve fiyatlar HER ZAMAN kalır.
  Future<({int sut, int yem, int odeme})> sutVeYemSil({bool odemelerDahil = false}) => donemKilidiyle(
        () => db.transaction((txn) async {
          final sut = await txn.delete('sutler');
          final yem = await txn.delete('yemler');
          final odeme = odemelerDahil ? await txn.delete('cari_odemeler') : 0;
          await denetimKaydet(txn,
              tablo: 'sutler',
              kayitId: 0,
              islem: 'sil',
              oncekiDeger: {'toplu_temizlik': true, 'sut_satir': sut, 'yem_satir': yem, 'odeme_satir': odeme});
          return (sut: sut, yem: yem, odeme: odeme);
        }),
      );

  /// Dışarıdan seçilen bir .db dosyasının bu uygulamanın sağlam bir
  /// veritabanı olup olmadığını, CANLI veritabanının üzerine yazmadan
  /// önce, salt okunur açarak denetler. Değilse [YedekHatasi] fırlatır.
  static Future<void> dbDosyasiniDogrula(String yol, {DatabaseFactory? factory}) async {
    Database? aday;
    try {
      aday = await (factory ?? databaseFactory).openDatabase(
        yol,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final tablolar = (await aday.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
          .map((r) => r['name'] as String)
          .toSet();
      final eksik = ['cariler', 'sutler', 'yemler'].where((t) => !tablolar.contains(t));
      if (eksik.isNotEmpty) {
        throw YedekHatasi('Seçilen dosya bir Süt-Yem veritabanı değil (eksik tablo: ${eksik.join(', ')}).');
      }
      final butunluk = await aday.rawQuery('PRAGMA quick_check');
      if (butunluk.isEmpty || butunluk.first.values.first != 'ok') {
        throw const YedekHatasi('Seçilen veritabanı dosyası bozuk.');
      }
    } on DatabaseException {
      throw const YedekHatasi('Seçilen dosya okunamadı; geçerli bir veritabanı değil.');
    } finally {
      await aday?.close();
    }
  }
}
