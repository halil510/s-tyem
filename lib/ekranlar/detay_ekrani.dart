import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/cari_model.dart';
import '../models/sut_model.dart';
import '../models/yem_model.dart';
import 'package:intl/intl.dart';
import '../utils/sayi_format.dart';
import '../utils/excel_export.dart';
import '../core/router/app_router.dart';
import '../data/repositories/sut_repository.dart';
import '../data/repositories/yem_repository.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'detay/kayit_duzenle_dialoglari.dart';
import '../features/fis/fis_ekranlari.dart';
import '../features/fis/fis_servisi.dart';

class DetayEkrani extends ConsumerStatefulWidget {
  final Cari cari;
  const DetayEkrani({required this.cari, super.key});

  @override
  ConsumerState<DetayEkrani> createState() => _DetayEkraniState();
}

class _DetayEkraniState extends ConsumerState<DetayEkrani> {
  late SutRepository _sutRepo;
  late YemRepository _yemRepo;
  List<Sut> _sutKayitlari = [];
  List<Yem> _yemKayitlari = [];
  DateTimeRange? _selectedRange;
  bool _yukleniyor = true;
  int _seciliTab = 0;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);

    _sutRepo = await ref.read(sutRepositoryProvider.future);
    _yemRepo = await ref.read(yemRepositoryProvider.future);

    final simdi = DateTime.now();
    final baslangic = DateTime(simdi.year, simdi.month, 1);
    final bitis = DateTime(simdi.year, simdi.month + 1, 0);

    _selectedRange = DateTimeRange(start: baslangic, end: bitis);

    await _kayitlariGetir();
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _kayitlariGetir() async {
    if (_selectedRange == null) return;

    final baslangicStr = DateFormat('yyyy-MM-dd').format(_selectedRange!.start);
    final bitisStr = DateFormat('yyyy-MM-dd').format(_selectedRange!.end);

    List<Sut> sutler = await _sutRepo.getByCari(widget.cari.id!, baslangicStr, bitisStr);
    List<Yem> yemler = await _yemRepo.getByCari(widget.cari.id!, baslangicStr, bitisStr);

    if (!mounted) return;
    setState(() {
      _sutKayitlari = List.from(sutler.reversed);
      _yemKayitlari = List.from(yemler.reversed);
    });
  }

  Future<void> _tarihAraligiSec() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      // Ay sonu bugünden ileride olabilir; lastDate < initialDateRange.end
      // olursa showDateRangePicker assert hatası verip çöküyordu.
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: _selectedRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedRange = picked;
        _yukleniyor = true;
      });
      await _kayitlariGetir();
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _sutSil(Sut sut) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Süt Kaydı Sil'),
        content: Text(
            '${DateFormat('dd MMMM yyyy', 'tr_TR').format(DateTime.parse(sut.tarih))} tarihli süt kaydını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _sutRepo.delete(sut.id!);
      ref.veriDegisti();
      await _kayitlariGetir();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Süt kaydı silindi')),
        );
      }
    }
  }

  Future<void> _yemSil(Yem yem) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yem Kaydı Sil'),
        content: Text(
            '${DateFormat('dd MMMM yyyy', 'tr_TR').format(DateTime.parse(yem.tarih))} tarihli yem kaydını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (result == true) {
      await _yemRepo.delete(yem.id!);
      ref.veriDegisti();
      await _kayitlariGetir();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yem kaydı silindi')),
        );
      }
    }
  }

  void _excelExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excel\'e Aktar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download, color: Colors.blue),
              title: const Text('Süt Raporu'),
              onTap: () => _sutRaporuOlustur(),
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text('Yem Raporu'),
              onTap: () => _yemRaporuOlustur(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sutRaporuOlustur() async {
    Navigator.pop(context);
    try {
      final cariler = [widget.cari];
      final file = await ExcelExport.exportSutRaporu(
        cariler: cariler,
        sutler: _sutKayitlari,
        startDate: _selectedRange!.start,
        endDate: _selectedRange!.end,
        raporAdi: '${widget.cari.ad}_${widget.cari.soyad}_Sut_Raporu',
      );
      await ExcelExport.shareFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FormatException ? e.message : 'Hata: $e')),
        );
      }
    }
  }

  Future<void> _yemRaporuOlustur() async {
    Navigator.pop(context);
    try {
      final cariler = [widget.cari];
      final file = await ExcelExport.exportYemRaporu(
        cariler: cariler,
        yemler: _yemKayitlari,
        startDate: _selectedRange!.start,
        endDate: _selectedRange!.end,
        raporAdi: '${widget.cari.ad}_${widget.cari.soyad}_Yem_Raporu',
      );
      await ExcelExport.shareFile(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FormatException ? e.message : 'Hata: $e')),
        );
      }
    }
  }

  double get _toplamSut => _sutKayitlari.fold(0, (sum, sut) => sum + sut.toplam);
  double get _toplamYem => _yemKayitlari.fold(0, (sum, yem) => sum + yem.toplam);

  Future<void> _sutFisi(Sut sut) async {
    try {
      final repo = await ref.read(sutRepositoryProvider.future);
      final ayar = await FisAyarlari.yukle();
      final fis = await sutFisiOlustur(repo,
          cari: widget.cari, tarih: sut.tarih.substring(0, 10), isletmeAdi: ayar.isletmeAdi);
      if (fis == null || !mounted) return;
      await fisGoster(context, fis: fis, telefon: widget.cari.telefon);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fiş hazırlanamadı: $e')));
    }
  }

  Future<void> _sutDuzenle(Sut sut) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SutDuzenleDialog(sut: sut),
    );
    if (result == true) {
      await _kayitlariGetir();
      setState(() {});
    }
  }

  Future<void> _yemDuzenle(Yem yem) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => YemDuzenleDialog(yem: yem),
    );
    if (result == true) {
      await _kayitlariGetir();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('${widget.cari.ad} ${widget.cari.soyad}'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _excelExportDialog,
            tooltip: 'Excel\'e Aktar',
          ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildUstBilgiKarti(),
                _buildIstatistikKartlari(),
                _buildTabBar(),
                Expanded(child: _buildTabIcerigi()),
              ],
            ),
    );
  }

  Widget _buildUstBilgiKarti() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person, size: 32, color: Colors.blue[700]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.cari.ad} ${widget.cari.soyad}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.cari.hayvanTuru ?? 'Belirtilmemiş',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.cari.telefon != null && widget.cari.telefon!.isNotEmpty) ...[
                Icon(Icons.phone, size: 18, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.cari.telefon!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ),
              ] else
                const Expanded(child: SizedBox()),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor: Colors.blue[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.blue[200]!),
                  ),
                ),
                icon: Icon(Icons.payments, size: 18, color: Colors.blue[700]),
                label: Text(
                  'Ödeme',
                  style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onPressed: () {
                  context.push(AppRoutes.cariHesap, extra: widget.cari);
                },
              ),
            ],
          ),
          if (widget.cari.adres != null && widget.cari.adres!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildBilgiSatiri(Icons.location_on, widget.cari.adres!),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: _tarihAraligiSec,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _selectedRange != null
                        ? '${DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedRange!.start)} - ${DateFormat('dd MMMM yyyy', 'tr_TR').format(_selectedRange!.end)}'
                        : 'Tarih Seçin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: Colors.blue[800]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.blue[700]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBilgiSatiri(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIstatistikKartlari() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _istatistikKarti(
              'Toplam Süt',
              '${sayiGoster(_toplamSut)} kg',
              Icons.local_drink,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _istatistikKarti(
              'Toplam Yem',
              '${sayiGoster(_toplamYem)} kg',
              Icons.agriculture,
              Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _istatistikKarti(String baslik, String deger, IconData ikon, Color renk) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: renk.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ikon, color: renk, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            deger,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: renk),
          ),
          Text(
            baslik,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tabItem('Süt Kayıtları', 0),
          _tabItem('Yem Kayıtları', 1),
        ],
      ),
    );
  }

  Widget _tabItem(String text, int index) {
    final secili = _seciliTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _seciliTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: secili ? Colors.blue[700] : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secili ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabIcerigi() {
    return _seciliTab == 0 ? _buildSutListesi() : _buildYemListesi();
  }

  Widget _buildSutListesi() {
    if (_sutKayitlari.isEmpty) {
      return _bosListeWidget('Süt kaydı bulunmuyor', Icons.local_drink_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sutKayitlari.length,
      itemBuilder: (context, index) {
        final sut = _sutKayitlari[index];
        final bugun = DateTime.now();
        final sutTarih = DateTime.parse(sut.tarih);
        final bugunMu = sutTarih.year == bugun.year &&
            sutTarih.month == bugun.month &&
            sutTarih.day == bugun.day;
        return _sutKarti(sut, bugunKayit: bugunMu);
      },
    );
  }

  Widget _sutKarti(Sut sut, {bool bugunKayit = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: bugunKayit ? Colors.green : Colors.transparent, width: bugunKayit ? 2 : 0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Sol simge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bugunKayit ? Colors.green[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                bugunKayit ? Icons.today : Icons.local_drink,
                color: bugunKayit ? Colors.green : Colors.blue[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            // Orta alan (tarih ve açıklama) – esnek genişlik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd MMMM yyyy', 'tr_TR').format(DateTime.parse(sut.tarih)),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (bugunKayit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green),
                          ),
                          child: const Text(
                            'BUGÜN',
                            style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sabah: ${sayiGoster(sut.sabah)}kg • Akşam: ${sayiGoster(sut.aksam)}kg',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            // Sağ badge ve menü
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: bugunKayit ? Colors.green[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${sayiGoster(sut.toplam)}kg',
                    style: TextStyle(
                      color: bugunKayit ? Colors.green[700] : Colors.blue[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
                    const PopupMenuItem(value: 'fis', child: Text('Fiş Ver')),
                    const PopupMenuItem(value: 'sil', child: Text('Sil', style: TextStyle(color: Colors.red))),
                  ],
                  onSelected: (value) {
                    if (value == 'duzenle') {
                      _sutDuzenle(sut);
                    } else if (value == 'fis') {
                      _sutFisi(sut);
                    } else if (value == 'sil') {
                      _sutSil(sut);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYemListesi() {
    if (_yemKayitlari.isEmpty) {
      return _bosListeWidget('Yem kaydı bulunmuyor', Icons.agriculture_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _yemKayitlari.length,
      itemBuilder: (context, index) {
        final yem = _yemKayitlari[index];
        final bugun = DateTime.now();
        final yemTarih = DateTime.parse(yem.tarih);
        final bugunMu = yemTarih.year == bugun.year &&
            yemTarih.month == bugun.month &&
            yemTarih.day == bugun.day;
        return _yemKarti(yem, bugunKayit: bugunMu);
      },
    );
  }

  Widget _yemKarti(Yem yem, {bool bugunKayit = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: bugunKayit ? Colors.green : Colors.transparent, width: bugunKayit ? 2 : 0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bugunKayit ? Colors.green[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    bugunKayit ? Icons.today : Icons.agriculture,
                    color: bugunKayit ? Colors.green : Colors.green[700],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          DateFormat('dd MMMM yyyy', 'tr_TR').format(DateTime.parse(yem.tarih)),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (bugunKayit) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green),
                          ),
                          child: const Text(
                            'BUGÜN',
                            style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: bugunKayit ? Colors.green[50] : Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${sayiGoster(yem.toplam)}kg',
                        style: TextStyle(
                          color: bugunKayit ? Colors.green[700] : Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'duzenle', child: Text('Düzenle')),
                        const PopupMenuItem(value: 'sil', child: Text('Sil', style: TextStyle(color: Colors.red))),
                      ],
                      onSelected: (value) {
                        if (value == 'duzenle') {
                          _yemDuzenle(yem);
                        } else if (value == 'sil') {
                          _yemSil(yem);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (yem.sutYemi > 0) _yemTipiChip('Süt: ${sayiGoster(yem.sutYemi)}kg', bugunKayit),
                if (yem.besiYemi > 0) _yemTipiChip('Besi: ${sayiGoster(yem.besiYemi)}kg', bugunKayit),
                if (yem.bBaslangic > 0) _yemTipiChip('Başlangıç: ${sayiGoster(yem.bBaslangic)}kg', bugunKayit),
                if (yem.bBuyutme > 0) _yemTipiChip('Büyütme: ${sayiGoster(yem.bBuyutme)}kg', bugunKayit),
                if (yem.kuzuYemi > 0) _yemTipiChip('Kuzu: ${sayiGoster(yem.kuzuYemi)}kg', bugunKayit),
                if (yem.tavukYemi > 0) _yemTipiChip('Tavuk: ${sayiGoster(yem.tavukYemi)}kg', bugunKayit),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _yemTipiChip(String text, bool bugunKayit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bugunKayit ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: bugunKayit ? Border.all(color: Colors.green) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: bugunKayit ? Colors.green[700] : Colors.grey[700],
          fontWeight: bugunKayit ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _bosListeWidget(String mesaj, IconData ikon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ikon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            mesaj,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }
}
