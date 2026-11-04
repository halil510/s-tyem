import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/whatsapp_service.dart';
import 'fis_servisi.dart';
import 'uretici_fisi.dart';

/// Fişi önizler; yazıcıya basar veya WhatsApp'tan gönderir.
Future<void> fisGoster(BuildContext context, {required UreticiFisi fis, String? telefon}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FisOnizleme(fis: fis, telefon: telefon),
    );

class _FisOnizleme extends StatefulWidget {
  final UreticiFisi fis;
  final String? telefon;
  const _FisOnizleme({required this.fis, this.telefon});

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

  Future<void> _ayarYukle() async {
    final a = await FisAyarlari.yukle();
    if (mounted) setState(() => _ayar = a);
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
      _durumYaz('Fiş yazdırıldı ✓');
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
                    child: Text('Yazıcı: ${ayar.yaziciAdi}',
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
  List<({String ad, String adres})> _cihazlar = [];
  bool _cihazlarYukleniyor = false;
  String? _cihazHata;
  bool _deneniyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _isletmeCtrl.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final a = await FisAyarlari.yukle();
    if (!mounted) return;
    setState(() => _ayar = a);
    _isletmeCtrl.text = a.isletmeAdi;
    await _cihazlariGetir();
  }

  Future<void> _cihazlariGetir() async {
    setState(() {
      _cihazlarYukleniyor = true;
      _cihazHata = null;
    });
    try {
      if (Platform.isAndroid) {
        final izin = await Permission.bluetoothConnect.request();
        if (!izin.isGranted) throw const YaziciHatasi('Bluetooth izni verilmedi.');
      }
      final liste = await _btKanal.invokeMethod<List<dynamic>>('getPairedDevices') ?? [];
      _cihazlar = [
        for (final d in liste.cast<Map<dynamic, dynamic>>())
          (ad: '${d['name'] ?? 'Adsız cihaz'}', adres: '${d['address']}'),
      ];
    } on PlatformException catch (e) {
      _cihazHata = e.code == 'NO_BLUETOOTH' ? 'Bu cihazda Bluetooth yok.' : 'Cihazlar okunamadı: ${e.message}';
    } on MissingPluginException {
      _cihazHata = 'Bluetooth bu cihazda kullanılamıyor.';
    } catch (e) {
      _cihazHata = '$e';
    } finally {
      if (mounted) setState(() => _cihazlarYukleniyor = false);
    }
  }

  Future<void> _guncelle(FisAyarlari yeni) async {
    setState(() => _ayar = yeni);
    await yeni.kaydet();
  }

  Future<void> _deneme() async {
    final ayar = _ayar!.kopyala(isletmeAdi: _isletmeCtrl.text);
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

  UreticiFisi _denemeFisi(FisAyarlari a) => UreticiFisi(
        isletmeAdi: a.isletmeAdi,
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
              const SizedBox(height: 4),
              const Text(
                'Termal yazıcıyı önce telefonun Bluetooth ayarlarından eşleştirin; '
                'sonra burada seçin. Fiş yazdırmak teraziyi koparmaz.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  if (_cihazlarYukleniyor)
                    const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                  else if (_cihazHata != null)
                    ListTile(
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text(_cihazHata!),
                    )
                  else if (_cihazlar.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.bluetooth_disabled),
                      title: Text('Eşleştirilmiş cihaz yok'),
                    )
                  else
                    for (final c in _cihazlar)
                      RadioListTile<String>(
                        value: c.adres,
                        groupValue: a.yaziciAdres,
                        title: Text(c.ad),
                        subtitle: Text(c.adres),
                        secondary: const Icon(Icons.print_outlined),
                        onChanged: (_) => _guncelle(a.kopyala(yaziciAdres: c.adres, yaziciAdi: c.ad)),
                      ),
                  TextButton.icon(
                    onPressed: _cihazlarYukleniyor ? null : _cihazlariGetir,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Listeyi yenile'),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Kâğıt genişliği', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 32, label: Text('58 mm')),
                  ButtonSegment(value: 48, label: Text('80 mm')),
                ],
                selected: {a.genislik},
                onSelectionChanged: (s) => _guncelle(a.kopyala(genislik: s.first)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _isletmeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fişte görünecek işletme adı',
                  hintText: 'Örn: Kabatlı Süt Toplama',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _ayar = _ayar!.kopyala(isletmeAdi: v)),
                onEditingComplete: () => _guncelle(_ayar!),
                onTapOutside: (_) => _guncelle(_ayar!),
              ),
              const SizedBox(height: 8),
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
                satirlar: _denemeFisi(a.kopyala(isletmeAdi: _isletmeCtrl.text)).satirlar(a.genislik),
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
