import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cari_model.dart';
import '../models/cari_fiyat_model.dart';
import '../data/repositories/cari_repository.dart';
import '../data/repositories/fiyat_repository.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../utils/sayi_format.dart';

// Yem türleri sabit liste
const List<Map<String, dynamic>> kYemTurleri = [
  {
    'alan': 'sutYemiFiyat',
    'ad': 'Süt Yemi',
    'ikon': Icons.water_drop,
    'renk': Color(0xFF0D47A1)
  },
  {
    'alan': 'besiYemiFiyat',
    'ad': 'Besi Yemi',
    'ikon': Icons.agriculture,
    'renk': Color(0xFF4E342E)
  },
  {
    'alan': 'bBaslangicFiyat',
    'ad': 'B. Başlangıç',
    'ikon': Icons.start,
    'renk': Color(0xFF6A1B9A)
  },
  {
    'alan': 'bBuyutmeFiyat',
    'ad': 'B. Büyütme',
    'ikon': Icons.trending_up,
    'renk': Color(0xFF283593)
  },
  {
    'alan': 'kuzuYemiFiyat',
    'ad': 'Kuzu Yemi',
    'ikon': Icons.pets,
    'renk': Color(0xFFE65100)
  },
  {
    'alan': 'tavukYemiFiyat',
    'ad': 'Tavuk Yemi',
    'ikon': Icons.egg,
    'renk': Color(0xFFF9A825)
  },
];

class YemFiyatEkrani extends ConsumerStatefulWidget {
  const YemFiyatEkrani({super.key});

  @override
  ConsumerState<YemFiyatEkrani> createState() => _YemFiyatEkraniState();
}

class _YemFiyatEkraniState extends ConsumerState<YemFiyatEkrani> {
  late CariRepository _cariRepo;
  late CariFiyatRepository _fiyatRepo;
  List<Cari> _cariler = [];
  Map<int, CariFiyat> _fiyatlar = {};
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  DateTime _seciliAy = DateTime.now();

  // Her cari için her yem türü için controller: _controllers[cariId][alan]
  final Map<int, Map<String, TextEditingController>> _controllers = {};

  // "Tüm carilere aynı yem fiyatı" kartı
  final _topluCtrl = TextEditingController();
  String _topluAlan = kYemTurleri.first['alan'] as String;
  String? _topluHata;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    for (final m in _controllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _topluCtrl.dispose();
    super.dispose();
  }

  String get _ayStr => DateFormat('yyyy-MM').format(_seciliAy);
  String get _ayGoster => DateFormat('MMMM yyyy', 'tr_TR').format(_seciliAy);

  double _fiyatDegeri(CariFiyat f, String alan) {
    switch (alan) {
      case 'sutYemiFiyat':
        return f.sutYemiFiyat;
      case 'besiYemiFiyat':
        return f.besiYemiFiyat;
      case 'bBaslangicFiyat':
        return f.bBaslangicFiyat;
      case 'bBuyutmeFiyat':
        return f.bBuyutmeFiyat;
      case 'kuzuYemiFiyat':
        return f.kuzuYemiFiyat;
      case 'tavukYemiFiyat':
        return f.tavukYemiFiyat;
      default:
        return 0;
    }
  }

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    _cariRepo = await ref.read(cariRepositoryProvider.future);
    _fiyatRepo = await ref.read(cariFiyatRepositoryProvider.future);
    _cariler = await _cariRepo.getAll(sadeceAktif: true);

    // Controller'ları temizle
    for (final m in _controllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _controllers.clear();

    _fiyatlar = await _fiyatRepo.getAyFiyatlariHepsi(
        _cariler.map((c) => c.id!).toList(), _ayStr);

    for (final cari in _cariler) {
      final f = _fiyatlar[cari.id!]!;
      _controllers[cari.id!] = {};
      for (final tur in kYemTurleri) {
        final alan = tur['alan'] as String;
        final deger = _fiyatDegeri(f, alan);
        _controllers[cari.id!]![alan] = TextEditingController(
          text: deger > 0 ? deger.toStringAsFixed(2) : '',
        );
      }
    }

    setState(() => _yukleniyor = false);
  }

