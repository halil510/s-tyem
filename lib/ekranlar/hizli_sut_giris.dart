import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/turkce.dart';
import '../features/donem/donem_kapali_bandi.dart';
import 'package:intl/intl.dart';

import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../data/repositories/sut_repository.dart';
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../utils/sayi_format.dart';
import '../widgetlar/kaydedilmemis_koruma.dart';

/// Tüm aktif cariler için tek ekrandan, bir günün sabah/akşam sütü.
///
/// Güvenlik kuralları:
/// - Kayıt TEK transaction'dır: bir satır bile geçersizse hiçbir şey
///   yazılmaz (yarım kalmış toplu giriş müşteri hesaplarını bozamaz).
/// - Geçersiz sayı girilen satır kırmızı işaretlenir, 0 kg kaydedilmez.
/// - Kayıtlı bir satırın iki alanı da boşaltılırsa kayıt silinir; bu,
///   kaydetmeden önce ayrıca onaylatılır.
class HizliSutGiris extends ConsumerStatefulWidget {
  const HizliSutGiris({super.key});

  @override
  ConsumerState<HizliSutGiris> createState() => _HizliSutGirisState();
}

class _HizliSutGirisState extends ConsumerState<HizliSutGiris> {
  final _tarihFormat = DateFormat('yyyy-MM-dd');
  final _aramaCtrl = TextEditingController();
  final Map<int, TextEditingController> _sabahCtrl = {};
  final Map<int, TextEditingController> _aksamCtrl = {};
  final Set<int> _hataliSatirlar = {};

