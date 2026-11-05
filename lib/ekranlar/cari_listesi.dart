import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/turkce.dart';
import 'package:go_router/go_router.dart';
import '../models/cari_model.dart';
import 'cari_ekle.dart';
import 'detay_ekrani.dart';
import '../core/router/app_router.dart';
import '../utils/excel_export.dart';
import '../services/whatsapp_service.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/donem_kilidi.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'package:intl/intl.dart';
import '../utils/sayi_format.dart';
import '../services/toplu_mesaj_servisi.dart';
import 'cari/cari_dialoglari.dart';
import 'cari/cari_duzenle.dart';

class CariListesi extends ConsumerStatefulWidget {
  const CariListesi({super.key});

  @override
  ConsumerState<CariListesi> createState() => _CariListesiState();
}

class _CariListesiState extends ConsumerState<CariListesi> {
  late CariRepository _cariRepo;
  late SutRepository _sutRepo;
  late YemRepository _yemRepo;
  List<Cari> _cariler = [];
  List<Cari> _filtrelenen = [];
  final TextEditingController _aramaController = TextEditingController();
  bool _yukleniyor = true;
  List<int> _seciliCariler = [];
  
  // Ayın başı ve sonu
  DateTime get _ayBaslangic => DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get _ayBitis => DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  
  // Her cari için bu ayki süt toplamlarını saklayan map
  Map<int, double> _aylikSutToplamlari = {};
  
  // Hayvan türlerine göre toplam süt miktarları
  Map<String, double> _hayvanTuruneGoreToplamSut = {
    'İnek': 0.0,
    'Koyun': 0.0,
    'Tavuk': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    _aramaController.dispose();
    super.dispose();
  }

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    
    try {
      // Repository'leri veritabanı hazır olduğunda al
      _cariRepo = await ref.read(cariRepositoryProvider.future);
      _sutRepo = await ref.read(sutRepositoryProvider.future);
      _yemRepo = await ref.read(yemRepositoryProvider.future);

      // Carileri getir
      final liste = await _cariRepo.getAll(sadeceAktif: true);
      
      // Bu ayki süt toplamları: TEK gruplu sorgu (eskiden cari başına ayrı sorgu).
      final aylik = await _sutRepo.toplamByCariInRange(
        DateFormat('yyyy-MM-dd').format(_ayBaslangic),
        DateFormat('yyyy-MM-dd').format(_ayBitis),
      );
      _aylikSutToplamlari = {};
      _hayvanTuruneGoreToplamSut = {
        'İnek': 0.0,
        'Koyun': 0.0,
        'Tavuk': 0.0,
      };
      
      for (var cari in liste) {
        double toplamSut = 0.0;
        
        if (cari.id != null) {
          toplamSut = aylik[cari.id!] ?? 0.0;
          
          // Hayvan türüne göre toplamı güncelle
          final hayvanTuru = cari.hayvanTuru ?? '';
          if (_hayvanTuruneGoreToplamSut.containsKey(hayvanTuru)) {
            _hayvanTuruneGoreToplamSut[hayvanTuru] = 
                (_hayvanTuruneGoreToplamSut[hayvanTuru] ?? 0.0) + toplamSut;
          }
        }
        
        _aylikSutToplamlari[cari.id!] = toplamSut;
      }
      
      if (!mounted) return;
      setState(() {
        _cariler = liste;
        // Yenilemede arama kutusundaki filtre korunur (eskiden tüm liste dönüyordu).
        _filtrelenen = _filtrele(liste, _aramaController.text);
        _yukleniyor = false;
      });
      
    } catch (e) {
      debugPrint('Veri yükleme hatası: $e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  /// Türkçe İ/ı farkını gözeten arama (büyük harfli "İSMAİL", "ismail" ile bulunur).
  List<Cari> _filtrele(List<Cari> liste, String sorgu) => liste
      .where((c) => aramaEslesir(c.tamAd, sorgu) || aramaEslesir(c.hayvanTuru ?? '', sorgu))
      .toList();

  void _aramaYap(String sorgu) {
    setState(() => _filtrelenen = _filtrele(_cariler, sorgu));
  }

  void _cariSec(int cariId, bool secili) {
    setState(() {
      if (secili) {
        _seciliCariler.add(cariId);
      } else {
        _seciliCariler.remove(cariId);
      }
    });
  }

  void _tumunuSec(bool secili) {
    setState(() {
      if (secili) {
        _seciliCariler = _filtrelenen.map((c) => c.id!).toList();
      } else {
        _seciliCariler.clear();
      }
    });
  }

  Future<void> _cariSil(int cariId) async {
    // Kalıcı silme, carinin TÜM süt/yem/ödeme kayıtlarını da siler
    // (ON DELETE CASCADE). Hareketi olan cari için önce pasife almayı öner.
    final sayilar = await _cariRepo.hareketSayilari(cariId);
    final hareketVar = sayilar.sut + sayilar.yem + sayilar.odeme > 0;
    if (!mounted) return;

    final secim = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cari Sil'),
        content: Text(hareketVar
            ? 'Bu carinin ${sayilar.sut} süt, ${sayilar.yem} yem ve ${sayilar.odeme} ödeme/tahsilat kaydı var.\n\n'
                'Kalıcı silerseniz BU KAYITLARIN HEPSİ geri dönülmez şekilde silinir ve hesap geçmişi kaybolur.\n\n'
                'Önerilen: cariyi PASİFE ALIN — listelerden kalkar, kayıtları korunur, istediğiniz zaman geri açabilirsiniz.'
            : 'Bu carinin hiç kaydı yok. Silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'iptal'),
            child: const Text('İptal'),
          ),
          if (hareketVar)
            TextButton(
              onPressed: () => Navigator.pop(context, 'sil'),
              child: const Text('Kalıcı Sil', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, hareketVar ? 'pasif' : 'sil'),
            child: Text(hareketVar ? 'Pasife Al' : 'Sil'),
          ),
        ],
      ),
    );

