import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sutyem_pro/features/fis/fis_ekranlari.dart';
import 'package:sutyem_pro/features/fis/fis_servisi.dart';
import 'package:sutyem_pro/features/fis/uretici_fisi.dart';
import 'package:sutyem_pro/utils/tarih_format.dart';

/// Fiş yazıcısı ayarları (Fırın ERP'deki gibi): USB, kopya, besleme, kesici, alt yazı,
/// işletme telefon/adres, süt kaydında otomatik yazdır.

/// Yerel ağdaki termal yazıcıyı taklit eder: 127.0.0.1'de port açar, gelen baytları toplar.
class _AgYazicisi {
  late ServerSocket sunucu;
  final gelen = <int>[];
  Future<void> baslat() async {
    sunucu = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    sunucu.listen((s) => s.listen(gelen.addAll, onDone: s.destroy));
  }
}

final _fis = UreticiFisi(
  isletmeAdi: 'Kabatlı Süt',
  isletmeTelefon: '0555 111 22 33',
  isletmeAdres: 'Merkez Mahallesi',
  altYazi: 'Ödemeler ayın 15inde',
  fisNo: 7,
  tarih: DateTime(2026, 11, 4),
  basimZamani: DateTime(2026, 11, 4, 8),
  ureticiAdi: 'Ali Kaya',
  sabah: 40,
  aksam: 35,
  buAyKg: 300,
);

int _say(List<int> b, List<int> desen) {
  var n = 0;
  for (var i = 0; i + desen.length <= b.length; i++) {
    var ok = true;
    for (var j = 0; j < desen.length; j++) {
      if (b[i + j] != desen[j]) {
        ok = false;
        break;
      }
    }
    if (ok) n++;
  }
  return n;
}

Widget _uygulama(Widget ev) => MaterialApp(
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: ev,
    );

Future<void> _bekle(WidgetTester t, bool Function() kosul, String neyi) async {
  for (var i = 0; i < 150; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    if (kosul()) return;
  }
  fail('Zaman aşımı: $neyi');
}

