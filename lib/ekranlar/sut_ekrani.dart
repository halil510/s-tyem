import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/cari/providers/cari_providers.dart';
import '../features/sut/sut_toplama_durumu.dart';
import '../utils/turkce.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../utils/tarih_secici.dart';
import '../features/donem/donem_kapali_bandi.dart';
import '../features/fis/fis_ekranlari.dart';
import '../features/fis/fis_servisi.dart';
import '../utils/sayi_format.dart';
import '../widgetlar/kaydedilmemis_koruma.dart';
import '../data/repositories/sut_repository.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../core/providers/repository_providers.dart';
import '../core/router/app_router.dart';
import '../features/terazi/providers/terazi_providers.dart';
import '../features/terazi/services/terazi_baglanti_durumu.dart';
import '../widgetlar/rota_rozeti.dart';

/// Süt girişi sekmesi — cari listesi + arama.
///
/// Faz 1/3 modernizasyonu: `DBHelper` yerine `cariRepositoryProvider`
/// kullanıyor.
class SutEkrani extends ConsumerStatefulWidget {
  const SutEkrani({super.key});

  @override
  ConsumerState<SutEkrani> createState() => _SutEkraniState();
}

class _SutEkraniState extends ConsumerState<SutEkrani> {
  String _aramaMetni = '';
  final TextEditingController _aramaCtrl = TextEditingController();

  /// Sekme bellekte açık kalır: saat 12'yi (sabah → akşam) ya da gece yarısını
  /// (yeni gün) geçince tikler kendiliğinden değişsin diye dakikada bir bakılır.
  Timer? _saatTimer;
  String? _sonDurum;

  @override
  void initState() {
    super.initState();
    _saatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final an = ref.read(simdiProvider)();
      final durum = '${gunAnahtari(an)}-${toplamaOgunu(an).name}';
      if (_sonDurum != null && durum != _sonDurum && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saatTimer?.cancel();
    _aramaCtrl.dispose();
    super.dispose();
  }

  List<Cari> _filtreUygula(List<Cari> hepsi) {
    return hepsi.where((c) => aramaEslesir(c.tamAd, _aramaMetni)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final carilerAsync = ref.watch(aktifCarilerProvider);
    final an = ref.watch(simdiProvider)();
    final gun = gunAnahtari(an);
    final ogun = toplamaOgunu(an);
    _sonDurum = '$gun-${ogun.name}';
    // Yüklenirken tikler boş görünür; liste beklemez.
    final bugunkuler = ref.watch(gunlukSutlerProvider(gun)).valueOrNull ?? const <int, Sut>{};

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _aramaCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari ara...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: _aramaMetni.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () { _aramaCtrl.clear(); setState(() => _aramaMetni = ''); },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _aramaMetni = v),
              ),
            ),
          ),
          Expanded(
            child: carilerAsync.when(
              data: (cariler) {
                  final filtrelenen = _filtreUygula(cariler);
                  if (filtrelenen.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.water_drop_outlined, size: 72, color: Colors.blue[200]),
                          const SizedBox(height: 16),
                          Text(
                            cariler.isEmpty ? 'Henüz cari kaydı yok' : 'Cari bulunamadı',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }
                  final alinan = cariler.where((c) => ogunAlindi(bugunkuler[c.id], ogun)).length;
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(aktifCarilerProvider);
                      ref.invalidate(gunlukSutlerProvider(gun));
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrelenen.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          return _ToplamaOzeti(ogun: ogun, alinan: alinan, toplam: cariler.length);
                        }
                        final cari = filtrelenen[i - 1];
                        return _CariKarti(
                          cari: cari,
                          ogun: ogun,
                          ogunKg: ogunKg(bugunkuler[cari.id], ogun),
                          onKaydedildi: () => ref.invalidate(aktifCarilerProvider),
                        );
                      },
                    ),
                  );
                },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Listenin üstünde: "Sabah toplaması · 5 / 12 alındı".
class _ToplamaOzeti extends StatelessWidget {
  final ToplamaOgunu ogun;
  final int alinan;
  final int toplam;
  const _ToplamaOzeti({required this.ogun, required this.alinan, required this.toplam});