    if (secim == 'sil' && hareketVar && await _kaliciSilmeIkinciOnay() != true) return;

    if (secim == 'pasif') {
      await _cariRepo.pasifeAl(cariId);
    } else if (secim == 'sil') {
      try {
        await _cariRepo.delete(cariId);
      } on DonemKapaliHatasi {
        _mesajGoster('Bu carinin kapatılmış dönemlerde kaydı var; kalıcı silinemez. '
            'Hesap geçmişi korunsun diye cariyi "Pasife Al" ile listeden kaldırabilirsiniz.');
        return;
      }
    } else {
      return;
    }
    ref.veriDegisti();
    await _verileriYukle();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(secim == 'pasif' ? 'Cari pasife alındı, kayıtları korundu' : 'Cari silindi')),
    );
  }

  Future<bool?> _kaliciSilmeIkinciOnay() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Son onay'),
          content: const Text('Carinin tüm hesap geçmişi kalıcı olarak silinecek. Bu işlem GERİ ALINAMAZ.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Evet, kalıcı sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

  /// Pasife alınmış carileri listeler ve yeniden aktif yapmayı sağlar.
  Future<void> _pasifCarileriGoster() async {
    final pasifler = (await _cariRepo.getAll()).where((c) => !c.aktif).toList();
    if (!mounted) return;
    final aktifEdilecek = await showModalBottomSheet<Cari>(
      context: context,
      builder: (ctx) => SafeArea(
        child: pasifler.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Pasif cari yok', textAlign: TextAlign.center),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Pasif Cariler', style: TextStyle(fontWeight: FontWeight.bold))),
                  for (final c in pasifler)
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: Text(c.tamAd),
                      trailing: TextButton(
                        onPressed: () => Navigator.pop(ctx, c),
                        child: const Text('Aktif Yap'),
                      ),
                    ),
                ],
              ),
      ),
    );
    if (aktifEdilecek == null) return;
    await _cariRepo.aktifYap(aktifEdilecek.id!);
    ref.veriDegisti();
    await _verileriYukle();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${aktifEdilecek.tamAd} yeniden aktif')),
    );
  }

  // ─── Excel raporları ────────────────────────────────────────────────

  void _excelExportDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Excel'den cari içeri alma üst sağdaki ⋮ menüsüne taşındı.
        title: const Text('Excel\'e Aktar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Süt Raporu'),
              onTap: () {
                Navigator.pop(ctx);
                _excelRaporu(sut: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Yem Raporu'),
              onTap: () {
                Navigator.pop(ctx);
                _excelRaporu(sut: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _excelRaporu({required bool sut}) async {
    final aralik = await raporTarihAraligiSor(context, sut ? 'Süt Raporu' : 'Yem Raporu');
    if (aralik == null || !mounted) return;
    final gun = DateFormat('yyyy-MM-dd');
    final bas = gun.format(aralik.start), bit = gun.format(aralik.end);
    final ad = '${sut ? 'Sut' : 'Yem'}_Raporu_${DateFormat('yyyy_MM_dd').format(DateTime.now())}';
    try {
      final sutler = sut ? await _sutRepo.getAllInRange(bas, bit) : null;
      final yemler = sut ? null : await _yemRepo.getAllInRange(bas, bit);
      // Aktif cariler + bu aralıkta kaydı olan pasif cariler (adıyla görünsün;
      // eskiden pasif carinin sütü raporda ve GENEL TOPLAM'da hiç yoktu).
      final kayitli = {...?sutler?.map((s) => s.cariId), ...?yemler?.map((y) => y.cariId)};
      final cariler = (await _cariRepo.getAll())
          .where((c) => c.aktif || kayitli.contains(c.id))
          .toList();
      final file = sut
          ? await ExcelExport.exportSutRaporu(
              cariler: cariler,
              sutler: sutler!,
              startDate: aralik.start,
              endDate: aralik.end,
              raporAdi: ad,
            )
          : await ExcelExport.exportYemRaporu(
              cariler: cariler,
              yemler: yemler!,
              startDate: aralik.start,
              endDate: aralik.end,
              raporAdi: ad,
            );
      await ExcelExport.shareFile(file);
      _mesajGoster('${sut ? 'Süt' : 'Yem'} raporu oluşturuldu');
    } catch (e) {
      _mesajGoster('Rapor oluşturulamadı: $e');
    }
  }

  // ─── Toplu WhatsApp ─────────────────────────────────────────────────

  List<Cari> get _seciliCariNesneleri =>
      _cariler.where((c) => c.id != null && _seciliCariler.contains(c.id)).toList();

  Future<void> _whatsappGonder() async {
    final secili = _seciliCariNesneleri;
    if (secili.isEmpty) {
      _mesajGoster('Lütfen en az bir cari seçin');
      return;
    }
    final secenek = await whatsappSecenekSor(context, secili.length);
    if (secenek == null || !mounted) return;

    final bugun = DateTime.now();
    final gun = DateFormat('yyyy-MM-dd');
    final tarihMetni = DateFormat('dd MMMM yyyy', 'tr_TR').format(bugun);

    switch (secenek) {
      case WhatsappSecenek.sutRaporu:
        final bas = gun.format(sutRaporuBaslangici(bugun));
        await _topluGonder(secili, 'süt raporu', (cari) async {
          final t = sutRaporuToplamlari(
              await _sutRepo.getByCari(cari.id!, bas, gun.format(bugun)), bugun);
          return WhatsAppService.createSutRaporuMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            gunlukToplam: t.gunluk,
            haftalikToplam: t.haftalik,
            aylikToplam: t.aylik,
            tarih: tarihMetni,
          );
        });
      case WhatsappSecenek.yemRaporu:
        final bas = gun.format(DateTime(bugun.year, bugun.month, 1));
        await _topluGonder(secili, 'yem raporu', (cari) async {
          final y = yemRaporuDetayi(await _yemRepo.getByCari(cari.id!, bas, gun.format(bugun)));
          return WhatsAppService.createYemRaporuMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            toplamYem: y.toplam,
            yemDetay: y.detay,
            tarih: tarihMetni,
          );
        });
      case WhatsappSecenek.ozelMesaj:
        final mesaj = await ozelMesajSor(context, secili.length);
        if (mesaj == null) return;
        await _topluGonder(secili, 'mesaj', (_) async => mesaj);
      case WhatsappSecenek.odemeBildirimi:
        final b = await odemeBildirimiSor(context, secili.length);
        if (b == null) return;
        await _topluGonder(
          secili,
          'ödeme bildirimi',
          (cari) async => WhatsAppService.createOdemeBildirimiMessage(
            cariAd: '${cari.ad} ${cari.soyad}',
            tutar: b.tutar,
            donem: b.donem,
          ),
        );
    }
  }

  Future<void> _topluGonder(List<Cari> cariler, String ne, MesajUretici uret) async {
    final sonuc = await TopluMesajServisi().gonder(cariler, uret);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: SingleChildScrollView(child: Text(sonuc.ozet(ne))),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(label: 'Tamam', onPressed: () {}),
    ));
  }

  void _mesajGoster(String metin) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(metin)));
  }

  Widget build(BuildContext context) {
    // Sekmeler IndexedStack'te bellekte durur: başka sekmede süt/yem/ödeme/cari
    // değişince bu liste (bu ayki süt toplamları dahil) kendiliğinden yenilenir.
    ref.listen<int>(veriSurumuProvider, (_, __) => _verileriYukle());
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildAramaCubugu(),
          if (_seciliCariler.isNotEmpty) _buildSecimAppBar(),
          _buildIstatistikKartlari(),
          _buildCariListesi(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_seciliCariler.isNotEmpty)
            FloatingActionButton(
              onPressed: _whatsappGonder,
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              child: const Icon(Icons.message),
            ),
          const SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () async {
              final sonuc = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CariEkle()),
              );
              if (sonuc == true) _verileriYukle();
            },
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            child: const Icon(Icons.person_add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildAramaCubugu() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _aramaController,
                decoration: const InputDecoration(
                  hintText: 'Cari ara...',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: _aramaYap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pasifCarileriGoster,
            tooltip: 'Pasif Cariler',
            icon: const Icon(Icons.person_off_outlined, color: Colors.grey),
          ),
          const SizedBox(width: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _excelExportDialog,
              icon: Image.asset(
                'assets/images/excel.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecimAppBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_seciliCariler.length} cari seçildi',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Tümünü Seç',
                onPressed: () => _tumunuSec(true),
              ),
              IconButton(
                icon: const Icon(Icons.deselect),
                tooltip: 'Seçimi Temizle',
                onPressed: () => _tumunuSec(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIstatistikKartlari() {
    final inekSayisi = _cariler.where((c) => c.hayvanTuru == 'İnek').length;
    final koyunSayisi = _cariler.where((c) => c.hayvanTuru == 'Koyun').length;
    final tavukSayisi = _cariler.where((c) => c.hayvanTuru == 'Tavuk').length;

    // Toplam süt miktarını hesapla
    final toplamSutMiktari = _hayvanTuruneGoreToplamSut.values.fold(
      0.0, 
      (sum, value) => sum + (value ?? 0.0)
    );

    // Kompakt, eşit yükseklikte kartlar (ikon solda, sayı + başlık sağda).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: IntrinsicHeight(
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _istatistikKarti('Toplam', _cariler.length, Icons.people, Colors.blue, null),
          _istatistikKarti('İnek', inekSayisi, Icons.agriculture, Colors.green, _hayvanTuruneGoreToplamSut['İnek']),
          _istatistikKarti('Koyun', koyunSayisi, Icons.pets, Colors.orange, _hayvanTuruneGoreToplamSut['Koyun']),
          _istatistikKarti('Tavuk', tavukSayisi, Icons.egg, Colors.purple, _hayvanTuruneGoreToplamSut['Tavuk']),
          _istatistikKarti('Süt Toplam', null, Icons.local_drink, Colors.blue, toplamSutMiktari),
        ],
        ),
      ),
    );
  }

  /// Küçük özet kartı: solda renkli ikon, sağda sayı (büyük), altında
  /// başlık ve varsa bu ayki süt toplamı.
  Widget _istatistikKarti(String baslik, int? sayi, IconData ikon, Color renk, double? sutToplam) {
    final anaDeger = sayi?.toString() ?? '${sayiGoster(sutToplam ?? 0)} kg';
    final altBilgi = sayi != null && sutToplam != null ? '${sayiGoster(sutToplam)} kg' : null;
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: renk.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: renk.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ikon, color: renk, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                anaDeger,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk, height: 1.1),
              ),
              Text(
                altBilgi == null ? baslik : '$baslik · $altBilgi',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCariListesi() {
    if (_yukleniyor) {
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_filtrelenen.isEmpty) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _aramaController.text.isEmpty ? 'Henüz cari kaydı yok' : 'Sonuç bulunamadı',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_aramaController.text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final sonuc = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CariEkle()),
                    );
                    if (sonuc == true) _verileriYukle();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('İlk Cariyi Ekle'),
                ),
              ),
          ],
        ),
      );
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: _verileriYukle,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          itemCount: _filtrelenen.length,
          itemBuilder: (context, index) {
            final cari = _filtrelenen[index];
            return _cariKarti(cari);
          },
        ),
      ),
    );
  }

  Widget _cariKarti(Cari cari) {
    final secili = _seciliCariler.contains(cari.id);
    final buAykiSutToplam = cari.id != null ? _aylikSutToplamlari[cari.id!] ?? 0.0 : 0.0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_seciliCariler.isNotEmpty)
              Checkbox(
                value: secili,
                onChanged: (value) => _cariSec(cari.id!, value!),
              ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _hayvanRengi(cari.hayvanTuru).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _hayvanIkonu(cari.hayvanTuru),
                color: _hayvanRengi(cari.hayvanTuru),
                size: 24,
              ),
            ),
          ],
        ),
        title: Text(
          '${cari.ad} ${cari.soyad}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              cari.hayvanTuru ?? 'Belirtilmemiş',
              style: TextStyle(
                color: _hayvanRengi(cari.hayvanTuru),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                // Bu ayki süt toplamını göster
                if (buAykiSutToplam > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_drink, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          '${sayiGoster(buAykiSutToplam)} kg',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (cari.telefon != null && cari.telefon!.isNotEmpty)
              Text(
                cari.telefon!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'detay', child: Text('Detay')),
            const PopupMenuItem(value: 'ekstre', child: Text('Hesap Ekstresi')),
            const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
            const PopupMenuItem(value: 'sil', child: Text('Sil')),
          ],
          onSelected: (value) {
            if (value == 'detay') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetayEkrani(cari: cari)),
              );
            } else if (value == 'ekstre') {
              context.push(AppRoutes.cariHesap, extra: cari);
            } else if (value == 'duzenle') {
              _cariDuzenle(cari);
            } else if (value == 'sil') {
              _cariSil(cari.id!);
            }
          },
        ),
        onTap: () {
          if (_seciliCariler.isNotEmpty) {
            _cariSec(cari.id!, !secili);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetayEkrani(cari: cari)),
            );
          }
        },
        onLongPress: () => _cariSec(cari.id!, !secili),
      ),
    );
  }

  Future<void> _cariDuzenle(Cari cari) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CariDuzenle(cari: cari)),
    );
    if (result == true) _verileriYukle();
  }

  IconData _hayvanIkonu(String? tur) {
    switch (tur) {
      case 'İnek': return Icons.agriculture;
      case 'Koyun': return Icons.pets;
      case 'Tavuk': return Icons.egg;
      default: return Icons.pets;
    }
  }

  Color _hayvanRengi(String? tur) {
    switch (tur) {
      case 'İnek': return Colors.blue;
      case 'Koyun': return Colors.green;
      case 'Tavuk': return Colors.orange;
      default: return Colors.grey;
    }
  }
}