  Future<void> _aySec() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _seciliAy,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Ay Seçin',
    );
    if (picked != null) {
      setState(() => _seciliAy = DateTime(picked.year, picked.month, 1));
      await _verileriYukle();
    }
  }

  /// Alandan değeri okur; alan BOŞSA 0 DEĞİL, mevcut (önceki aydan
  /// devralınmış olabilecek) değeri döner. Aksi halde boş bırakılan
  /// bir yem türü sessizce 0 ₺ olarak kaydedilir ve bu, o aydan
  /// itibaren gerçek önceki-ay fiyatının bulunmasını kalıcı olarak
  /// engeller (bkz. sut_fiyat_ekrani.dart'taki aynı düzeltme).
  double _oku(int cariId, String alan, double mevcutDeger) {
    final text = _controllers[cariId]?[alan]?.text ?? '';
    if (text.trim().isEmpty) return mevcutDeger;
    return sayiCoz(text) ?? mevcutDeger;
  }

  Future<void> _kaydet() async {
    final hataliVar = _controllers.values
        .expand((alanlar) => alanlar.values)
        .any((ctrl) => sayiCoz(ctrl.text) == null);
    if (hataliVar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Geçersiz fiyat var, lütfen girdiğiniz değerleri kontrol edin'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final kaydedilecek = <CariFiyat>[];
      for (final cari in _cariler) {
        final mevcut = _fiyatlar[cari.id!]!;
        kaydedilecek.add(CariFiyat(
          cariId: cari.id!,
          ay: _ayStr,
          sutFiyat: mevcut.sutFiyat,
          sutYemiFiyat: _oku(cari.id!, 'sutYemiFiyat', mevcut.sutYemiFiyat),
          besiYemiFiyat: _oku(cari.id!, 'besiYemiFiyat', mevcut.besiYemiFiyat),
          bBaslangicFiyat:
              _oku(cari.id!, 'bBaslangicFiyat', mevcut.bBaslangicFiyat),
          bBuyutmeFiyat: _oku(cari.id!, 'bBuyutmeFiyat', mevcut.bBuyutmeFiyat),
          kuzuYemiFiyat: _oku(cari.id!, 'kuzuYemiFiyat', mevcut.kuzuYemiFiyat),
          tavukYemiFiyat:
              _oku(cari.id!, 'tavukYemiFiyat', mevcut.tavukYemiFiyat),
        ));
      }
      // Tek transaction: ya hepsi ya hiçbiri. Ay ortasından geçerli süt
      // fiyatı satırlarının yem fiyatları da bu ayın yem fiyatına çekilir.
      await _fiyatRepo.topluKaydet(kaydedilecek, yemFiyatiniAyaYay: true);
      ref.veriDegisti();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Yem fiyatları kaydedildi'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    }
    setState(() => _kaydediliyor = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFF8),
      appBar: AppBar(
        title: const Text('Yem Fiyatları',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_kaydediliyor)
            const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)))
          else
            TextButton.icon(
              onPressed: _kaydet,
              icon: const Icon(Icons.save, color: Colors.white, size: 18),
              label: const Text('Kaydet',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Ay seçici
                InkWell(
                  onTap: _aySec,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF2E7D32).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.grass,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Yem Fiyatı Dönemi',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text(_ayGoster,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ])),
                        const Icon(Icons.edit_calendar, color: Colors.white70),
                      ],
                    ),
                  ),
                ),

                // Bilgi notu
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green[100]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.green[700], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Her cariye farklı fiyat girebilirsiniz. Boş = önceki ay.',
                              style: TextStyle(
                                  color: Colors.green[800], fontSize: 12))),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Cari listesi (toplu fiyat kartı listenin başında; klavye
                // açıkken dar ekranda taşmasın diye birlikte kayar)
                Expanded(
                  child: _cariler.isEmpty
                      ? Center(
                          child: Text('Henüz cari yok',
                              style: TextStyle(color: Colors.grey[500])))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                          itemCount: _cariler.length + 1,
                          itemBuilder: (ctx, i) => i == 0
                              ? _topluFiyatKarti()
                              : Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: _cariFiyatKarti(_cariler[i - 1]),
                                ),
                        ),
                ),
              ],
            ),
    );
  }

  /// Seçilen yem türünün fiyatını TÜM carilerin alanına yazar. KAYDETMEZ:
  /// kullanıcı listeyi görüp (gerekirse tek tek değiştirip) "Kaydet"e basar.
  void _tumuneUygula() {
    final fiyat = sayiCoz(_topluCtrl.text);
    if (fiyat == null || fiyat <= 0) {
      setState(() => _topluHata = 'Geçerli bir fiyat girin (ör. 12,50)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _topluHata = null;
      for (final alanlar in _controllers.values) {
        alanlar[_topluAlan]!.text = fiyat.toStringAsFixed(2);
      }
    });
    final ad = kYemTurleri.firstWhere((t) => t['alan'] == _topluAlan)['ad'];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_cariler.length} cariye $ad: ${fiyat.toStringAsFixed(2)} ₺ yazıldı. Kaydetmeyi unutmayın.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'KAYDET', onPressed: _kaydet),
    ));
  }

  Widget _topluFiyatKarti() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tüm carilere aynı yem fiyatı',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green[800])),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('topluYemTuru'),
            value: _topluAlan,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Yem türü',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final t in kYemTurleri)
                DropdownMenuItem(
                  value: t['alan'] as String,
                  child: Row(children: [
                    Icon(t['ikon'] as IconData, color: t['renk'] as Color, size: 18),
                    const SizedBox(width: 8),
                    Text(t['ad'] as String),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _topluAlan = v ?? _topluAlan),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('topluYemFiyati'),
                  controller: _topluCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _tumuneUygula(),
                  decoration: InputDecoration(
                    labelText: 'Fiyat',
                    suffixText: '₺/kg',
                    isDense: true,
                    errorText: _topluHata,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _kaydediliyor ? null : _tumuneUygula,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                child: const Text('Tümüne\nUygula', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cariFiyatKarti(Cari cari) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      // ExpansionTile'ın dokunma efekti en yakın Material'a çizilir; renkli
      // Container onu gizliyordu (debug'da hata, cihazda efekt görünmüyordu).
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.person, color: Colors.green[700], size: 20),
            ),
            title: Text('${cari.ad} ${cari.soyad}',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(cari.hayvanTuru ?? '',
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: kYemTurleri.map((tur) {
              final alan = tur['alan'] as String;
              final ctrl = _controllers[cari.id!]![alan]!;
              final renk = tur['renk'] as Color;
              final ikon = tur['ikon'] as IconData;
              final ad = tur['ad'] as String;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: renk.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(ikon, color: renk, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(ad,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500))),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: ctrl,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0.00',
                          suffixText: '₺',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: renk.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: renk, width: 2),
                          ),
                          filled: true,
                          fillColor: renk.withOpacity(0.05),
                        ),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: renk),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