  @override
  Widget build(BuildContext context) {
    final bitti = toplam > 0 && alinan >= toplam;
    return Container(
      key: const ValueKey('toplamaOzeti'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bitti ? Colors.green[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(ogun == ToplamaOgunu.sabah ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
              size: 20, color: bitti ? Colors.green[700] : Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${ogunAdi(ogun)} toplaması',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ),
          Icon(Icons.check_circle, size: 18, color: Colors.green[600]),
          const SizedBox(width: 4),
          // Flexible + küçültme: dar ekran / büyük yazıda sayaç sağdan taşmasın (sayı hep okunur).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text('$alinan / $toplam alındı',
                  style: TextStyle(fontWeight: FontWeight.bold, color: bitti ? Colors.green[800] : Colors.grey[800])),
            ),
          ),
        ],
      ),
    );
  }
}

class _CariKarti extends StatelessWidget {
  final Cari cari;
  final ToplamaOgunu ogun;
  /// Bugün bu öğünde alınan kg (0 = henüz alınmadı).
  final double ogunKg;
  final VoidCallback onKaydedildi;
  const _CariKarti({
    required this.cari,
    required this.ogun,
    required this.ogunKg,
    required this.onKaydedildi,
  });

  bool get _alindi => ogunKg > 0;

  Future<void> _girisSayfasinaGit(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SutGirisSayfasi(cari: cari)),
    );
    if (result == true) onKaydedildi();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('sutKarti-${cari.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _alindi ? const Color(0xFFF1FBF3) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: _alindi ? Border.all(color: Colors.green.shade300, width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      // ListTile dokunma efekti en yakın Material'a çizilir; renkli Container
      // onu gizliyordu (dokunduğunu görmüyordun, debug'da hata).
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _alindi
            ? Container(
                key: ValueKey('alindiTik-${cari.id}'),
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.green[600], borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.water_drop, color: Colors.blue[700], size: 22),
              ),
        title: RotaliAd(cari, stil: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_alindi)
              Text('${ogunAdi(ogun)} alındı · ${sayiGoster(ogunKg)} kg',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.green[800], fontSize: 12, fontWeight: FontWeight.w600)),
            Text(cari.hayvanTuru ?? 'Belirtilmemiş', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            if (cari.telefon != null && cari.telefon!.isNotEmpty)
              Text(cari.telefon!, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _girisSayfasinaGit(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('Süt Ekle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        onTap: () => _girisSayfasinaGit(context),
      ),
      ),
    );
  }
}

// ==================== SUT GİRİŞ SAYFASI ====================

/// Bir carinin bir günlük süt girişi.
///
/// - Seçilen günde GİRİLMİŞ öğün (sabah ya da akşam) KİLİTLİDİR: kutu yerine
///   "kayıtlı" yazısı görünür, terazi o öğüne uygulanamaz. Yalnız boş öğün
///   girilir (ör. sabah girilmiş → yalnız akşam). Düzeltme yalnız Cari Detay →
///   Düzenle'den yapılır (kullanıcı kararı 2026-11-05: kafa karışıklığı olmasın).
///   Kayıt katmanı da korur: `gunlukKaydet(kayitliOgunuKoru: true)`.
/// - Bir cari için bir günde tek satır vardır; akşam, sabahın satırına eklenir.
/// - Geçersiz sayı (ör. "12,5x") 0 kg kaydedilmez; alan hata gösterir.
/// - Teraziden gelen ağırlık YALNIZCA "Sabaha/Akşama Uygula" ile alana
///   yazılır. Eskiden her okuma sabah alanının üzerine otomatik
///   yazılıyordu: akşam sütü tartılırken sabah değeri de değişiyordu.
class SutGirisSayfasi extends ConsumerStatefulWidget {
  final Cari cari;
  const SutGirisSayfasi({required this.cari, super.key});

  @override
  ConsumerState<SutGirisSayfasi> createState() => _SutGirisSayfasiState();
}

class _SutGirisSayfasiState extends ConsumerState<SutGirisSayfasi> {
  final _sabahCtrl = TextEditingController();
  final _aksamCtrl = TextEditingController();
  DateTime _seciliTarih = DateUtils.dateOnly(DateTime.now());
  Sut? _mevcutKayit;
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  String? _sabahHata;
  String? _aksamHata;

  String get _tarihStr => DateFormat('yyyy-MM-dd').format(_seciliTarih);

  /// O gün girilmiş öğünler kilitlidir (yalnız Cari Detay → Düzenle).
  bool get _sabahKilitli => (_mevcutKayit?.sabah ?? 0) > 0;
  bool get _aksamKilitli => (_mevcutKayit?.aksam ?? 0) > 0;
  bool get _gunTamam => _sabahKilitli && _aksamKilitli;

