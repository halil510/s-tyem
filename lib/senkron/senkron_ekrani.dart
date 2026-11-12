import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/providers/database_provider.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'bulut_kanali.dart';
import 'senkron_yoneticisi.dart';
import 'yerel_ag_kanali.dart';

const _lacivert = Color(0xFF1A237E);
const _yesil = Color(0xFF1B6B3A);
const _kirmizi = Color(0xFFC62828);
const _turuncu = Color(0xFFE65100);

const _tabloAdi = {
  'cariler': 'Cari',
  'cari_fiyatlar': 'Cari fiyatı',
  'fiyatlar': 'Piyasa fiyat notu',
  'sutler': 'Süt',
  'yemler': 'Yem',
  'cari_odemeler': 'Ödeme/tahsilat',
  'donemler': 'Dönem',
  'donem_hakedisleri': 'Hakediş',
};

String _saat(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String _zaman(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${_saat(d)}';
}

/// ─────────────────────────────────────────────────────────────
/// ÇOKLU CİHAZ VE BULUT — internetli (Supabase) + internetsiz (aynı WiFi).
/// ─────────────────────────────────────────────────────────────
class SenkronEkrani extends ConsumerStatefulWidget {
  const SenkronEkrani({super.key});
  @override
  ConsumerState<SenkronEkrani> createState() => _SenkronEkraniState();
}

class _SenkronEkraniState extends ConsumerState<SenkronEkrani> {
  final _y = SenkronYoneticisi();
  final _url = TextEditingController();
  final _anahtar = TextEditingController();
  final _isletme = TextEditingController();
  final _sifre = TextEditingController();
  final _lanAdres = TextEditingController();
  final _lanKod = TextEditingController();
  final _cihazAd = TextEditingController();
  bool _hazir = false, _mesgul = false, _sifreGizli = true, _taraniyor = false, _otomatik = true;
  BulutAyari? _bulut;
  String _lanRol = 'kapali';
  String? _anaKod;
  int _bekleyenBulut = 0, _bekleyenLan = 0, _bekletilen = 0;
  List<Map<String, Object?>> _hatalar = [];
  List<AnaCihaz> _bulunan = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _yukle());
  }

  @override
  void dispose() {
    for (final c in [_url, _anahtar, _isletme, _sifre, _lanAdres, _lanKod, _cihazAd]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final db = await ref.read(databaseProvider.future);
    await _y.baslat(db);
    _bulut = await _y.bulutAyari();
    _lanRol = (await _y.ayar(SenkAyar.lanRol)) ?? 'kapali';
    _anaKod = await _y.ayar(SenkAyar.lanKod);
    _otomatik = (await _y.ayar(SenkAyar.bulutOtomatik)) != '0';
    if (!_hazir) {
      _url.text = (await _y.ayar(SenkAyar.bulutUrl)) ?? '';
      _anahtar.text = (await _y.ayar(SenkAyar.bulutAnahtar)) ?? '';
      _isletme.text = (await _y.ayar(SenkAyar.isletme)) ?? '';
      _sifre.text = (await _y.ayar(SenkAyar.isletmeSifre)) ?? '';
      _lanAdres.text = (await _y.ayar(SenkAyar.lanAdres)) ?? '';
      _lanKod.text = (await _y.ayar(SenkAyar.lanIstemciKod)) ?? '';
      _cihazAd.text = await _y.cihazAdi();
    }
    _bekleyenBulut = await _y.bekleyen('bulut', 'bulut');
    _bekleyenLan = await _y.bekleyen('lan', 'lan');
    _bekletilen = await _y.bekletilenSayisi();
    _hatalar = await _y.hatalar();
    if (mounted) setState(() => _hazir = true);
  }

  void _mesaj(String m, {Color? renk}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: renk, duration: const Duration(seconds: 5)));

  Future<void> _islem(Future<String> Function() f) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      final m = await f();
      ref.veriDegisti();
      if (mounted) _mesaj(m, renk: _yesil);
    } catch (e) {
      if (mounted) _mesaj(e.toString(), renk: _kirmizi);
    } finally {
      if (mounted) setState(() => _mesgul = false);
      await _yukle();
    }
  }

  Future<bool> _onay(String baslik, String mesaj) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(baslik),
          content: Text(mesaj),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Evet')),
          ],
        ),
      ) ??
      false;

  // ── SQL dosyası ──
  Future<String> _sql() => rootBundle.loadString('supabase/sutyem_bulut_sema.sql');

  Future<void> _sqlPaylas() async {
    try {
      final d = await getTemporaryDirectory();
      final f = File('${d.path}${Platform.pathSeparator}sutyem_bulut_sema.sql');
      await f.writeAsString(await _sql());
      await Share.shareXFiles([XFile(f.path, mimeType: 'text/plain')], text: 'Süt-Yem bulut şeması (Supabase SQL Editor\'da çalıştırın)');
    } catch (e) {
      if (mounted) _mesaj('Paylaşılamadı: $e', renk: _kirmizi);
    }
  }

  Future<void> _sqlKopyala() async {
    await Clipboard.setData(ClipboardData(text: await _sql()));
    if (mounted) _mesaj('SQL panoya kopyalandı. Supabase → SQL Editor → yapıştır → Run.', renk: _yesil);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(title: const Text('Çoklu Cihaz ve Bulut', style: TextStyle(fontWeight: FontWeight.bold)), foregroundColor: _lacivert),
        body: !_hazir
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _yukle,
                child: ListView(padding: const EdgeInsets.all(12), children: [
                  ValueListenableBuilder<Duration?>(
                    valueListenable: _y.saatFarki,
                    builder: (_, f, __) => SaatFarki.sapmaVar(f)
                        ? Card(
                            color: const Color(0xFFFFF3E0),
                            child: ListTile(
                              leading: const Icon(Icons.schedule, color: _turuncu),
                              title: const Text('Telefonun saati yanlış', style: TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(SaatFarki.metin(f!)),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _cihazKarti(),
                  _bulutKarti(),
                  _lanKarti(),
                  if (_hatalar.isNotEmpty || _bekletilen > 0) _sorunKarti(),
                  _bilgiKarti(),
                  const SizedBox(height: 30),
                ]),
              ),
      );

  Widget _kart(List<Widget> c) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: c)),
      );

  Widget _baslik(IconData i, String t, {Color renk = _lacivert}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(i, color: renk),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _satir(String sol, String sag) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(sol, style: TextStyle(color: Colors.grey[700]))),
          Flexible(child: Text(sag, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _durum(SenkOzet o) {
    final (renk, ikon) = switch (o.durum) {
      SenkDurum.tamam => (_yesil, Icons.check_circle),
      SenkDurum.hata => (_kirmizi, Icons.error),
      SenkDurum.esitleniyor => (_lacivert, Icons.sync),
      _ => (Colors.grey, Icons.cloud_off),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: renk.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(ikon, color: renk, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('${o.mesaj}${o.zaman != null ? '  (${_saat(o.zaman!)})' : ''}', style: TextStyle(color: renk))),
      ]),
    );
  }

  Widget _yukleniyor() => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _cihazKarti() => _kart([
        _baslik(Icons.smartphone, 'Bu cihaz'),
        TextField(
          controller: _cihazAd,
          decoration: InputDecoration(
            labelText: 'Cihaz adı (ör. Toplayıcı Ali, Dükkan, Patron)',
            suffixIcon: IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                await _y.ayarYaz(SenkAyar.cihazAd, _cihazAd.text.trim());
                if (mounted) _mesaj('Cihaz adı kaydedildi');
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Cihaz kimliği: ${_y.cihaz.length > 8 ? _y.cihaz.substring(0, 8) : _y.cihaz}…', style: const TextStyle(fontSize: 12)),
      ]);

  // ═════════════════════════════ BULUT ═════════════════════════════
  Widget _bulutKarti() => _kart([
        _baslik(Icons.cloud, 'İnternetli — Bulut (Supabase)'),
        ValueListenableBuilder(valueListenable: _y.bulutDurum, builder: (_, o, __) => _durum(o)),
        if (_bulut != null) ...[
          _satir('İşletme', _bulut!.isletme),
          _satir('Bulut', _bulut!.url.replaceFirst('https://', '')),
          _satir('Gönderilmeyi bekleyen', '$_bekleyenBulut değişiklik'),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('bulutEsitle'),
            icon: _mesgul ? _yukleniyor() : const Icon(Icons.sync),
            label: const Text('Şimdi eşitle'),
            onPressed: _mesgul ? null : () => _islem(() => _y.buluttaEsitle()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Otomatik eşitle'),
            subtitle: const Text('İnternet varken dakikada bir, uygulama açılınca ve kapanırken'),
            value: _otomatik,
            onChanged: (x) async {
              await _y.ayarYaz(SenkAyar.bulutOtomatik, x ? '1' : '0');
              setState(() => _otomatik = x);
            },
          ),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(icon: const Icon(Icons.devices), label: const Text('Bağlı cihazlar'), onPressed: _cihazlariGoster),
            TextButton.icon(
              icon: const Icon(Icons.link_off, color: _kirmizi),
              label: const Text('Bu cihazı buluttan ayır', style: TextStyle(color: _kirmizi)),
              onPressed: () async {
                if (await _onay('Buluttan ayrılsın mı?',
                    'Bu cihaz artık bulutla eşitlenmez. Telefondaki ve buluttaki veri SİLİNMEZ; istediğinizde yeniden bağlanabilirsiniz.')) {
                  await _y.bulutuKapat();
                  await _yukle();
                }
              },
            ),
          ]),
        ] else
          ..._bulutFormu(),
      ]);

  List<Widget> _bulutFormu() => [
        const Text(
            '1) supabase.com\'da AYRI bir proje açın  2) Aşağıdaki SQL dosyasını SQL Editor\'da çalıştırın  '
            '3) Project Settings → API\'den URL ve anon/publishable anahtarı buraya yazın.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(icon: const Icon(Icons.share), label: const Text('SQL dosyasını paylaş'), onPressed: _sqlPaylas),
          OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('SQL\'i kopyala'), onPressed: _sqlKopyala),
        ]),
        const SizedBox(height: 10),
        TextField(
            key: const ValueKey('bulutUrl'),
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co')),
        const SizedBox(height: 8),
        TextField(
            controller: _anahtar, decoration: const InputDecoration(labelText: 'anon / publishable anahtar', hintText: 'sb_publishable_… ya da eyJ…')),
        const SizedBox(height: 8),
        TextField(
            controller: _isletme, decoration: const InputDecoration(labelText: 'İşletme kodu', hintText: 'ör. kabatli-sut (tüm cihazlarda aynı)')),
        const SizedBox(height: 8),
        TextField(
          controller: _sifre,
          obscureText: _sifreGizli,
          decoration: InputDecoration(
            labelText: 'İşletme şifresi (en az 6 karakter, tüm cihazlarda aynı)',
            suffixIcon:
                IconButton(icon: Icon(_sifreGizli ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _sifreGizli = !_sifreGizli)),
          ),
        ),
        const SizedBox(height: 4),
        const Text('İlk cihazda bu kod ve şifreyle işletme bulutta KURULUR; diğer cihazlarda aynısını yazınca bağlanır.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: _mesgul ? _yukleniyor() : const Icon(Icons.cloud_upload),
          label: const Text('Bağlan ve eşitle'),
          onPressed: _mesgul
              ? null
              : () => _islem(() async {
                    final a = BulutAyari(url: _url.text, anahtar: _anahtar.text.trim(), isletme: _isletme.text.trim().toLowerCase(), sifre: _sifre.text);
                    if (!a.tamam) throw const BulutHatasi('Dört alanı da doldurun.');
                    final r = await _y.bulutBaglan(a);
                    final m = await _y.buluttaEsitle();
                    return '${r['yeni'] == true ? 'İşletme bulutta kuruldu. ' : 'Buluttaki işletmeye bağlandı. '}$m';
                  }),
        ),
      ];

  Future<void> _cihazlariGoster() async {
    try {
      final l = await _y.bulutCihazlari();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Bağlı cihazlar'),
          content: SizedBox(
            width: 400,
            child: ListView(shrinkWrap: true, children: [
              for (final d in l)
                ListTile(
                  leading: Icon(d['cihaz'] == _y.cihaz ? Icons.smartphone : Icons.devices_other),
                  title: Text('${d['ad'] ?? '-'}${d['cihaz'] == _y.cihaz ? ' (bu cihaz)' : ''}'),
                  subtitle: Text('Son eşitleme: ${_zaman((d['son_gorulme'] as String?) ?? '')}'),
                ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    } catch (e) {
      if (mounted) _mesaj(e.toString(), renk: _kirmizi);
    }
  }

  // ═════════════════════════════ YEREL AĞ ═════════════════════════════
  Widget _lanKarti() => _kart([
        _baslik(Icons.wifi, 'İnternetsiz — Aynı WiFi (yerel ağ)'),
        ValueListenableBuilder(valueListenable: _y.lanDurum, builder: (_, o, __) => _durum(o)),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'kapali', label: Text('Kapalı')),
            ButtonSegment(value: 'ana', label: Text('Ana cihaz')),
            ButtonSegment(value: 'bagli', label: Text('Bağlı')),
          ],
          selected: {_lanRol},
          onSelectionChanged: (s) async {
            final r = s.first;
            if (r == 'ana') {
              await _islem(() async => 'Ana cihaz açıldı · kod ${await _y.anaCihazOl()}');
            } else if (r == 'kapali') {
              await _y.yerelAgiKapat();
              await _yukle();
            } else {
              await _y.sunucu.durdur();
              setState(() => _lanRol = 'bagli');
            }
          },
        ),
        const SizedBox(height: 10),
        if (_lanRol == 'ana') ..._anaGorunum(),
        if (_lanRol == 'bagli') ..._bagliGorunum(),
        if (_lanRol == 'kapali')
          const Text(
              'İnternet yokken aynı WiFi\'daki telefonları eşitlemek için birini (ör. dükkandaki telefon/tablet) "Ana cihaz", '
              'diğerlerini "Bağlı" yapın.',
              style: TextStyle(fontSize: 12)),
      ]);

  List<Widget> _anaGorunum() => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _lacivert.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            const Text('Diğer cihazlarda bu bilgileri girin:'),
            const SizedBox(height: 6),
            SelectableText('Adres: ${_y.sunucu.ip ?? '(WiFi yok)'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            SelectableText('Kod: ${_anaKod ?? '-'}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4, color: _lacivert)),
          ]),
        ),
        const SizedBox(height: 6),
        const Text(
            'Uygulama bu cihazda AÇIK kaldıkça diğer cihazlar eşitlenebilir. Bu cihaz buluta da bağlıysa, '
            'yerel ağdan gelen değişiklikler internet gelince buluta da gider.',
            style: TextStyle(fontSize: 12)),
        TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Kodu değiştir'),
          onPressed: () async {
            await _y.ayarYaz(SenkAyar.lanKod, null);
            await _islem(() async => 'Yeni kod: ${await _y.anaCihazOl()}');
          },
        ),
      ];

  List<Widget> _bagliGorunum() => [
        OutlinedButton.icon(
          icon: _taraniyor ? _yukleniyor() : const Icon(Icons.search),
          label: Text(_taraniyor ? 'Ana cihaz aranıyor…' : 'Ana cihazı ara'),
          onPressed: _taraniyor
              ? null
              : () async {
                  setState(() => _taraniyor = true);
                  final l = await YerelAgIstemcisi.tara();
                  if (!mounted) return;
                  setState(() {
                    _bulunan = l;
                    _taraniyor = false;
                    if (l.length == 1) _lanAdres.text = l.first.adres;
                  });
                  if (l.isEmpty) _mesaj('Ana cihaz bulunamadı. Aynı WiFi\'da mı, ana cihazda uygulama açık mı? Adresi elle de yazabilirsiniz.');
                },
        ),
        for (final a in _bulunan)
          ListTile(
            dense: true,
            leading: const Icon(Icons.router),
            title: Text(a.ad),
            subtitle: Text(a.adres),
            onTap: () => setState(() => _lanAdres.text = a.adres),
            trailing: _lanAdres.text == a.adres ? const Icon(Icons.check, color: _yesil) : null,
          ),
        const SizedBox(height: 8),
        TextField(
            controller: _lanAdres, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Ana cihaz adresi', hintText: '192.168.1.20')),
        const SizedBox(height: 8),
        TextField(
            controller: _lanKod,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Eşleşme kodu (ana cihazda yazar)', counterText: '')),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: _mesgul ? _yukleniyor() : const Icon(Icons.sync),
          label: const Text('Bağlan ve eşitle'),
          onPressed: _mesgul
              ? null
              : () => _islem(() {
                    if (_lanAdres.text.trim().isEmpty || _lanKod.text.trim().length != 6) {
                      throw const YerelAgHatasi('Adresi ve 6 haneli kodu girin.');
                    }
                    return _y.anaCihazaBaglan(_lanAdres.text, _lanKod.text);
                  }),
        ),
        if (_bekleyenLan > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Ana cihaza gitmeyi bekleyen: $_bekleyenLan değişiklik')),
      ];

  // ═════════════════════════════ SORUNLAR ═════════════════════════════
  Widget _sorunKarti() => _kart([
        _baslik(Icons.report_problem, 'Eşitleme sorunları', renk: _turuncu),
        if (_bekletilen > 0) Text('$_bekletilen kayıt, bağlı olduğu kayıt (ör. carisi) henüz gelmediği için bekliyor; sonraki eşitlemede yerine oturur.'),
        for (final h in _hatalar.take(30))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline, color: _kirmizi),
            title: Text('${_tabloAdi[h['tablo']] ?? h['tablo'] ?? '-'} · ${_zaman(h['zaman'] as String)}'),
            subtitle: Text(h['mesaj'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        if (_hatalar.isNotEmpty)
          TextButton(
            onPressed: () async {
              await _y.hatalariTemizle();
              await _yukle();
            },
            child: const Text('Listeyi temizle'),
          ),
      ]);

  Widget _bilgiKarti() => _kart(const [
        Text(
          'Nasıl çalışır?\n'
          '• Her telefon her değişikliği (ekleme, düzeltme, silme) kendi günlüğüne yazar; eşitlemede yalnız değişenler gider.\n'
          '• Kayıtlar telefonlar arasında ortak kimlikle eşleşir: süt yanlış cariye bağlanmaz.\n'
          '• Aynı günün sütünü iki telefon girerse sabah ve akşam AYRI ayrı birleşir; biri diğerini silmez.\n'
          '• Başka kayıtları iki telefon aynı anda değiştirirse SON değiştiren geçerli olur.\n'
          '• İnternet yoksa değişiklikler telefonda bekler, bağlantı gelince kendiliğinden gider; hiçbir kayıt kaybolmaz.\n'
          '• Terazi listesi ve işlem geçmişi her telefona özeldir, eşitlenmez.\n'
          '• İlk kez: carileri tek telefonda girip eşitleyin, sonra diğer telefonları bağlayın (aynı cari iki kez açılmasın).',
          style: TextStyle(fontSize: 12.5),
        ),
      ]);
}