void main() {
  setUpAll(initializeTurkishLocale);

  test('Ayarlar kaydedilip geri okunur (USB, kopya, besleme, kesici, otomatik, işletme bilgileri)', () async {
    SharedPreferences.setMockInitialValues({});
    await const FisAyarlari(
      baglanti: YaziciBaglantisi.usb,
      usbVid: 0x0483,
      usbPid: 0x5743,
      usbAd: 'XP-58',
      isletmeTelefon: '0555',
      isletmeAdres: 'Köy',
      altYazi: 'Hayırlı işler',
      kopya: 2,
      besleme: 6,
      kesici: false,
      otomatikYazdir: true,
    ).kaydet();
    final a = await FisAyarlari.yukle();
    expect([a.baglanti, a.usbVid, a.usbPid, a.usbAd, a.yaziciSecili, a.yaziciEtiketi],
        [YaziciBaglantisi.usb, 0x0483, 0x5743, 'XP-58', true, 'XP-58 (USB)']);
    expect([a.isletmeTelefon, a.isletmeAdres, a.altYazi, a.kopya, a.besleme, a.kesici, a.otomatikYazdir],
        ['0555', 'Köy', 'Hayırlı işler', 2, 6, false, true]);
    // Eski kurulum (yeni anahtarlar yok) → güvenli varsayılanlar.
    SharedPreferences.setMockInitialValues({'fis_yazici_baglanti': 'wifi'});
    final e = await FisAyarlari.yukle();
    expect([e.kopya, e.besleme, e.kesici, e.otomatikYazdir, e.altYazi], [1, 4, true, false, 'Teşekkür ederiz']);
  });

  test('Baytlar: kopya sayısı kadar fiş, besleme satırı, kesici açık/kapalı', () {
    final s = _fis.satirlar(32);
    final tek = TermalYaziciServisi.baytlar(const FisAyarlari(), s);
    final iki = TermalYaziciServisi.baytlar(const FisAyarlari(kopya: 2), s);
    expect(iki.length, tek.length * 2);
    expect(_say(iki, [0x1D, 0x56, 0x42, 0x00]), 2, reason: 'her kopya kesilir');
    expect(_say(TermalYaziciServisi.baytlar(const FisAyarlari(kesici: false), s), [0x1D, 0x56]), 0);
    expect(_say(TermalYaziciServisi.baytlar(const FisAyarlari(besleme: 7), s), [0x1B, 0x64, 7]), 1);
    expect(_say(TermalYaziciServisi.baytlar(const FisAyarlari(besleme: 0), s), [0x1B, 0x64]), 0);
  });

  test('Fişte işletme telefonu, adresi ve alt yazı; alt yazı boşsa yazılmaz', () {
    final m = _fis.satirlar(32).map((s) => s.metin).toList();
    expect(m, containsAll(['Merkez Mahallesi', 'Tel: 0555 111 22 33', 'Ödemeler ayın 15inde']));
    final bos = UreticiFisi(
            isletmeAdi: 'X', altYazi: '', fisNo: 1, tarih: DateTime(2026), basimZamani: DateTime(2026), ureticiAdi: 'A', sabah: 1, aksam: 0, buAyKg: 1)
        .satirlar(32)
        .map((s) => s.metin);
    expect(bos.any((s) => s.contains('Teşekkür')), isFalse);
    expect(bos.any((s) => s.startsWith('Tel:')), isFalse);
  });

  Future<_AgYazicisi> yaziciliAyar(WidgetTester t, {required bool otomatik, int kopya = 1}) async {
    final y = _AgYazicisi();
    await t.runAsync(y.baslat);
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => FisAyarlari(
          baglanti: YaziciBaglantisi.wifi,
          wifiAdres: '127.0.0.1',
          wifiPort: y.sunucu.port,
          otomatikYazdir: otomatik,
          kopya: kopya,
        ).kaydet());
    addTearDown(() => y.sunucu.close());
    return y;
  }

  Future<void> fisAc(WidgetTester t, {required bool kayittan}) async {
    await t.pumpWidget(_uygulama(Builder(
      builder: (c) => Scaffold(
        body: Center(child: ElevatedButton(onPressed: () => fisGoster(c, fis: _fis, otomatikYazdir: kayittan), child: const Text('FIS'))),
      ),
    )));
    await t.tap(find.text('FIS'));
    await t.pump();
  }

  testWidgets('Otomatik yazdır açık + süt kaydından açılan fiş → beklemeden basılır (2 kopya)', (t) async {
    final y = await yaziciliAyar(t, otomatik: true, kopya: 2);
    await fisAc(t, kayittan: true);
    await _bekle(t, () => find.textContaining('Fiş yazdırıldı').evaluate().isNotEmpty, 'otomatik baskı');
    expect(find.textContaining('2 kopya'), findsOneWidget);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(_say(y.gelen, [0x1D, 0x56, 0x42, 0x00]), 2);
  });

  testWidgets('Fişe yeniden bakılınca (kayıttan değil) otomatik BASILMAZ; ayar kapalıysa da basılmaz', (t) async {
    final y = await yaziciliAyar(t, otomatik: true);
    await fisAc(t, kayittan: false);
    await _bekle(t, () => find.text('Yazdır').evaluate().isNotEmpty, 'önizleme');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    expect(y.gelen, isEmpty);

    await t.pumpWidget(const SizedBox()); // önceki fiş penceresi kapansın
    await t.pump();
    final y2 = await yaziciliAyar(t, otomatik: false);
    await fisAc(t, kayittan: true);
    await _bekle(t, () => find.text('Yazdır').evaluate().isNotEmpty, 'önizleme 2');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    expect(y2.gelen, isEmpty);
  });

  testWidgets('Wi-Fi yazıcı KAYITLIYKEN kart ne yapılacağını söyler; "Değiştir" → Bluetooth ve USB seçenekleri görünür', (t) async {
    t.view.physicalSize = const Size(360, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() => const FisAyarlari(baglanti: YaziciBaglantisi.wifi, wifiAdres: '192.168.1.50').kaydet());
    await t.pumpWidget(_uygulama(const FisYaziciAyarlariEkrani()));
    await _bekle(t, () => find.textContaining('192.168.1.50').evaluate().isNotEmpty, 'kayıtlı kart');
    expect(find.text('USB'), findsNothing, reason: 'kayıtlıyken seçim kilitli');
    expect(find.textContaining('Bluetooth, USB ya da başka bir Wi-Fi'), findsOneWidget);
    await t.tap(find.text('Değiştir'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Değiştir'));
    await _bekle(t, () => find.text('USB').evaluate().isNotEmpty, 'seçenekler');
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Wi-Fi / Ağ'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Ayar ekranı 360 px telefonda taşmaz; USB seçilince takılı cihaz yoksa söyler; kopya artırılır ve kaydedilir', (t) async {
    t.view.physicalSize = const Size(360, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(_uygulama(const FisYaziciAyarlariEkrani()));
    await _bekle(t, () => find.byKey(const ValueKey('baglantiSecimi')).evaluate().isNotEmpty, 'ekran');
    expect(t.takeException(), isNull);
    await t.tap(find.text('USB'));
    await _bekle(t, () => find.text('Takılı USB cihaz bulunamadı').evaluate().isNotEmpty, 'USB listesi');
    expect(t.takeException(), isNull);

    final kopya = find.byKey(const ValueKey('fisKopya'));
    await t.ensureVisible(kopya);
    await t.tap(find.descendant(of: kopya, matching: find.byTooltip('Artır')));
    await _bekle(t, () => find.descendant(of: kopya, matching: find.text('2')).evaluate().isNotEmpty, 'kopya 2');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect((await t.runAsync(FisAyarlari.yukle))!.kopya, 2);
    expect(t.takeException(), isNull);
  });
}
