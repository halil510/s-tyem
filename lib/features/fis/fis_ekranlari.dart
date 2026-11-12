import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/bt_cihaz_suzgeci.dart';
import '../../utils/permission_helper.dart';

import '../../services/whatsapp_service.dart';
import 'fis_servisi.dart';
import 'uretici_fisi.dart';

/// Fişi önizler; yazıcıya basar veya WhatsApp'tan gönderir.
/// [otomatikYazdir]: süt az önce kaydedildi → ayarda "otomatik yazdır" açık ve yazıcı seçiliyse
/// fiş pencere açılır açılmaz basılır (yeniden bakışta basılmaz, iki kez çıkmasın).
Future<void> fisGoster(BuildContext context, {required UreticiFisi fis, String? telefon, bool otomatikYazdir = false}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FisOnizleme(fis: fis, telefon: telefon, otomatikYazdir: otomatikYazdir),
    );

class _FisOnizleme extends StatefulWidget {
  final UreticiFisi fis;
  final String? telefon;
  final bool otomatikYazdir;
  const _FisOnizleme({required this.fis, this.telefon, this.otomatikYazdir = false});

  @override
  State<_FisOnizleme> createState() => _FisOnizlemeState();
}

class _FisOnizlemeState extends State<_FisOnizleme> {
  FisAyarlari? _ayar;
  bool _yazdiriliyor = false;
  String? _durum;
  bool _hata = false;

  @override
  void initState() {
    super.initState();
    _ayarYukle();
  }

  bool _otomatikDenendi = false;

  Future<void> _ayarYukle() async {
    final a = await FisAyarlari.yukle();
    if (!mounted) return;
    setState(() => _ayar = a);
    if (widget.otomatikYazdir && !_otomatikDenendi && a.otomatikYazdir && a.yaziciSecili) {
      _otomatikDenendi = true;
      await _yazdir();
    }
  }

  void _durumYaz(String m, {bool hata = false}) => setState(() {
        _durum = m;
        _hata = hata;
      });

  Future<void> _yazdir() async {
    final ayar = _ayar!;
    if (!ayar.yaziciSecili) {
      await _ayarlariAc();
      return;
    }
    setState(() => _yazdiriliyor = true);
    try {
      await TermalYaziciServisi.yazdir(ayar, widget.fis.satirlar(ayar.genislik));
      _durumYaz(ayar.kopya > 1 ? 'Fiş yazdırıldı ✓ (${ayar.kopya} kopya)' : 'Fiş yazdırıldı ✓');
    } catch (e) {
      _durumYaz('$e', hata: true);
    } finally {
      if (mounted) setState(() => _yazdiriliyor = false);
    }
  }

  Future<void> _whatsapp() async {
    final ok = await WhatsAppService.sendToWhatsApp(
      widget.telefon ?? '',
      widget.fis.whatsappMetni(genislik: 32),
    );
    if (!ok) _durumYaz('WhatsApp açılamadı. Telefon numarasını kontrol edin.', hata: true);
  }

  Future<void> _ayarlariAc() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FisYaziciAyarlariEkrani()));
    await _ayarYukle();
  }

  @override
  Widget build(BuildContext context) {
    final ayar = _ayar;
    final telefonVar = WhatsAppService.telefonNormalize(widget.telefon ?? '').isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: ayar == null
            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Expanded(
                    child: Text('Üretici Fişi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    tooltip: 'Yazıcı ayarları',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: _ayarlariAc,
                  ),
                ]),
                const SizedBox(height: 8),
                Flexible(child: FisOnizlemeKagidi(satirlar: widget.fis.satirlar(ayar.genislik), genislik: ayar.genislik)),
                if (_durum != null) ...[
                  const SizedBox(height: 10),
                  Text(_durum!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _hata ? Colors.red[700] : Colors.green[700])),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _yazdiriliyor ? null : _yazdir,
                      icon: _yazdiriliyor
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_rounded),
                      label: Text(ayar.yaziciSecili ? 'Yazdır' : 'Yazıcı Seç'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: telefonVar ? _whatsapp : null,
                      icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                      label: Text(telefonVar ? 'WhatsApp' : 'Telefon yok'),
                    ),
                  ),
                ]),
                if (ayar.yaziciSecili)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Yazıcı: ${ayar.yaziciEtiketi}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ]),
      ),
    );
  }
}