  List<Cari> _cariler = [];
  Map<int, Sut> _mevcutKayitlar = {};
  DateTime _tarih = DateUtils.dateOnly(DateTime.now());
  String _arama = '';
  bool _yukleniyor = true;
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _ilkYukleme();
  }

  @override
  void dispose() {
    // Her cari için oluşturulan controller'lar temizlenmezse bellek sızar.
    for (final c in [..._sabahCtrl.values, ..._aksamCtrl.values]) {
      c.dispose();
    }
    _aramaCtrl.dispose();
    super.dispose();
  }

  Future<void> _ilkYukleme() async {
    try {
      final cariRepo = await ref.read(cariRepositoryProvider.future);
      _cariler = await cariRepo.getAll(sadeceAktif: true);
      for (final cari in _cariler) {
        _sabahCtrl[cari.id!] = TextEditingController();
        _aksamCtrl[cari.id!] = TextEditingController();
      }
      await _gunuYukle();
    } catch (e) {
      _snack('Veriler yüklenemedi: $e', Colors.red);
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Seçili günün kayıtlarını TEK sorguda çeker ve alanları doldurur.
  Future<void> _gunuYukle() async {
    if (mounted) setState(() => _yukleniyor = true);
    try {
      final sutRepo = await ref.read(sutRepositoryProvider.future);
      final kayitlar = await sutRepo.getGunlukHepsi(_tarihFormat.format(_tarih));
      if (!mounted) return;
      setState(() {
        _mevcutKayitlar = kayitlar;
        _hataliSatirlar.clear();
        for (final cari in _cariler) {
          final k = kayitlar[cari.id!];
          _sabahCtrl[cari.id!]!.text = k != null && k.sabah > 0 ? sayiGoster(k.sabah) : '';
          _aksamCtrl[cari.id!]!.text = k != null && k.aksam > 0 ? sayiGoster(k.aksam) : '';
        }
      });
    } catch (e) {
      _snack('Kayıtlar okunamadı: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _tarihSec() async {
    final secilen = await showDatePicker(
      context: context,
      initialDate: _tarih,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      locale: const Locale('tr', 'TR'),
    );
    if (secilen == null || DateUtils.isSameDay(secilen, _tarih)) return;
    if (_kaydedilmemisDegisiklikVar() && await _degisiklikleriAtOnayi() != true) return;
    _tarih = DateUtils.dateOnly(secilen);
    await _gunuYukle();
  }

  bool _kaydedilmemisDegisiklikVar() {
    for (final cari in _cariler) {
      final k = _mevcutKayitlar[cari.id!];
      final sabah = sayiCoz(_sabahCtrl[cari.id!]!.text);
      final aksam = sayiCoz(_aksamCtrl[cari.id!]!.text);
      if (sabah != (k?.sabah ?? 0) || aksam != (k?.aksam ?? 0)) return true;
    }
    return false;
  }

  Future<void> _tumunuKaydet() async {
    if (_kaydediliyor) return;
    FocusScope.of(context).unfocus();

    final girdiler = <GunlukSutGirdisi>[];
    final silinecekler = <Cari>[];
    final hatalilar = <int>{};
    for (final cari in _cariler) {
      final id = cari.id!;
      final sabah = sayiCoz(_sabahCtrl[id]!.text);
      final aksam = sayiCoz(_aksamCtrl[id]!.text);
      if (sabah == null || aksam == null) {
        hatalilar.add(id);
        continue;
      }
      final mevcut = _mevcutKayitlar[id];
      if (mevcut == null && sabah == 0 && aksam == 0) continue;
      if (mevcut != null && mevcut.sabah == sabah && mevcut.aksam == aksam) continue;
      if (mevcut != null && sabah == 0 && aksam == 0) silinecekler.add(cari);
      girdiler.add(GunlukSutGirdisi(cariId: id, sabah: sabah, aksam: aksam));
    }

    setState(() {
      _hataliSatirlar
        ..clear()
        ..addAll(hatalilar);
    });
    if (hatalilar.isNotEmpty) {
      _snack('${hatalilar.length} satırda geçersiz miktar var (kırmızı). Hiçbir kayıt yapılmadı.', Colors.red);
      return;
    }
    if (girdiler.isEmpty) {
      _snack('Kaydedilecek değişiklik yok.', Colors.blueGrey);
      return;
    }
    if (silinecekler.isNotEmpty && await _silmeOnayi(silinecekler) != true) return;

    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final sonuc = await repo.topluGunlukKaydet(_tarihFormat.format(_tarih), girdiler);
      ref.veriDegisti();
      final parcalar = [
        if (sonuc.eklenen > 0) '${sonuc.eklenen} yeni',
        if (sonuc.guncellenen > 0) '${sonuc.guncellenen} güncellendi',
        if (sonuc.silinen > 0) '${sonuc.silinen} silindi',
      ];
      _snack('Kaydedildi: ${parcalar.join(', ')}', Colors.green[700]!);
      await _gunuYukle();
    } on SutKayitHatasi catch (e) {
      _snack('${e.mesaj} Hiçbir kayıt yapılmadı.', Colors.red);
    } catch (e) {
      _snack('Kayıt yapılamadı, hiçbir değişiklik yazılmadı: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<bool?> _silmeOnayi(List<Cari> cariler) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kayıtlar silinecek'),
          content: Text(
            'Şu carilerin bu tarihteki süt kaydı boşaltıldı ve SİLİNECEK:\n\n'
            '${cariler.map((c) => '• ${c.tamAd}').join('\n')}\n\nDevam edilsin mi?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil ve Kaydet', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

  Future<bool?> _degisiklikleriAtOnayi() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler'),
          content: const Text('Bu tarihte kaydedilmemiş girişler var. Tarih değişirse bu girişler kaybolur.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydetmeden Devam')),
          ],
        ),
      );

  void _snack(String mesaj, Color renk) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mesaj), backgroundColor: renk, behavior: SnackBarBehavior.floating));
  }

  List<Cari> get _gorunenCariler {
    if (_arama.isEmpty) return _cariler;
    return _cariler.where((c) => aramaEslesir(c.tamAd, _arama)).toList();
  }

  double get _gunlukToplamKg =>
      _mevcutKayitlar.values.fold(0.0, (t, s) => t + s.toplam);

  @override
  Widget build(BuildContext context) {
    // Girilip kaydedilmeden geri tuşuna basılırsa sor; "Kaydet" seçilirse
    // kaydedip (hata yoksa) ekrandan çıkar.
    return KaydedilmemisKoruma(
      dinle: Listenable.merge([..._sabahCtrl.values, ..._aksamCtrl.values]),
      degisiklikVar: () => !_yukleniyor && !_kaydediliyor && _kaydedilmemisDegisiklikVar(),
      kaydet: () async {
        await _tumunuKaydet();
        if (mounted && !_kaydedilmemisDegisiklikVar()) Navigator.of(context).pop();
      },
      baslik: 'Süt girişleri kaydedilmedi',
      child: _ekran(context),
    );
  }

  Widget _ekran(BuildContext context) {
    final gorunen = _gorunenCariler;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hızlı Süt Girişi'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 2,
        actions: [
          IconButton(
            icon: _kaydediliyor
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: _kaydediliyor || _yukleniyor ? null : _tumunuKaydet,
            tooltip: 'Tümünü Kaydet',
          ),
        ],
      ),
      body: Column(
        children: [
          _TarihKarti(tarih: _tarih, onDegistir: _yukleniyor ? null : _tarihSec),
          DonemKapaliBandi(tarih: _tarih, margin: const EdgeInsets.fromLTRB(16, 0, 16, 8)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _aramaCtrl,
              decoration: InputDecoration(
                hintText: 'Cari ara...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _arama.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _aramaCtrl.clear();
                          setState(() => _arama = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _arama = v.trim()),
            ),
          ),
          const _BaslikSatiri(),
          Expanded(
            child: _yukleniyor
                ? const Center(child: CircularProgressIndicator())
                : gorunen.isEmpty
                    ? Center(child: Text(_cariler.isEmpty ? 'Aktif cari yok' : 'Cari bulunamadı'))
                    : ListView.builder(
                        itemCount: gorunen.length,
                        itemBuilder: (context, i) {
                          final cari = gorunen[i];
                          return _CariSatiri(
                            key: ValueKey(cari.id),
                            cari: cari,
                            mevcutKayit: _mevcutKayitlar[cari.id!],
                            hatali: _hataliSatirlar.contains(cari.id),
                            sabahCtrl: _sabahCtrl[cari.id!]!,
                            aksamCtrl: _aksamCtrl[cari.id!]!,
                            onDegisti: () {
                              if (_hataliSatirlar.remove(cari.id)) setState(() {});
                            },
                          );
                        },
                      ),
          ),
          _AltPanel(
            kayitliSayisi: _mevcutKayitlar.length,
            cariSayisi: _cariler.length,
            gunlukToplamKg: _gunlukToplamKg,
            kaydediliyor: _kaydediliyor,
            onKaydet: _kaydediliyor || _yukleniyor ? null : _tumunuKaydet,
          ),
        ],
      ),
    );
  }
}

