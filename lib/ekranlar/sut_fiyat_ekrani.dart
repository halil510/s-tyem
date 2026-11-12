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

class SutFiyatEkrani extends ConsumerStatefulWidget {
  const SutFiyatEkrani({super.key});

  @override
  ConsumerState<SutFiyatEkrani> createState() => _SutFiyatEkraniState();
}

class _SutFiyatEkraniState extends ConsumerState<SutFiyatEkrani> {
  late CariRepository _cariRepo;
  late CariFiyatRepository _fiyatRepo;
  List<Cari> _cariler = [];
  Map<int, CariFiyat> _fiyatlar = {};
  bool _yukleniyor = true;
  bool _kaydediliyor = false;

  /// Fiyatın GEÇERLİ OLACAĞI İLK GÜN. Varsayılan bugün: "süt bugünden
  /// itibaren 27 ₺" → önceki günler eski fiyatla kalır. Ayın 1'i seçilirse
  /// fiyat tüm aya uygulanır (eski aylık davranış).
  DateTime _seciliGun = DateUtils.dateOnly(DateTime.now());

  // Düzenleme için controller'lar
  final Map<int, TextEditingController> _controllers = {};
  final _topluCtrl = TextEditingController();
  String? _topluHata;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _topluCtrl.dispose();
    super.dispose();
  }

  /// `cari_fiyatlar.ay` anahtarı: ayın 1'i → 'yyyy-MM', diğer günler → 'yyyy-MM-dd'.
  String get _anahtar => CariFiyat.anahtar(_seciliGun);
  bool get _ayBasi => _seciliGun.day == 1;
  String get _gunGoster => DateFormat('d MMMM yyyy', 'tr_TR').format(_seciliGun);

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    _cariRepo = await ref.read(cariRepositoryProvider.future);
    _fiyatRepo = await ref.read(cariFiyatRepositoryProvider.future);
    _cariler = await _cariRepo.getAll(sadeceAktif: true);

    // Controller'ları temizle
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    // Her cari için seçilen günde geçerli fiyat (yoksa öncekinden devralınır)
    _fiyatlar = await _fiyatRepo.getAyFiyatlariHepsi(_cariler.map((c) => c.id!).toList(), _anahtar);

    // Controller'ları oluştur
    for (final cari in _cariler) {
      final f = _fiyatlar[cari.id!]!;
      _controllers[cari.id!] = TextEditingController(
        text: f.sutFiyat > 0 ? f.sutFiyat.toStringAsFixed(2) : '',
      );
    }

    if (!mounted) return;
    setState(() => _yukleniyor = false);
  }

  Future<void> _gunSec() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _seciliGun,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'Fiyat hangi günden itibaren geçerli?',
    );
    if (picked != null) await _gunuDegistir(picked);
  }

  Future<void> _gunuDegistir(DateTime gun) async {
    setState(() => _seciliGun = DateUtils.dateOnly(gun));
    await _verileriYukle();
  }

  Future<void> _kaydet() async {
    // Önce TÜM alanları doğrula; hatalı yazılmış bir fiyat varken hiçbir
    // şey kaydetme (eskiden hatalı alan sessizce atlanıyordu).
    final hatalilar = _cariler.where((c) => sayiCoz(_controllers[c.id!]!.text) == null).toList();
    if (hatalilar.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Geçersiz fiyat: ${hatalilar.map((c) => c.tamAd).join(', ')}'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final kaydedilecek = <CariFiyat>[];
      for (final cari in _cariler) {
        final ctrl = _controllers[cari.id!]!;
        // KRİTİK: Alan boşsa bu cari için HİÇBİR KAYIT YAZMA. Aksi
        // halde "boş bırakılan cariler önceki ayın fiyatını kullanır"
        // sözü tutulmaz — boş alan sessizce 0 ₺ olarak kaydedilir ve
        // bu 0, o aydan itibaren `getirSonGecerli` tarafından "bu ay
        // için tanımlı fiyat" sayılıp gerçek önceki-ay fiyatının
        // bulunmasını KALICI OLARAK engeller.
        if (ctrl.text.trim().isEmpty) continue;
        final fiyat = sayiCoz(ctrl.text)!;
        if (fiyat <= 0) continue;
        final mevcut = _fiyatlar[cari.id!]!;
        // Fiyatı DEĞİŞMEYEN cari için seçilen güne satır YAZILMAZ. (Eski koşul `mevcut.ay != _anahtar`
        // hiç doğru olmuyordu: getAyFiyatlariHepsi devralınan fiyatı da istenen anahtarla döndürür.
        // Sonuç: değişmeyen her cariye o günden itibaren "hayalet" satır yazılıyor, sonradan yapılan
        // ay başı fiyat değişikliği o günden sonraki sütlere uygulanmıyordu.)
        if (kurusaYuvarla(fiyat) == kurusaYuvarla(mevcut.sutFiyat)) continue;
        kaydedilecek.add(CariFiyat(
          cariId: cari.id!,
          ay: _anahtar,
          sutFiyat: fiyat,
          sutYemiFiyat: mevcut.sutYemiFiyat,
          besiYemiFiyat: mevcut.besiYemiFiyat,
          bBaslangicFiyat: mevcut.bBaslangicFiyat,
          bBuyutmeFiyat: mevcut.bBuyutmeFiyat,
          kuzuYemiFiyat: mevcut.kuzuYemiFiyat,
          tavukYemiFiyat: mevcut.tavukYemiFiyat,
        ));
      }
      // Tek transaction: ya hepsi ya hiçbiri.
      await _fiyatRepo.topluKaydet(kaydedilecek);
      ref.veriDegisti();
      await _verileriYukle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(kaydedilecek.isEmpty
              ? 'Değişen fiyat yok'
              : '${kaydedilecek.length} carinin süt fiyatı $_gunGoster tarihinden itibaren kaydedildi'),
          backgroundColor: Colors.blue[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _kaydediliyor = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text('Süt Fiyatları', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_kaydediliyor)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton.icon(
              onPressed: _kaydet,
              icon: const Icon(Icons.save, color: Colors.white, size: 18),
              label: const Text('Kaydet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          // Tek kaydırılabilir liste: üstteki gün seçici + bilgi + toplu fiyat da kayar
          // (küçük / yatay ekranda eskiden liste alanı kalmıyor, taşıyordu).
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                // Geçerlilik başlangıç günü seçici
                _gunSeciciWidget(),

                // Bilgi notu
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue[100]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _ayBasi
                              ? 'Fiyat ${DateFormat('MMMM', 'tr_TR').format(_seciliGun)} ayının tamamına uygulanır '
                                  '(ay içinde sonradan girilen fiyat değişiklikleri kendi gününden itibaren geçerli kalır).'
                              : 'Yeni fiyat $_gunGoster ve sonrasındaki sütlere uygulanır. '
                                  'Önceki günler eski fiyatla hesaplanır. Tüm ayı değiştirmek için ayın 1\'ini seçin.',
                          style: TextStyle(color: Colors.blue[800], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_cariler.isNotEmpty) _topluFiyatKarti(),

                // Cari listesi
                if (_cariler.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text('Henüz cari yok', style: TextStyle(color: Colors.grey[500]))),
                  )
                else ...[
                  const SizedBox(height: 4),
                  for (final c in _cariler)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _cariFiyatSatiri(c),
                    ),
                ],
              ],
            ),
    );
  }

  /// Tek fiyatı tüm carilerin alanına yazar. KAYDETMEZ: kullanıcı listeyi
  /// görüp (gerekirse tek tek değiştirip) "Kaydet"e basar.
  void _tumuneUygula() {
    final fiyat = sayiCoz(_topluCtrl.text);
    if (fiyat == null || fiyat <= 0) {
      setState(() => _topluHata = 'Geçerli bir fiyat girin (ör. 18,50)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _topluHata = null;
      for (final c in _controllers.values) {
        c.text = fiyat.toStringAsFixed(2);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_cariler.length} cariye ${fiyat.toStringAsFixed(2)} ₺ yazıldı. Kaydetmeyi unutmayın.'),
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
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('topluSutFiyati'),
              controller: _topluCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _tumuneUygula(),
              decoration: InputDecoration(
                labelText: 'Tüm carilere aynı fiyat',
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
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
            child: const Text('Tümüne\nUygula', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _gunSeciciWidget() {
    final bugun = DateUtils.dateOnly(DateTime.now());
    final ayBasi = DateTime(_seciliGun.year, _seciliGun.month, 1);
    return Column(
      children: [
        _gunKarti(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const ValueKey('fiyatBugunden'),
                label: const Text('Bugünden itibaren'),
                selected: _seciliGun == bugun,
                onSelected: (_) => _gunuDegistir(bugun),
              ),
              ChoiceChip(
                key: const ValueKey('fiyatAyBasindan'),
                label: Text('Ayın başından (1 ${DateFormat('MMMM', 'tr_TR').format(ayBasi)})'),
                selected: _ayBasi,
                onSelected: (_) => _gunuDegistir(ayBasi),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gunKarti() {
    return InkWell(
      onTap: _gunSec,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF1565C0).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.water_drop, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fiyat şu günden itibaren geçerli', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(_gunGoster, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.edit_calendar, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _cariFiyatSatiri(Cari cari) {
    final ctrl = _controllers[cari.id!]!;
    final oncekiFiyat = _fiyatlar[cari.id!]?.sutFiyat ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.person, color: Colors.blue[700], size: 20),
          ),
          const SizedBox(width: 12),
          // Ad
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${cari.ad} ${cari.soyad}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(cari.hayvanTuru ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Fiyat girişi
          SizedBox(
            width: 100,
            child: TextField(
              controller: ctrl,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: oncekiFiyat > 0 ? oncekiFiyat.toStringAsFixed(2) : '0.00',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                suffixText: '₺',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.blue[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
                ),
                filled: true,
                fillColor: Colors.blue[50],
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1565C0)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
    );
  }
}