  /// Sabah/akşam alanına odaklanınca ekran, alanın ALTINDAKİ KAYDET ve
  /// KAYDET + FİŞ VER düğmeleri de klavyenin üstünde kalacak kadar kayar.
  static const _kaydetGorunurPay = EdgeInsets.fromLTRB(20, 20, 20, 240);

  @override
  void initState() {
    super.initState();
    _gunuYukle();
    // Ekran açıldığında, henüz bağlı değilse kayıtlı varsayılan teraziye
    // otomatik bağlanmayı dene (yalnızca Wi-Fi/Classic — BLE kullanıcı
    // etkileşimi gerektirir). Sessizce dener; başarısız olursa kullanıcı
    // yine de "Bağlan" ile manuel deneyebilir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final durum = ref.read(teraziDurumStreamProvider).valueOrNull;
      if (durum == null || !durum.aktifBaglanti) {
        ref.read(teraziBaglantiNotifierProvider.notifier).baslangicOtomatikBaglan();
      }
    });
  }

  @override
  void dispose() {
    _sabahCtrl.dispose();
    _aksamCtrl.dispose();
    super.dispose();
  }

  /// Seçili günün mevcut kaydını yükler ve alanları doldurur.
  Future<void> _gunuYukle() async {
    setState(() => _yukleniyor = true);
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final kayit = await repo.getGunluk(widget.cari.id!, _tarihStr);
      if (!mounted) return;
      setState(() {
        _mevcutKayit = kayit;
        _sabahCtrl.text = kayit != null && kayit.sabah > 0 ? sayiGirdi(kayit.sabah) : '';
        _aksamCtrl.text = kayit != null && kayit.aksam > 0 ? sayiGirdi(kayit.aksam) : '';
        _sabahHata = _aksamHata = null;
      });
    } catch (e) {
      if (mounted) _snack('Kayıt okunamadı: $e', renk: Colors.red);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Kaydedilen günün fişini önizletir (yazdır / WhatsApp).
  /// [kayittan]: süt az önce kaydedildi → "otomatik yazdır" açıksa fiş kendiliğinden basılır.
  Future<void> _fisGoster({bool kayittan = false}) async {
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final ayar = await FisAyarlari.yukle();
      final fis = await sutFisiOlustur(repo, cari: widget.cari, tarih: _tarihStr, isletmeAdi: ayar.isletmeAdi, ayar: ayar);
      if (fis == null || !mounted) return;
      await fisGoster(context, fis: fis, telefon: widget.cari.telefon, otomatikYazdir: kayittan);
    } catch (e) {
      if (mounted) _snack('Fiş hazırlanamadı: $e', renk: Colors.red);
    }
  }

  Future<void> _kaydet({bool fisVer = false}) async {
    if (_kaydediliyor) return; // çift dokunma
    if (_gunTamam) return;
    // Kilitli öğünün değeri yazıdan değil KAYITTAN alınır (yuvarlama farkı olmasın).
    final sabah = _sabahKilitli ? _mevcutKayit!.sabah : sayiCoz(_sabahCtrl.text);
    final aksam = _aksamKilitli ? _mevcutKayit!.aksam : sayiCoz(_aksamCtrl.text);
    setState(() {
      _sabahHata = sabah == null ? 'Geçersiz miktar' : null;
      _aksamHata = aksam == null ? 'Geçersiz miktar' : null;
    });
    if (sabah == null || aksam == null) return;

    final double yeniGirilen = (_sabahKilitli ? 0.0 : sabah) + (_aksamKilitli ? 0.0 : aksam);
    if (yeniGirilen == 0) {
      _snack(
        _sabahKilitli
            ? 'Lütfen akşam süt miktarını giriniz'
            : _aksamKilitli
                ? 'Lütfen sabah süt miktarını giriniz'
                : 'Lütfen sabah veya akşam süt miktarını giriniz',
        renk: Colors.orange,
      );
      return;
    }

    // Bildirici AWAIT'TEN ÖNCE alınır: kayıt sürerken geri tuşuyla ekran kapanırsa `ref` artık
    // kullanılamaz; kayıt yine yazılır ve bağlı ekranlar (tik, bakiye, Özet) yenilenmeliydi.
    final veriBildir = ref.read(veriSurumuProvider.notifier);
    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final durum = await repo.gunlukKaydet(
        cariId: widget.cari.id!,
        tarih: _tarihStr,
        sabah: sabah,
        aksam: aksam,
        kayitliOgunuKoru: true,
      );
      veriBildir.state++;
      if (!mounted) return;
      final mesaj = switch (durum) {
        SutKayitDurumu.eklendi => 'Süt kaydı eklendi (${sayiGoster(sabah + aksam)} kg)',
        SutKayitDurumu.guncellendi =>
          '${_sabahKilitli ? 'Akşam' : 'Sabah'} sütü eklendi (${sayiGoster(yeniGirilen)} kg) · '
              'günlük ${sayiGoster(sabah + aksam)} kg',
        SutKayitDurumu.silindi => 'Süt kaydı silindi',
        SutKayitDurumu.degismedi => 'Değişiklik yok — kayıt aynı',
      };
      _snack(mesaj, renk: Colors.green[700]!);
      if (fisVer && durum != SutKayitDurumu.silindi) await _fisGoster(kayittan: true);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on KayitliOgunHatasi catch (e) {
      // Bu arada başka yerden girilmiş olabilir → günü yeniden yükle (kilitlensin).
      if (mounted) _snack(e.mesaj, renk: Colors.red);
      if (mounted) await _gunuYukle();
    } on SutKayitHatasi catch (e) {
      if (mounted) _snack(e.mesaj, renk: Colors.red);
    } catch (e) {
      if (mounted) _snack('Kayıt yapılamadı: $e', renk: Colors.red);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  void _snack(String msg, {Color renk = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: renk,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  BoxDecoration get _kartStili => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      );

  /// Alanlardaki değer, kayıtlı değerden farklı mı? (Geri tuşunda uyarı için.)
  /// Geçersiz yazılmış alan da "değişiklik" sayılır.
  bool get _kaydedilmemisVar {
    if (_yukleniyor || _kaydediliyor) return false;
    bool farkli(TextEditingController c, double kayitli) {
      final v = sayiCoz(c.text);
      return v == null || kurusaYuvarla(v) != kurusaYuvarla(kayitli);
    }
    return (!_sabahKilitli && farkli(_sabahCtrl, _mevcutKayit?.sabah ?? 0)) ||
        (!_aksamKilitli && farkli(_aksamCtrl, _mevcutKayit?.aksam ?? 0));
  }

  Future<bool?> _tarihDegisimOnayi() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kaydedilmemiş miktar'),
          content: const Text('Girdiğiniz miktar kaydedilmedi. Tarih değişirse bu giriş kaybolur.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydetmeden Devam')),
          ],
        ),
      );

  late final _alanDinleyici = Listenable.merge([_sabahCtrl, _aksamCtrl]);

  @override
  Widget build(BuildContext context) {
    final agirlikAsync = ref.watch(teraziAgirlikStreamProvider);
    final durumAsync = ref.watch(teraziDurumStreamProvider);
    final teraziBagli = durumAsync.valueOrNull?.aktifBaglanti ?? false;

    // Süt girilip KAYDET'e basılmadan geri tuşuna basılırsa sor.
    return KaydedilmemisKoruma(
      dinle: _alanDinleyici,
      degisiklikVar: () => _kaydedilmemisVar,
      kaydet: _kaydet,
      baslik: 'Süt kaydedilmedi',
      child: _ekran(agirlikAsync, durumAsync, teraziBagli),
    );
  }

  Widget _ekran(AsyncValue<String> agirlikAsync, AsyncValue<TeraziBaglantiDurumu> durumAsync, bool teraziBagli) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text(widget.cari.tamAd, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.withOpacity(0.1)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _kartStili,
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.person, color: Colors.blue[700], size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.cari.tamAd, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(widget.cari.hayvanTuru ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: _kartStili,
              child: TarihSecici(
                // Anahtar: vazgeçilince seçici eski güne geri döner (kendi iç durumunu tutar).
                key: ValueKey(_seciliTarih),
                baslangicTarihi: _seciliTarih,
                showRange: false,
                sonTarih: DateUtils.dateOnly(DateTime.now()),
                onTarihSecildi: (bas, _) async {
                  final yeni = DateUtils.dateOnly(bas);
                  if (yeni == _seciliTarih) return;
                  // Girilmiş ama kaydedilmemiş miktar SORMADAN silinmesin (Hızlı Süt Girişi gibi).
                  if (_kaydedilmemisVar && await _tarihDegisimOnayi() != true) {
                    if (mounted) setState(() {});
                    return;
                  }
                  _seciliTarih = yeni;
                  _gunuYukle();
                },
              ),
            ),
            const SizedBox(height: 14),
            DonemKapaliBandi(tarih: _seciliTarih),
            if (_mevcutKayit != null) ...[
              _MevcutKayitBandi(kayit: _mevcutKayit!),
              const SizedBox(height: 14),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _kartStili,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.water_drop, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text('Süt Miktarları',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      if (_yukleniyor) ...[
                        const Spacer(),
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_sabahKilitli)
                    _KilitliOgun(
                      key: const ValueKey('kilitliSabah'),
                      etiket: 'Sabah Sütü',
                      kg: _mevcutKayit!.sabah,
                      ikon: Icon(Icons.wb_sunny, color: Colors.orange[400]),
                    )
                  else
                  TextField(
                    controller: _sabahCtrl,
                    enabled: !_yukleniyor,
                    autofocus: false,
                    decoration: InputDecoration(
                      labelText: 'Sabah Sütü (kg)',
                      prefixIcon: Icon(Icons.wb_sunny, color: Colors.orange[400]),
                      hintText: '0',
                      errorText: _sabahHata,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    scrollPadding: _kaydetGorunurPay,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_sabahHata != null) setState(() => _sabahHata = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_aksamKilitli)
                    _KilitliOgun(
                      key: const ValueKey('kilitliAksam'),
                      etiket: 'Akşam Sütü',
                      kg: _mevcutKayit!.aksam,
                      ikon: Icon(Icons.nightlight_round, color: Colors.indigo[400]),
                    )
                  else
                  TextField(
                    controller: _aksamCtrl,
                    enabled: !_yukleniyor,
                    decoration: InputDecoration(
                      labelText: 'Akşam Sütü (kg)',
                      prefixIcon: Icon(Icons.nightlight_round, color: Colors.indigo[400]),
                      hintText: '0',
                      errorText: _aksamHata,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    scrollPadding: _kaydetGorunurPay,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_aksamHata != null) setState(() => _aksamHata = null);
                    },
                    onSubmitted: (_) => _kaydet(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _kaydediliyor || _yukleniyor || _gunTamam ? null : _kaydet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _kaydediliyor
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle),
                label: Text(
                  _kaydediliyor ? 'Kaydediliyor...' : 'KAYDET',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                // Gün tamamsa yalnız fiş verilir (kayıt değişmez).
                onPressed: _kaydediliyor || _yukleniyor
                    ? null
                    : (_gunTamam ? () => _fisGoster() : () => _kaydet(fisVer: true)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[800],
                  side: BorderSide(color: Colors.blue[700]!, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: Text(
                  _gunTamam ? 'FİŞ VER' : 'KAYDET + FİŞ VER',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // Terazi kartı EN ALTTA: klavye açıkken sabah/akşam alanları ile
            // KAYDET düğmesi birlikte ekranda kalır → seri giriş.
            const SizedBox(height: 14),
            _CanliTeraziKarti(
              agirlikAsync: agirlikAsync,
              durumAsync: durumAsync,
              // Kayıtlı öğüne terazi uygulanamaz (düğme kapalı).
              onSabahaUygula: _sabahKilitli
                  ? null
                  : (kg) {
                      _sabahCtrl.text = kg;
                      setState(() => _sabahHata = null);
                      _snack('Sabah sütüne $kg kg aktarıldı', renk: Colors.blue[700]!);
                    },
              onAksamaUygula: _aksamKilitli
                  ? null
                  : (kg) {
                      _aksamCtrl.text = kg;
                      setState(() => _aksamHata = null);
                      _snack('Akşam sütüne $kg kg aktarıldı', renk: Colors.indigo[700]!);
                    },
              onBaglanTikla: () => context.push(AppRoutes.terazi),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.terazi),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[700],
                  side: BorderSide(color: Colors.blue[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(teraziBagli ? Icons.settings : Icons.bluetooth),
                label: Text(teraziBagli ? 'Terazi Ayarları' : 'Terazi Bağla'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seçili günde zaten kayıt varsa gösterilen bilgi bandı.
class _MevcutKayitBandi extends StatelessWidget {
  final Sut kayit;
  const _MevcutKayitBandi({required this.kayit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _metin,
              style: TextStyle(fontSize: 12.5, color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }

  String get _metin {
    const duzelt = 'Düzeltmek için: Cariler → cari → Detay → Düzenle.';
    final sabah = kayit.sabah > 0, aksam = kayit.aksam > 0;
    if (sabah && aksam) {
      return 'Bu günün sütü tamam: sabah ${sayiGoster(kayit.sabah)} kg, '
          'akşam ${sayiGoster(kayit.aksam)} kg. $duzelt';
    }
    if (sabah) return 'Sabah sütü kayıtlı (${sayiGoster(kayit.sabah)} kg). Yalnız akşam sütü girilebilir. $duzelt';
    if (aksam) return 'Akşam sütü kayıtlı (${sayiGoster(kayit.aksam)} kg). Yalnız sabah sütü girilebilir. $duzelt';
    return 'Bu tarihte boş bir süt kaydı var.';
  }
}

/// Kayıtlı (kilitli) öğün: düzenlenebilir kutu yerine salt yazı.
class _KilitliOgun extends StatelessWidget {
  final String etiket;
  final double kg;
  final Widget ikon;
  const _KilitliOgun({super.key, required this.etiket, required this.kg, required this.ikon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          ikon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(etiket, style: TextStyle(color: Colors.grey[800], fontSize: 15)),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('${sayiGoster(kg)} kg',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.green[800])),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock, size: 16, color: Colors.green[700]),
          const SizedBox(width: 4),
          Text('kayıtlı', style: TextStyle(fontSize: 12, color: Colors.green[700])),
        ],
      ),
    );
  }
}

/// Süt girişi ekranında her zaman görünen, canlı terazi kartı.
///
/// Bağlantı durumunu ve teraziden anlık gelen ağırlığı büyük puntoyla
/// gösterir; bağlıyken tek dokunuşla okunan değeri sabah/akşam alanına
/// aktarma kısayolları sunar. Bağlı değilse "Bağlan" kısayoluyla
/// doğrudan Terazi Bağlantısı ekranına yönlendirir.
class _CanliTeraziKarti extends StatelessWidget {
  final AsyncValue<String> agirlikAsync;
  final AsyncValue<TeraziBaglantiDurumu> durumAsync;
  final ValueChanged<String>? onSabahaUygula; // null → öğün kayıtlı, düğme kapalı
  final ValueChanged<String>? onAksamaUygula;
  final VoidCallback onBaglanTikla;

  const _CanliTeraziKarti({
    required this.agirlikAsync,
    required this.durumAsync,
    required this.onSabahaUygula,
    required this.onAksamaUygula,
    required this.onBaglanTikla,
  });

  @override
  Widget build(BuildContext context) {
    final durum = durumAsync.valueOrNull ?? TeraziBaglantiDurumu.bagliDegil;
    final bagli = durum.aktifBaglanti;
    final kg = agirlikAsync.valueOrNull;
    final durumRengi = bagli ? Colors.greenAccent.shade400 : (durum.mesgul ? Colors.orange[300]! : Colors.grey[500]!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: bagli
            ? LinearGradient(
                colors: [Colors.blue[800]!, Colors.blue[900]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: bagli ? null : Colors.grey[100],
        borderRadius: BorderRadius.circular(18),
        border: bagli ? null : Border.all(color: Colors.grey[300]!),
        boxShadow: bagli
            ? [BoxShadow(color: Colors.blue.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (bagli)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: durumRengi,
                    boxShadow: [BoxShadow(color: durumRengi.withOpacity(0.8), blurRadius: 6, spreadRadius: 1)],
                  ),
                )
              else
                Icon(
                  durum.mesgul ? Icons.sync : Icons.scale_outlined,
                  size: 14,
                  color: durumRengi,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bagli ? 'TERAZİ BAĞLI — CANLI ÖLÇÜM' : durum.gorunenMetin.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bagli ? Colors.white70 : durumRengi,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (!bagli)
                TextButton.icon(
                  onPressed: onBaglanTikla,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.bluetooth, size: 16),
                  label: const Text('Bağlan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.scale_rounded, color: bagli ? Colors.white : Colors.grey[400], size: 30),
              const SizedBox(width: 10),
              // Ağırlık asla kesilmez; dar ekranda / büyük yazıda küçülür.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    kg ?? '--.--',
                    style: TextStyle(
                      color: bagli ? Colors.white : Colors.grey[400],
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 6),
                child: Text('kg', style: TextStyle(color: bagli ? Colors.white70 : Colors.grey[400], fontSize: 16)),
              ),
            ],
          ),
          if (bagli && kg != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSabahaUygula == null ? null : () => onSabahaUygula!(kg),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Sabaha Uygula', style: TextStyle(fontSize: 12))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAksamaUygula == null ? null : () => onAksamaUygula!(kg),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.nightlight_round, size: 16),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Akşama Uygula', style: TextStyle(fontSize: 12))),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