class _TarihKarti extends StatelessWidget {
  final DateTime tarih;
  final VoidCallback? onDegistir;
  const _TarihKarti({required this.tarih, required this.onDegistir});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: ListTile(
        leading: Icon(Icons.calendar_today, color: Colors.blue[700]),
        title: Text(
          DateFormat('dd MMMM yyyy EEEE', 'tr_TR').format(tarih),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Süt Giriş Tarihi'),
        trailing: IconButton(
          icon: const Icon(Icons.edit_calendar),
          onPressed: onDegistir,
          tooltip: 'Tarih Değiştir',
        ),
      ),
    );
  }
}

class _BaslikSatiri extends StatelessWidget {
  const _BaslikSatiri();

  @override
  Widget build(BuildContext context) {
    final stil = TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700], fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Cari', style: stil)),
          Expanded(child: Text('Sabah (kg)', style: stil, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(child: Text('Akşam (kg)', style: stil, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _CariSatiri extends StatelessWidget {
  final Cari cari;
  final Sut? mevcutKayit;
  final bool hatali;
  final TextEditingController sabahCtrl;
  final TextEditingController aksamCtrl;
  final VoidCallback onDegisti;

  const _CariSatiri({
    super.key,
    required this.cari,
    required this.mevcutKayit,
    required this.hatali,
    required this.sabahCtrl,
    required this.aksamCtrl,
    required this.onDegisti,
  });

  Widget _alan(TextEditingController ctrl, IconData ikon, Color renk) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.next,
        onChanged: (_) => onDegisti(),
        decoration: InputDecoration(
          hintText: '0',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: Icon(ikon, size: 16, color: renk),
          prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          filled: true,
          fillColor: hatali ? Colors.red[50] : (mevcutKayit != null ? Colors.green[50] : null),
          enabledBorder: hatali
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cari.tamAd,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    mevcutKayit != null
                        ? 'Kayıtlı · ${sayiGoster(mevcutKayit!.toplam)} kg'
                        : (cari.hayvanTuru ?? 'Belirtilmemiş'),
                    style: TextStyle(
                      fontSize: 11,
                      color: mevcutKayit != null ? Colors.green[700] : Colors.grey[600],
                      fontWeight: mevcutKayit != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (hatali)
                    const Text('Geçersiz miktar', style: TextStyle(fontSize: 11, color: Colors.red)),
                ],
              ),
            ),
            _alan(sabahCtrl, Icons.wb_sunny, Colors.orange[600]!),
            const SizedBox(width: 8),
            _alan(aksamCtrl, Icons.nightlight_round, Colors.blue[600]!),
          ],
        ),
      ),
    );
  }
}

class _AltPanel extends StatelessWidget {
  final int kayitliSayisi;
  final int cariSayisi;
  final double gunlukToplamKg;
  final bool kaydediliyor;
  final VoidCallback? onKaydet;

  const _AltPanel({
    required this.kayitliSayisi,
    required this.cariSayisi,
    required this.gunlukToplamKg,
    required this.kaydediliyor,
    required this.onKaydet,
  });

  Widget _kutu(String baslik, String deger, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: renk.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: renk.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(deger, maxLines: 1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk)),
          ),
          Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: renk)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(top: BorderSide(color: Colors.grey[300]!)),
        ),
        child: Column(
          children: [
            // Kutular genişliği paylaşır; büyük günlük toplam dar ekranda taşmaz.
            Row(
              children: [
                Expanded(child: _kutu('Kayıtlı', '$kayitliSayisi', Colors.green)),
                const SizedBox(width: 8),
                Expanded(
                  child: _kutu(
                      'Boş', '${cariSayisi - kayitliSayisi < 0 ? 0 : cariSayisi - kayitliSayisi}', Colors.grey),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _kutu('Günlük Toplam', '${sayiGoster(gunlukToplamKg)} kg', Colors.blue)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: onKaydet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: kaydediliyor
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 20),
                label: Text(
                  kaydediliyor ? 'Kaydediliyor...' : 'Tümünü Kaydet',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
