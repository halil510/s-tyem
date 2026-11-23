import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/cari_model.dart';
import '../models/urun_model.dart';
import '../data/repositories/donem_kilidi.dart';
import '../data/repositories/urun_repository.dart';
import '../core/providers/repository_providers.dart';
import '../core/providers/veri_surumu_provider.dart';
import '../features/urunler/urunler_ekrani.dart';
import '../utils/sayi_format.dart';

/// ─────────────────────────────────────────────────────────────
/// YEM / ÜRÜN FİYATLARI — cari başına, AYLIK
/// ─────────────────────────────────────────────────────────────
/// Alanlar Menü → Ürünler'deki AKTİF ürünlerden oluşur. Boş bırakılan alan
/// önceki aydan devralınan fiyatı korur (0 yazılmaz). Fiyat ürünün birimi
/// başınadır (₺/kg, ₺/çuval…). Kayıt tek transaction'dır (bkz.
/// `UrunFiyatRepository.ayFiyatlariniKaydet`).
class YemFiyatEkrani extends ConsumerStatefulWidget {
  const YemFiyatEkrani({super.key});

  @override
  ConsumerState<YemFiyatEkrani> createState() => _YemFiyatEkraniState();
}

class _YemFiyatEkraniState extends ConsumerState<YemFiyatEkrani> {
  List<Cari> _cariler = [];
  List<Urun> _urunler = [];

  /// cariId → (urunId → ay başında geçerli fiyat).
  Map<int, Map<int, double>> _fiyatlar = {};
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  DateTime _seciliAy = DateTime.now();

  // _controllers[cariId][urunId]
  final Map<int, Map<int, TextEditingController>> _controllers = {};

  // "Tüm carilere aynı fiyat" kartı
  final _topluCtrl = TextEditingController();
  int? _topluUrun;
  String? _topluHata;

  static const _renkler = [
    Color(0xFF0D47A1), Color(0xFF4E342E), Color(0xFF6A1B9A), Color(0xFF283593), Color(0xFFE65100),
    Color(0xFFF9A825), Color(0xFF00695C), Color(0xFF2E7D32), Color(0xFFC62828), Color(0xFF00838F),
  ];
  Color _renk(int i) => _renkler[i % _renkler.length];

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  @override
  void dispose() {
    _controllerlariBirak();
    _topluCtrl.dispose();
    super.dispose();
  }

