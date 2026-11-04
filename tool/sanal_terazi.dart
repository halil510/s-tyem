// SANAL TERAZİ — telefondaki uygulamayı gerçek terazi olmadan denemek için.
//
// Bilgisayar, Wi-Fi terazi gibi davranır ve yarım saniyede bir tartı
// satırı gönderir (ör. "ST,GS,+0025.40kg\r\n").
//
// Kullanım (proje klasöründe):
//   dart run tool/sanal_terazi.dart            (port 9100)
//   dart run tool/sanal_terazi.dart 8080       (başka port)
//
// Telefonda: Süt → cari → Süt Ekle → "Bağlan" (ya da ⋮ → Terazi) → Wi-Fi →
// ekrana yazılan IP ve port → Bağlan. Telefon ile bilgisayar AYNI Wi-Fi
// ağında olmalı. Windows Güvenlik Duvarı izin sorarsa "Özel ağ"a izin verin.
//
// Komutlar (yazıp Enter):
//   25.4   → tartıyı 25.4 kg yap        0     → dara / boş kefe
//   b      → "bölünmüş paket" modu aç/kapa (satırı iki parça gönderir —
//            Bluetooth'ta sık görülen durum; uygulama yine doğru göstermeli)
//   d      → dengesiz/oynak okuma modu aç/kapa (±0.05 kg oynar)
//   q      → çıkış
import 'dart:async';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 9100 : 9100;
  final sunucu = await ServerSocket.bind(InternetAddress.anyIPv4, port);
  final baglantilar = <Socket>[];
  var kg = 25.40;
  var bolunmus = false;
  var oynak = false;
  final rastgele = Random();

  stdout.writeln('══════════════════════════════════════════════');
  stdout.writeln(' SANAL TERAZİ çalışıyor — port $port');
  for (final arayuz in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in arayuz.addresses) {
      stdout.writeln('   Telefonda IP: ${a.address}   Port: $port   (${arayuz.name})');
    }
  }
  stdout.writeln(' Komutlar: sayı = kilo, b = bölünmüş paket, d = oynak, q = çıkış');
  stdout.writeln('══════════════════════════════════════════════');

  sunucu.listen((s) {
    baglantilar.add(s);
    stdout.writeln('>> Telefon bağlandı: ${s.remoteAddress.address}');
    s.listen((_) {}, onDone: () {
      baglantilar.remove(s);
      stdout.writeln('<< Telefon ayrıldı');
    }, onError: (_) => baglantilar.remove(s));
  });

  String satir() {
    final deger = oynak ? kg + (rastgele.nextDouble() - 0.5) * 0.1 : kg;
    final durum = oynak ? 'US' : 'ST';
    final isaret = deger < 0 ? '-' : '+';
    return '$durum,GS,$isaret${deger.abs().toStringAsFixed(2).padLeft(7, '0')}kg\r\n';
  }

  final zamanlayici = Timer.periodic(const Duration(milliseconds: 500), (_) async {
    final veri = satir();
    for (final s in List.of(baglantilar)) {
      try {
        if (bolunmus) {
          final orta = veri.length ~/ 2;
          s.write(veri.substring(0, orta));
          await s.flush();
          await Future<void>.delayed(const Duration(milliseconds: 40));
          s.write(veri.substring(orta));
        } else {
          s.write(veri);
        }
        await s.flush();
      } catch (_) {
        baglantilar.remove(s);
      }
    }
  });

  await for (final komut in stdin.transform(const SystemEncoding().decoder).expand((t) => t.split('\n'))) {
    final k = komut.trim().toLowerCase();
    if (k.isEmpty) continue;
    if (k == 'q') break;
    if (k == 'b') {
      bolunmus = !bolunmus;
      stdout.writeln('Bölünmüş paket: ${bolunmus ? 'AÇIK' : 'kapalı'}');
    } else if (k == 'd') {
      oynak = !oynak;
      stdout.writeln('Oynak okuma: ${oynak ? 'AÇIK' : 'kapalı'}');
    } else {
      final yeni = double.tryParse(k.replaceAll(',', '.'));
      if (yeni == null) {
        stdout.writeln('Anlaşılmadı: "$k" (sayı, b, d ya da q)');
      } else {
        kg = yeni;
        stdout.writeln('Tartı: ${kg.toStringAsFixed(2)} kg');
      }
    }
  }

  zamanlayici.cancel();
  for (final s in baglantilar) {
    s.destroy();
  }
  await sunucu.close();
  exit(0);
}
