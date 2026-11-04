import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../utils/tarih_secici.dart';
import '../features/donem/donem_kapali_bandi.dart';
import '../utils/sayi_format.dart';
import '../data/repositories/sut_repository.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../core/providers/repository_providers.dart';
import '../core/router/app_router.dart';
import '../features/terazi/providers/terazi_providers.dart';
import '../features/terazi/services/terazi_baglanti_durumu.dart';

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

  @override
  void dispose() {
    _aramaCtrl.dispose();
    super.dispose();
  }

  List<Cari> _filtreUygula(List<Cari> hepsi) {
    if (_aramaMetni.isEmpty) return hepsi;
    final q = _aramaMetni.toLowerCase();
    return hepsi.where((c) => c.tamAd.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final carilerAsync = ref.watch(cariRepositoryProvider);

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
              data: (repo) => FutureBuilder<List<Cari>>(
                future: repo.getAll(sadeceAktif: true),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final cariler = snap.data ?? [];
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
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(cariRepositoryProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrelenen.length,
                      itemBuilder: (ctx, i) => _CariKarti(
                        cari: filtrelenen[i],
                        onKaydedildi: () => ref.invalidate(cariRepositoryProvider),
                      ),
                    ),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _CariKarti extends StatelessWidget {
  final Cari cari;
  final VoidCallback onKaydedildi;
  const _CariKarti({required this.cari, required this.onKaydedildi});

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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.water_drop, color: Colors.blue[700], size: 22),
        ),
        title: Text(cari.tamAd, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
    );
  }
}

// ==================== SUT GİRİŞ SAYFASI ====================

/// Bir carinin bir günlük süt girişi.
///
/// - Seçilen günde kayıt VARSA alanlar o kayıtla dolar ve kaydetmek onu
///   GÜNCELLER. Eskiden her kaydet yeni satır ekliyordu; sabah ve akşam
///   ayrı girilince aynı güne mükerrer kayıt oluşuyordu.
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
        _sabahCtrl.text = kayit != null && kayit.sabah > 0 ? sayiGoster(kayit.sabah) : '';
        _aksamCtrl.text = kayit != null && kayit.aksam > 0 ? sayiGoster(kayit.aksam) : '';
        _sabahHata = _aksamHata = null;
      });
    } catch (e) {
      if (mounted) _snack('Kayıt okunamadı: $e', renk: Colors.red);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    final sabah = sayiCoz(_sabahCtrl.text);
    final aksam = sayiCoz(_aksamCtrl.text);
    setState(() {
      _sabahHata = sabah == null ? 'Geçersiz miktar' : null;
      _aksamHata = aksam == null ? 'Geçersiz miktar' : null;
    });
    if (sabah == null || aksam == null) return;

    if (sabah == 0 && aksam == 0) {
      if (_mevcutKayit == null) {
        _snack('Lütfen sabah veya akşam süt miktarını giriniz', renk: Colors.orange);
        return;
      }
      final sil = await _silmeOnayi();
      if (sil != true) return;
    }

    setState(() => _kaydediliyor = true);
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final durum = await repo.gunlukKaydet(
        cariId: widget.cari.id!,
        tarih: _tarihStr,
        sabah: sabah,
        aksam: aksam,
      );
      ref.veriDegisti();
      if (!mounted) return;
      final mesaj = switch (durum) {
        SutKayitDurumu.eklendi => 'Süt kaydı eklendi (${sayiGoster(sabah + aksam)} kg)',
        SutKayitDurumu.guncellendi => 'Süt kaydı güncellendi (${sayiGoster(sabah + aksam)} kg)',
        SutKayitDurumu.silindi => 'Süt kaydı silindi',
        SutKayitDurumu.degismedi => 'Değişiklik yok — kayıt aynı',
      };
      _snack(mesaj, renk: Colors.green[700]!);
      Navigator.pop(context, true);
    } on SutKayitHatasi catch (e) {
      if (mounted) _snack(e.mesaj, renk: Colors.red);
    } catch (e) {
      if (mounted) _snack('Kayıt yapılamadı: $e', renk: Colors.red);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<bool?> _silmeOnayi() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kaydı sil'),
          content: Text(
            '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_seciliTarih)} tarihli '
            '${sayiGoster(_mevcutKayit!.toplam)} kg süt kaydı silinsin mi?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

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

  @override
  Widget build(BuildContext context) {
    final agirlikAsync = ref.watch(teraziAgirlikStreamProvider);
    final durumAsync = ref.watch(teraziDurumStreamProvider);
    final teraziBagli = durumAsync.valueOrNull?.aktifBaglanti ?? false;

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
            _CanliTeraziKarti(
              agirlikAsync: agirlikAsync,
              durumAsync: durumAsync,
              onSabahaUygula: (kg) {
                _sabahCtrl.text = kg;
                setState(() => _sabahHata = null);
                _snack('Sabah sütüne $kg kg aktarıldı', renk: Colors.blue[700]!);
              },
              onAksamaUygula: (kg) {
                _aksamCtrl.text = kg;
                setState(() => _aksamHata = null);
                _snack('Akşam sütüne $kg kg aktarıldı', renk: Colors.indigo[700]!);
              },
              onBaglanTikla: () => context.push(AppRoutes.terazi),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: _kartStili,
              child: TarihSecici(
                baslangicTarihi: _seciliTarih,
                showRange: false,
                sonTarih: DateUtils.dateOnly(DateTime.now()),
                onTarihSecildi: (bas, _) {
                  _seciliTarih = DateUtils.dateOnly(bas);
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
                      const Text('Süt Miktarları', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (_yukleniyor) ...[
                        const Spacer(),
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _sabahCtrl,
                    enabled: !_yukleniyor,
                    decoration: InputDecoration(
                      labelText: 'Sabah Sütü (kg)',
                      prefixIcon: Icon(Icons.wb_sunny, color: Colors.orange[400]),
                      hintText: '0',
                      errorText: _sabahHata,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_sabahHata != null) setState(() => _sabahHata = null);
                    },
                  ),
                  const SizedBox(height: 12),
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
                onPressed: _kaydediliyor || _yukleniyor ? null : _kaydet,
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
                  _kaydediliyor ? 'Kaydediliyor...' : (_mevcutKayit != null ? 'GÜNCELLE' : 'KAYDET'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
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
              'Bu tarihte kayıt var: sabah ${sayiGoster(kayit.sabah)} kg, '
              'akşam ${sayiGoster(kayit.aksam)} kg. Kaydederseniz bu kayıt güncellenir.',
              style: TextStyle(fontSize: 12.5, color: Colors.amber[900]),
            ),
          ),
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
  final ValueChanged<String> onSabahaUygula;
  final ValueChanged<String> onAksamaUygula;
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
              Text(
                bagli ? 'TERAZİ BAĞLI — CANLI ÖLÇÜM' : durum.gorunenMetin.toUpperCase(),
                style: TextStyle(
                  color: bagli ? Colors.white70 : durumRengi,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
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
              Text(
                kg ?? '--.--',
                style: TextStyle(
                  color: bagli ? Colors.white : Colors.grey[400],
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  height: 1,
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
                    onPressed: () => onSabahaUygula(kg),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: const Text('Sabaha Uygula', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onAksamaUygula(kg),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.nightlight_round, size: 16),
                    label: const Text('Akşama Uygula', style: TextStyle(fontSize: 12)),
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