  void _controllerlariBirak() {
    for (final m in _controllers.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _controllers.clear();
  }

  String get _ayStr => DateFormat('yyyy-MM').format(_seciliAy);
  String get _ayGoster => DateFormat('MMMM yyyy', 'tr_TR').format(_seciliAy);

  double _mevcut(int cariId, int urunId) => _fiyatlar[cariId]?[urunId] ?? 0;

  Future<void> _verileriYukle() async {
    setState(() => _yukleniyor = true);
    final cariRepo = await ref.read(cariRepositoryProvider.future);
    final urunRepo = await ref.read(urunRepositoryProvider.future);
    final fiyatRepo = await ref.read(urunFiyatRepositoryProvider.future);
    final cariler = await cariRepo.getAll(sadeceAktif: true);
    final urunler = await urunRepo.getAll(sadeceAktif: true);
    final fiyatlar = await fiyatRepo.ayBasiFiyatlari(cariler.map((c) => c.id!).toList(), _ayStr);
    if (!mounted) return;

    _controllerlariBirak();
    for (final cari in cariler) {
      _controllers[cari.id!] = {
        for (final u in urunler)
          u.id!: TextEditingController(
            text: (fiyatlar[cari.id!]?[u.id!] ?? 0) > 0 ? fiyatlar[cari.id!]![u.id!]!.toStringAsFixed(2) : '',
          ),
      };
    }
    setState(() {
      _cariler = cariler;
      _urunler = urunler;
      _fiyatlar = fiyatlar;
      if (_topluUrun == null || !urunler.any((u) => u.id == _topluUrun)) {
        _topluUrun = urunler.isEmpty ? null : urunler.first.id;
      }
      _yukleniyor = false;
    });
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

  /// Alandan değeri okur; alan BOŞSA 0 DEĞİL, mevcut (önceki aydan devralınmış
  /// olabilecek) değeri döner. Aksi halde boş bırakılan bir ürün sessizce 0 ₺
  /// olarak kaydedilir ve önceki ayın gerçek fiyatının bulunmasını engellerdi.
  double _oku(int cariId, int urunId) {
    final text = _controllers[cariId]?[urunId]?.text ?? '';
    final mevcut = _mevcut(cariId, urunId);
    if (text.trim().isEmpty) return mevcut;
    // Ekranda 2 haneye yuvarlı gösterilen değer dokunulmadıysa gerçek değer korunur
    // (12,345 ₺ "12.35" görünür; kullanıcı değiştirmeden kaydedince fiyat değişmesin).
    if (mevcut > 0 && text.trim() == mevcut.toStringAsFixed(2)) return mevcut;
    return sayiCoz(text) ?? mevcut;
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    final hataliVar = _controllers.values.expand((alanlar) => alanlar.values).any((ctrl) => sayiCoz(ctrl.text) == null);
    if (hataliVar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Geçersiz fiyat var, lütfen girdiğiniz değerleri kontrol edin'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    setState(() => _kaydediliyor = true);
    try {
      final kaydedilecek = [
        for (final cari in _cariler)
          for (final u in _urunler) (cariId: cari.id!, urunId: u.id!, fiyat: _oku(cari.id!, u.id!)),
      ];
      final repo = await ref.read(urunFiyatRepositoryProvider.future);
      // Tek transaction: ya hepsi ya hiçbiri. Değişmeyen fiyat için satır yazılmaz.
      await repo.ayFiyatlariniKaydet(_ayStr, kaydedilecek);
      ref.veriDegisti();
      await _verileriYukle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Yem fiyatları kaydedildi'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        final mesaj = e is UrunHatasi || e is DonemKapaliHatasi ? e.toString() : 'Hata: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mesaj), backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _kaydediliyor = false);
  }

  Future<void> _urunlereGit() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UrunlerEkrani()));
    if (mounted) await _verileriYukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFF8),
      appBar: AppBar(
        title: const Text('Yem Fiyatları', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Ürünler (yem, gübre…)',
            icon: const Icon(Icons.category_outlined),
            onPressed: _kaydediliyor ? null : _urunlereGit,
          ),
          if (_kaydediliyor)
            const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton.icon(
              onPressed: _urunler.isEmpty ? null : _kaydet,
              icon: const Icon(Icons.save, color: Colors.white, size: 18),
              label: const Text('Kaydet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                          colors: [Color(0xFF2E7D32), Color(0xFF388E3C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.grass, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Yem Fiyatı Dönemi', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(_ayGoster, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ])),
                        const Icon(Icons.edit_calendar, color: Colors.white70),
                      ],
                    ),
                  ),
                ),

                // Bilgi notu
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green[100]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.green[700], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Her cariye farklı fiyat girebilirsiniz. Boş = önceki ay. Fiyat ürünün birimi başınadır.',
                              style: TextStyle(color: Colors.green[800], fontSize: 12))),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Expanded(
                  child: _urunler.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('Aktif ürün yok', style: TextStyle(color: Colors.grey[600])),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _urunlereGit,
                                icon: const Icon(Icons.add),
                                label: const Text('Ürün Ekle'),
                              ),
                            ]),
                          ),
                        )
                      : _cariler.isEmpty
                          ? Center(child: Text('Henüz cari yok', style: TextStyle(color: Colors.grey[500])))
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

  /// Seçilen ürünün fiyatını TÜM carilerin alanına yazar. KAYDETMEZ:
  /// kullanıcı listeyi görüp (gerekirse tek tek değiştirip) "Kaydet"e basar.
  void _tumuneUygula() {
    final fiyat = sayiCoz(_topluCtrl.text);
    final urunId = _topluUrun;
    if (urunId == null) return;
    if (fiyat == null || fiyat <= 0) {
      setState(() => _topluHata = 'Geçerli bir fiyat girin (ör. 12,50)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _topluHata = null;
      for (final alanlar in _controllers.values) {
        alanlar[urunId]?.text = fiyat.toStringAsFixed(2);
      }
    });
    final ad = _urunler.firstWhere((u) => u.id == urunId).ad;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_cariler.length} cariye $ad: ${fiyat.toStringAsFixed(2)} ₺ yazıldı. Kaydetmeyi unutmayın.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'KAYDET', onPressed: _kaydet),
    ));
  }

  Widget _topluFiyatKarti() {
    final secili = _urunler.where((u) => u.id == _topluUrun).firstOrNull;
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
          Text('Tüm carilere aynı yem fiyatı', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green[800])),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const ValueKey('topluYemTuru'),
            value: _topluUrun,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ürün', isDense: true, border: OutlineInputBorder()),
            items: [
              for (var i = 0; i < _urunler.length; i++)
                DropdownMenuItem(
                  value: _urunler[i].id,
                  child: Row(children: [
                    Icon(Icons.grass, color: _renk(i), size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_urunler[i].ad, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _topluUrun = v ?? _topluUrun),
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
                    suffixText: '₺/${secili?.birim ?? 'kg'}',
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
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
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.person, color: Colors.green[700], size: 20),
            ),
            title: Text('${cari.ad} ${cari.soyad}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(cari.hayvanTuru ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (var i = 0; i < _urunler.length; i++) _urunSatiri(cari, _urunler[i], _renk(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _urunSatiri(Cari cari, Urun u, Color renk) {
    final ctrl = _controllers[cari.id!]![u.id!]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.grass, color: renk, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${u.ad} (₺/${u.birim})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              key: ValueKey('yemFiyat_${cari.id}_${u.id}'),
              controller: ctrl,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0.00',
                suffixText: '₺',
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: renk.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: renk, width: 2),
                ),
                filled: true,
                fillColor: renk.withOpacity(0.05),
              ),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: renk),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
    );
  }
}