/// Fişin kâğıttaki görünümü (yazıcıyla aynı satırlar).
class FisOnizlemeKagidi extends StatelessWidget {
  final List<FisSatiri> satirlar;
  final int genislik;
  const FisOnizlemeKagidi({super.key, required this.satirlar, required this.genislik});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: genislik * 8.4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in satirlar)
                  Text(
                    s.metin,
                    textAlign: s.ortala ? TextAlign.center : TextAlign.left,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: s.buyuk ? 20 : 14,
                      height: 1.3,
                      fontWeight: s.kalin ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black87,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fiş yazıcısı seçimi ve fiş ayarları.
class FisYaziciAyarlariEkrani extends StatefulWidget {
  const FisYaziciAyarlariEkrani({super.key});

  @override
  State<FisYaziciAyarlariEkrani> createState() => _FisYaziciAyarlariEkraniState();
}

class _FisYaziciAyarlariEkraniState extends State<FisYaziciAyarlariEkrani> {
  static const _btKanal = MethodChannel('classic_bluetooth');

  FisAyarlari? _ayar;
  final _isletmeCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _adresCtrl = TextEditingController();
  final _altYaziCtrl = TextEditingController();
  List<UsbYazici> _usbler = [];
  bool _usbYukleniyor = false;
  String? _usbHata;
  UsbYazici? _taslakUsb;
  List<BtCihaz> _cihazlar = [];
  bool _cihazlarYukleniyor = false;
  bool _araniyor = false;
  bool _isimsizGoster = false;
  String? _cihazHata;
  bool _deneniyor = false;

  /// Kayıtlı yazıcı varken seçim alanı KİLİTLİ; "Değiştir" ile açılır.
  bool _degistiriliyor = false;
  YaziciBaglantisi _taslakBaglanti = YaziciBaglantisi.bluetooth;
  BtCihaz? _taslakBt;
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '${FisAyarlari.varsayilanPort}');
  String? _ipHata;
  bool _test = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _isletmeCtrl.dispose();
    _telCtrl.dispose();
    _adresCtrl.dispose();
    _altYaziCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final a = await FisAyarlari.yukle();
    if (!mounted) return;
    setState(() {
      _ayar = a;
      _degistiriliyor = !a.yaziciSecili; // kayıtlı yazıcı yoksa seçim açık
      _taslakBaglanti = a.baglanti;
    });
    _isletmeCtrl.text = a.isletmeAdi;
    _telCtrl.text = a.isletmeTelefon;
    _adresCtrl.text = a.isletmeAdres;
    _altYaziCtrl.text = a.altYazi;
    _ipCtrl.text = a.wifiAdres ?? '';
    _portCtrl.text = '${a.wifiPort}';
    if (_degistiriliyor && _taslakBaglanti == YaziciBaglantisi.bluetooth) await _cihazlariGetir();
    if (_degistiriliyor && _taslakBaglanti == YaziciBaglantisi.usb) await _usbleriGetir();
  }

  Future<void> _usbleriGetir() async {
    setState(() {
      _usbYukleniyor = true;
      _usbHata = null;
    });
    try {
      _usbler = await TermalYaziciServisi.usbCihazlari();
      if (_usbler.length == 1) _taslakUsb = _usbler.first;
    } catch (e) {
      _usbHata = '$e';
    } finally {
      if (mounted) setState(() => _usbYukleniyor = false);
    }
  }

  /// Metin alanlarındaki fiş bilgilerini ayara işler.
  FisAyarlari _metinlerle(FisAyarlari a) => a.kopyala(
        isletmeAdi: _isletmeCtrl.text,
        isletmeTelefon: _telCtrl.text,
        isletmeAdres: _adresCtrl.text,
        altYazi: _altYaziCtrl.text,
      );

  Future<void> _degistirBaslat() async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yazıcı değiştirilsin mi?'),
        content: Text('Kayıtlı yazıcı: ${_ayar!.yaziciEtiketi}\n\n'
            'Yeni yazıcıyı kaydedene kadar fişler bu yazıcıdan basılmaya devam eder.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Değiştir')),
        ],
      ),
    );
    if (onay != true || !mounted) return;
    setState(() {
      _degistiriliyor = true;
      _taslakBt = null;
      _taslakUsb = null;
    });
    if (_taslakBaglanti == YaziciBaglantisi.bluetooth) await _cihazlariGetir();
    if (_taslakBaglanti == YaziciBaglantisi.usb) await _usbleriGetir();
  }

  int? get _port {
    final p = int.tryParse(_portCtrl.text.trim());
    return p != null && p > 0 && p <= 65535 ? p : null;
  }

  /// Wi-Fi: önce bağlantı denenir; ulaşılamayan yazıcı KAYDEDİLMEZ.
  /// Bluetooth: listeden seçilen eşleşmiş yazıcı kaydedilir.
  Future<void> _yaziciKaydet() async {
    final a = _ayar!;
    if (_taslakBaglanti == YaziciBaglantisi.wifi) {
      final ip = _ipCtrl.text.trim();
      final port = _port;
      if (!FisAyarlari.gecerliAgAdresi(ip) || port == null) {
        setState(() => _ipHata = 'Geçerli bir IP adresi ve port girin (ör. 192.168.1.50 : 9100)');
        return;
      }
      setState(() {
        _ipHata = null;
        _test = true;
      });
      try {
        await TermalYaziciServisi.wifiTest(ip, port);
      } catch (e) {
        if (mounted) setState(() => _ipHata = '$e');
        return;
      } finally {
        if (mounted) setState(() => _test = false);
      }
      await _guncelle(a.kopyala(baglanti: YaziciBaglantisi.wifi, wifiAdres: ip, wifiPort: port));
    } else if (_taslakBaglanti == YaziciBaglantisi.usb) {
      final u = _taslakUsb;
      if (u == null) {
        _mesaj('Listeden USB yazıcıyı seçin (OTG kablosuyla takılı ve açık olmalı).', hata: true);
        return;
      }
      await _guncelle(a.kopyala(baglanti: YaziciBaglantisi.usb, usbVid: u.vid, usbPid: u.pid, usbAd: u.ad));
    } else {
      final bt = _taslakBt;
      if (bt == null) {
        _mesaj('Listeden bir yazıcı seçin.', hata: true);
        return;
      }
      await _guncelle(a.kopyala(baglanti: YaziciBaglantisi.bluetooth, yaziciAdres: bt.adres, yaziciAdi: bt.isimsiz ? bt.adres : bt.ad.trim()));
    }
    if (!mounted) return;
    setState(() => _degistiriliyor = false);
    _mesaj('Yazıcı kaydedildi: ${_ayar!.yaziciEtiketi}. Siz değiştirmedikçe bu yazıcı kullanılır.');
  }

  /// [ara]: false → yalnız eşleşmiş cihazlar (anında); true → yakındaki klasik Bluetooth
  /// cihazları 10 sn aranır (eşleşmemiş yazıcı da bulunur).
  Future<void> _cihazlariGetir({bool ara = false}) async {
    setState(() {
      _cihazlarYukleniyor = true;
      _araniyor = ara;
      _cihazHata = null;
    });
    try {
      if (Platform.isAndroid) {
        if (!await PermissionHelper.bluetoothIzinleri()) {
          throw const YaziciHatasi('Bluetooth (Yakındaki cihazlar) izni verilmedi.');
        }
      }
      final liste = ara
          ? await _btKanal.invokeMethod<List<dynamic>>('discover', {'seconds': 10}) ?? []
          : await _btKanal.invokeMethod<List<dynamic>>('getPairedDevices') ?? [];
      final yeni = [
        for (final d in liste.cast<Map<dynamic, dynamic>>())
          BtCihaz(
            ad: '${d['name'] ?? ''}',
            adres: '${d['address']}',
            rssi: d['rssi'] as int?,
            eslesmis: !ara || d['bonded'] == true,
          ),
      ];
      // Arama sonucu öncekilerle birleşir (eşleşmiş liste kaybolmasın).
      _cihazlar = ara ? [..._cihazlar, ...yeni] : yeni;
      if (ara && yeni.where((c) => !c.eslesmis).isEmpty) {
        _mesaj('Yeni cihaz bulunamadı. Yazıcı açık mı, başka telefona bağlı değil mi? Gerekirse yazıcıyı kapatıp açın.', hata: true);
      }
    } on PlatformException catch (e) {
      _cihazHata = switch (e.code) {
        'NO_BLUETOOTH' => 'Bu cihazda Bluetooth yok.',
        'BT_KAPALI' => 'Bluetooth kapalı. Telefonun Bluetooth\'unu açın.',
        'IZIN' => 'Bluetooth arama izni verilmedi.',
        _ => 'Cihazlar okunamadı: ${e.message}',
      };
    } on MissingPluginException {
      _cihazHata = 'Bluetooth bu cihazda kullanılamıyor.';
    } catch (e) {
      _cihazHata = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _cihazlarYukleniyor = false;
          _araniyor = false;
        });
      }
    }
  }

  Future<void> _guncelle(FisAyarlari yeni) async {
    setState(() => _ayar = yeni);
    await yeni.kaydet();
  }

  Future<void> _deneme() async {
    final ayar = _metinlerle(_ayar!);
    setState(() => _deneniyor = true);
    try {
      await TermalYaziciServisi.yazdir(ayar, _denemeFisi(ayar).satirlar(ayar.genislik));
      _mesaj('Deneme fişi gönderildi. Türkçe harfler bozuksa "Türkçe karakter" ayarını kapatın.');
    } catch (e) {
      _mesaj('$e', hata: true);
    } finally {
      if (mounted) setState(() => _deneniyor = false);
    }
  }

  Widget _kayitliYaziciKarti(FisAyarlari a) => Card(
        color: Colors.green[50],
        child: ListTile(
          key: const ValueKey('kayitliYazici'),
          leading: Icon(
              switch (a.baglanti) {
                YaziciBaglantisi.wifi => Icons.wifi_rounded,
                YaziciBaglantisi.usb => Icons.usb_rounded,
                YaziciBaglantisi.bluetooth => Icons.bluetooth_rounded,
              },
              color: Colors.green[800]),
          title: Text(a.yaziciEtiketi, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Kayıtlı ✓ — siz değiştirmedikçe fişler bu yazıcıdan basılır.\n'
              'Bluetooth, USB ya da başka bir Wi-Fi yazıcıya geçmek için "Değiştir"e dokunun.'),
          isThreeLine: true,
          trailing: TextButton(onPressed: _degistirBaslat, child: const Text('Değiştir')),
        ),
      );

  Widget _usbSecimi() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Yazıcıyı USB OTG kablosuyla telefona/tablete takın ve açın, sonra listeden seçin. '
          'İlk yazdırmada Android "izin ver" sorar. (CDC, FTDI, CH340, CP210x yazıcılar desteklenir.)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (_usbYukleniyor)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_usbHata != null)
          ListTile(leading: const Icon(Icons.error_outline, color: Colors.red), title: Text(_usbHata!))
        else if (_usbler.isEmpty)
          const ListTile(leading: Icon(Icons.usb_off_rounded), title: Text('Takılı USB cihaz bulunamadı'))
        else
          for (final u in _usbler)
            RadioListTile<String>(
              value: '${u.vid}:${u.pid}',
              groupValue: _taslakUsb == null ? null : '${_taslakUsb!.vid}:${_taslakUsb!.pid}',
              title: Text(u.ad),
              subtitle: Text('VID ${u.vid.toRadixString(16).toUpperCase()} · PID ${u.pid.toRadixString(16).toUpperCase()}'),
              secondary: const Icon(Icons.print_outlined),
              onChanged: (_) => setState(() => _taslakUsb = u),
            ),
        TextButton.icon(
          onPressed: _usbYukleniyor ? null : _usbleriGetir,
          icon: const Icon(Icons.refresh),
          label: const Text('Listeyi yenile'),
        ),
      ]);

  Widget _yaziciSecimi() {
    final wifi = _taslakBaglanti == YaziciBaglantisi.wifi;
    final usb = _taslakBaglanti == YaziciBaglantisi.usb;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<YaziciBaglantisi>(
            key: const ValueKey('baglantiSecimi'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: YaziciBaglantisi.wifi, icon: Icon(Icons.wifi_rounded), label: Text('Wi-Fi / Ağ')),
              ButtonSegment(value: YaziciBaglantisi.bluetooth, icon: Icon(Icons.bluetooth_rounded), label: Text('Bluetooth')),
              ButtonSegment(value: YaziciBaglantisi.usb, icon: Icon(Icons.usb_rounded), label: Text('USB')),
            ],
            selected: {_taslakBaglanti},
            onSelectionChanged: (s) {
              setState(() => _taslakBaglanti = s.first);
              if (s.first == YaziciBaglantisi.bluetooth && _cihazlar.isEmpty) _cihazlariGetir();
              if (s.first == YaziciBaglantisi.usb) _usbleriGetir();
            },
          ),
          const SizedBox(height: 12),
          if (usb)
            _usbSecimi()
          else if (wifi) ...[
            const Text(
              'Yazıcının IP adresini yazıcının ayar fişinden (genelde düğmeye basılı tutarak açılınca basılır) '
              'ya da modem ekranından öğrenin. Telefon ve yazıcı aynı Wi-Fi ağında olmalı. '
              'Yazıcıya modemden sabit IP verirseniz adres hiç değişmez.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('yaziciIp'),
                  controller: _ipCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'IP adresi', hintText: '192.168.1.50', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('yaziciPort'),
                  controller: _portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ]),
            if (_ipHata != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_ipHata!, style: TextStyle(color: Colors.red[700], fontSize: 12)),
              ),
          ] else ...[
            const Text(
              'Yazıcı listede yoksa açık olduğundan emin olun ve "Yakındaki yazıcıları ara"ya dokunun. '
              'Eşleşmemiş yazıcıda ilk fişte Android eşleştirme sorar (şifre genelde 0000 ya da 1234). '
              'Fiş yazdırmak teraziyi koparmaz.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('btAra'),
              onPressed: _cihazlarYukleniyor ? null : () => _cihazlariGetir(ara: true),
              icon: _araniyor
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_searching_rounded),
              label: Text(_araniyor ? 'Aranıyor… (10 sn)' : 'Yakındaki yazıcıları ara'),
            ),
            if (_cihazlarYukleniyor && !_araniyor)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_cihazHata != null)
              ListTile(leading: const Icon(Icons.error_outline, color: Colors.red), title: Text(_cihazHata!))
            else ...[
              () {
                final liste = BtCihazSuzgeci.sirala(_cihazlar, BtAranan.yazici, isimsizleriGoster: _isimsizGoster);
                if (liste.isEmpty) {
                  return const ListTile(
                      leading: Icon(Icons.bluetooth_disabled), title: Text('Cihaz yok — "Yakındaki yazıcıları ara"ya dokunun'));
                }
                return Column(children: [
                  for (final c in liste)
                    RadioListTile<String>(
                      value: c.adres,
                      groupValue: _taslakBt?.adres,
                      title: Text(c.gorunenAd, overflow: TextOverflow.ellipsis),
                      subtitle: Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (BtCihazSuzgeci.benziyor(c.ad, BtAranan.yazici)) const _Etiket('yazıcı olabilir', Colors.green),
                        Text('${c.adres} · ${c.eslesmis ? 'eşleşmiş' : 'eşleşmemiş'}'
                            '${c.rssi != null ? ' · sinyal ${c.rssi! > -60 ? 'güçlü' : c.rssi! > -80 ? 'orta' : 'zayıf'}' : ''}'),
                      ]),
                      secondary: const Icon(Icons.print_outlined),
                      onChanged: (_) => setState(() => _taslakBt = c),
                    ),
                ]);
              }(),
              if (BtCihazSuzgeci.isimsizSayisi(_cihazlar) > 0)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _isimsizGoster,
                  title: Text('İsimsiz cihazları da göster (${BtCihazSuzgeci.isimsizSayisi(_cihazlar)})'),
                  onChanged: (v) => setState(() => _isimsizGoster = v),
                ),
            ],
            TextButton.icon(
              onPressed: _cihazlarYukleniyor ? null : () => _cihazlariGetir(),
              icon: const Icon(Icons.refresh),
              label: const Text('Eşleşmiş listeyi yenile'),
            ),
          ],
          const SizedBox(height: 8),
          // Dar ekranda düğmeler sığmazsa alt alta geçer (taşmaz).
          OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, overflowAlignment: OverflowBarAlignment.end, children: [
            if (_ayar!.yaziciSecili)
              TextButton(
                onPressed: () => setState(() {
                  _degistiriliyor = false;
                  _ipHata = null;
                }),
                child: const Text('Vazgeç'),
              ),
            FilledButton.icon(
              key: const ValueKey('yaziciKaydet'),
              onPressed: _test ? null : _yaziciKaydet,
              icon: _test
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(wifi ? 'Test Et ve Kaydet' : 'Kaydet'),
            ),
          ]),
        ]),
      ),
    );
  }

  /// "Kopya sayısı 2  [−] [+]" gibi küçük sayı ayarı.
  Widget _sayiAyari({
    required String key,
    required String baslik,
    required String aciklama,
    required int deger,
    required int min,
    required int max,
    required ValueChanged<int> degisti,
  }) =>
      ListTile(
        key: ValueKey(key),
        contentPadding: EdgeInsets.zero,
        title: Text(baslik),
        subtitle: Text(aciklama),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Azalt',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: deger > min ? () => degisti(deger - 1) : null,
          ),
          SizedBox(width: 24, child: Text('$deger', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          IconButton(
            tooltip: 'Artır',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: deger < max ? () => degisti(deger + 1) : null,
          ),
        ]),
      );

  UreticiFisi _denemeFisi(FisAyarlari a) => UreticiFisi(
        isletmeAdi: a.isletmeAdi,
        isletmeTelefon: a.isletmeTelefon,
        isletmeAdres: a.isletmeAdres,
        altYazi: a.altYazi,
        fisNo: 0,
        tarih: DateTime.now(),
        basimZamani: DateTime.now(),
        ureticiAdi: 'DENEME — Şükrü Çağlar Öztürk',
        sabah: 12.5,
        aksam: 10,
        buAyKg: 250,
      );

  void _mesaj(String m, {bool hata = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: hata ? Colors.red[700] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final a = _ayar;
    return Scaffold(
      appBar: AppBar(title: const Text('Fiş Yazıcısı')),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Yazıcı', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (!_degistiriliyor && a.yaziciSecili)
                _kayitliYaziciKarti(a)
              else
                _yaziciSecimi(),
              const SizedBox(height: 16),
              Text('Kâğıt genişliği', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 32, label: Text('58 mm')),
                  ButtonSegment(value: 40, label: Text('80 mm')),
                  ButtonSegment(value: 48, label: Text('80 mm geniş')),
                ],
                selected: {a.genislik},
                onSelectionChanged: (s) => _guncelle(a.kopyala(genislik: s.first)),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '58 mm: satırda 32 karakter · 80 mm: 40 karakter (büyük, okunaklı) · '
                  '80 mm geniş: 48 karakter. Satırlar taşıyorsa bir küçüğünü seçin.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              Text('Fiş bilgileri', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final (k, ctrl, etiket, ipucu, klavye) in [
                ('fisIsletme', _isletmeCtrl, 'İşletme adı', 'Örn: Kabatlı Süt Toplama', TextInputType.text),
                ('fisTelefon', _telCtrl, 'İşletme telefonu (isteğe bağlı)', '0555 555 55 55', TextInputType.phone),
                ('fisAdres', _adresCtrl, 'İşletme adresi (isteğe bağlı)', 'Köy / mahalle', TextInputType.text),
                ('fisAltYazi', _altYaziCtrl, 'Fişin altındaki yazı', 'Teşekkür ederiz', TextInputType.text),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    key: ValueKey(k),
                    controller: ctrl,
                    keyboardType: klavye,
                    decoration: InputDecoration(labelText: etiket, hintText: ipucu, border: const OutlineInputBorder(), isDense: true),
                    onChanged: (_) => setState(() => _ayar = _metinlerle(_ayar!)),
                    onEditingComplete: () => _guncelle(_metinlerle(_ayar!)),
                    onTapOutside: (_) => _guncelle(_metinlerle(_ayar!)),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Yazdırma', style: Theme.of(context).textTheme.titleMedium),
              _sayiAyari(
                key: 'fisKopya',
                baslik: 'Kopya sayısı',
                aciklama: 'Ör. 2: biri üreticiye, biri işletmeye',
                deger: a.kopya,
                min: 1,
                max: 5,
                degisti: (v) => _guncelle(a.kopyala(kopya: v)),
              ),
              _sayiAyari(
                key: 'fisBesleme',
                baslik: 'Fiş sonu kâğıt besleme',
                aciklama: 'Kesici/yırtma hizasına kaç satır ilerlesin',
                deger: a.besleme,
                min: 0,
                max: 10,
                degisti: (v) => _guncelle(a.kopyala(besleme: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a.kesici,
                title: const Text('Kâğıdı kes (kesicili yazıcı)'),
                subtitle: const Text('Kesicisi olmayan yazıcıda kapatın.'),
                onChanged: (v) => _guncelle(a.kopyala(kesici: v)),
              ),
              SwitchListTile(
                key: const ValueKey('fisOtomatik'),
                contentPadding: EdgeInsets.zero,
                value: a.otomatikYazdir,
                title: const Text('Süt kaydedince fişi otomatik yazdır'),
                subtitle: const Text('"Kaydet + Fiş" denince fiş beklemeden basılır (WhatsApp düğmesi yine görünür).'),
                onChanged: (v) => _guncelle(a.kopyala(otomatikYazdir: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a.turkceKodSayfasi,
                title: const Text('Türkçe karakter (ş, ğ, İ)'),
                subtitle: const Text(
                  'Kapalıyken harfler Latin karşılığıyla basılır (ş→s); her yazıcıda çalışır. '
                  'Yazıcınız Türkçe (CP857) destekliyorsa açın, deneme fişiyle kontrol edin.',
                ),
                onChanged: (v) => _guncelle(a.kopyala(turkceKodSayfasi: v)),
              ),
              const SizedBox(height: 16),
              Text('Önizleme', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FisOnizlemeKagidi(
                satirlar: _denemeFisi(_metinlerle(a)).satirlar(a.genislik),
                genislik: a.genislik,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !a.yaziciSecili || _deneniyor ? null : _deneme,
                icon: const Icon(Icons.print_rounded),
                label: const Text('Deneme Fişi Yazdır'),
              ),
            ]),
    );
  }
}

/// Küçük renkli etiket ("yazıcı olabilir", "terazi olabilir").
class _Etiket extends StatelessWidget {
  final String metin;
  final Color renk;
  const _Etiket(this.metin, this.renk);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: renk.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(metin, style: TextStyle(fontSize: 11, color: renk, fontWeight: FontWeight.w600)),
      );
}
