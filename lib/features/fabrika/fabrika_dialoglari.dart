import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/fabrika_repository.dart';
import '../../models/fabrika_model.dart';
import '../../utils/app_theme.dart';
import '../../utils/sayi_format.dart';
import 'fabrika_hesap.dart';

/// Tank & Sevkiyat ekranının giriş pencereleri. Her pencere kaydı KENDİSİ yapar
/// (hata olursa pencere açık kalır, girilenler kaybolmaz) ve kaydedince `true` döner;
/// çağıran `veriDegisti()` ile ekranları yeniler.

final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
final _gunYazi = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');

String _hataMetni(Object e) => e is FabrikaKayitHatasi ? e.mesaj : 'Kaydedilemedi: $e';

DateTime _bugun() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Ortak: tarih seçme satırı (bugünden ileri seçilemez).
class _TarihSatiri extends StatelessWidget {
  final DateTime tarih;
  final ValueChanged<DateTime> secildi;
  final bool etkin;
  const _TarihSatiri({required this.tarih, required this.secildi, this.etkin = true});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: !etkin
            ? null
            : () async {
                final bugun = _bugun();
                final s = await showDatePicker(
                  context: context,
                  initialDate: tarih.isAfter(bugun) ? bugun : tarih,
                  firstDate: DateTime(2020),
                  lastDate: bugun,
                );
                if (s != null) secildi(s);
              },
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Tarih', prefixIcon: Icon(Icons.event_rounded), isDense: true),
          child: Text(_gunYazi.format(tarih), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

class _HataYazisi extends StatelessWidget {
  final String? hata;
  const _HataYazisi(this.hata);
  @override
  Widget build(BuildContext context) => hata == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(hata!, style: const TextStyle(color: AppRenkler.hata, fontWeight: FontWeight.w600)),
        );
}

TextField _sayiAlani(TextEditingController c, String etiket, {String? sonek, String? ipucu, bool otomatikOdak = false}) =>
    TextField(
      controller: c,
      autofocus: otomatikOdak,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: etiket, suffixText: sonek, hintText: ipucu, isDense: true),
    );

TextField _metinAlani(TextEditingController c, String etiket, {int satir = 1}) => TextField(
      controller: c,
      maxLines: satir,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: etiket, isDense: true),
    );

// ───────────────────────────── SEVKİYAT ─────────────────────────────

Future<bool?> sevkiyatPenceresi(
  BuildContext context, {
  required FabrikaRepository repo,
  required List<Fabrika> fabrikalar,
  Sevkiyat? mevcut,
  DateTime? tarih,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SevkiyatPenceresi(repo: repo, fabrikalar: fabrikalar, mevcut: mevcut, tarih: tarih),
    );

class _SevkiyatPenceresi extends StatefulWidget {
  final FabrikaRepository repo;
  final List<Fabrika> fabrikalar;
  final Sevkiyat? mevcut;
  final DateTime? tarih;
  const _SevkiyatPenceresi({required this.repo, required this.fabrikalar, this.mevcut, this.tarih});

  @override
  State<_SevkiyatPenceresi> createState() => _SevkiyatPenceresiState();
}

class _SevkiyatPenceresiState extends State<_SevkiyatPenceresi> {
  late final _kg = TextEditingController(text: widget.mevcut == null ? '' : sayiGirdi(widget.mevcut!.kg));
  late final _fiyat = TextEditingController(
      text: widget.mevcut == null || widget.mevcut!.fiyatsiz ? '' : sayiGirdi(widget.mevcut!.birimFiyat));
  late final _fisNo = TextEditingController(text: widget.mevcut?.fisNo ?? '');
  late final _plaka = TextEditingController(text: widget.mevcut?.plaka ?? '');
  late final _aciklama = TextEditingController(text: widget.mevcut?.aciklama ?? '');
  late DateTime _tarih = widget.mevcut != null ? DateTime.parse(widget.mevcut!.tarih) : (widget.tarih ?? _bugun());
  late String? _saat = widget.mevcut?.saat;
  int? _fabrikaId;
  String? _hata;
  bool _kaydediliyor = false;

  /// Seçilebilir fabrikalar: aktifler + (düzenlemede) kaydın kendi fabrikası.
  late final List<Fabrika> _secenekler = [
    for (final f in widget.fabrikalar)
      if (f.aktif || f.id == widget.mevcut?.fabrikaId) f,
  ];

  @override
  void initState() {
    super.initState();
    _fabrikaId = widget.mevcut?.fabrikaId ?? (_secenekler.isNotEmpty ? _secenekler.first.id : null);
    if (widget.mevcut == null && _fabrikaId != null) _sonFiyatiDoldur(_fabrikaId!);
    _kg.addListener(_yenile);
    _fiyat.addListener(_yenile);
  }

  void _yenile() => setState(() {});

  Future<void> _sonFiyatiDoldur(int fabrikaId) async {
    final f = await widget.repo.sonBirimFiyat(fabrikaId);
    if (!mounted || widget.mevcut != null) return;
    // Kullanıcı bu arada bir şey yazdıysa ezilmez.
    if (_fiyat.text.trim().isEmpty || _fiyatOtomatik) {
      _fiyat.text = f == null ? '' : sayiGirdi(f);
      _fiyatOtomatik = true;
    }
  }

  bool _fiyatOtomatik = false;

  @override
  void dispose() {
    for (final c in [_kg, _fiyat, _fisNo, _plaka, _aciklama]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    final kg = sayiCoz(_kg.text);
    final fiyat = sayiCoz(_fiyat.text);
    String? hata;
    if (_fabrikaId == null) {
      hata = 'Fabrika seçin.';
    } else if (kg == null) {
      hata = 'Sevk miktarı geçersiz: "${_kg.text}". Örnek: 1250 ya da 1250,5';
    } else if (kg <= 0) {
      hata = 'Sevk miktarını (kg) yazın.';
    } else if (fiyat == null) {
      hata = 'Birim fiyat geçersiz: "${_fiyat.text}". Örnek: 18,75';
    }
    if (hata != null) {
      setState(() => _hata = hata);
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final s = Sevkiyat(
        id: widget.mevcut?.id,
        fabrikaId: _fabrikaId!,
        tarih: gunAnahtari(_tarih),
        saat: _saat,
        kg: kg!,
        birimFiyat: fiyat!,
        fisNo: _fisNo.text,
        plaka: _plaka.text,
        aciklama: _aciklama.text,
      );
      if (widget.mevcut == null) {
        await widget.repo.sevkiyatEkle(s);
      } else {
        await widget.repo.sevkiyatGuncelle(s);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kg = sayiCoz(_kg.text);
    final fiyat = sayiCoz(_fiyat.text);
    final onizleme = (kg != null && kg > 0 && fiyat != null && fiyat > 0) ? kurusaYuvarla(kg * fiyat) : null;
    return AlertDialog(
      title: Text(widget.mevcut == null ? 'Fabrikaya Sevkiyat' : 'Sevkiyatı Düzenle'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<int>(
            initialValue: _fabrikaId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fabrika', prefixIcon: Icon(Icons.factory_outlined), isDense: true),
            items: [
              for (final f in _secenekler)
                DropdownMenuItem(value: f.id, child: Text(f.aktif ? f.ad : '${f.ad} (pasif)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _kaydediliyor
                ? null
                : (v) {
                    setState(() => _fabrikaId = v);
                    if (v != null && widget.mevcut == null) _sonFiyatiDoldur(v);
                  },
          ),
          const SizedBox(height: 10),
          _TarihSatiri(tarih: _tarih, etkin: !_kaydediliyor, secildi: (d) => setState(() => _tarih = d)),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(_saat == null ? 'Saat ekle (isteğe bağlı)' : 'Saat: $_saat'),
                onPressed: _kaydediliyor
                    ? null
                    : () async {
                        final p = _saat?.split(':');
                        final t = await showTimePicker(
                          context: context,
                          initialTime: p == null ? TimeOfDay.now() : TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
                        );
                        if (t != null) {
                          setState(() => _saat = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                        }
                      },
              ),
              if (_saat != null)
                IconButton(
                  tooltip: 'Saati kaldır',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: _kaydediliyor ? null : () => setState(() => _saat = null),
                ),
            ]),
          ),
          _sayiAlani(_kg, 'Sevk edilen (kg)', sonek: 'kg', otomatikOdak: widget.mevcut == null),
          const SizedBox(height: 10),
          TextField(
            controller: _fiyat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _fiyatOtomatik = false,
            decoration: const InputDecoration(
              labelText: 'Fabrika fiyatı (₺/kg)',
              suffixText: '₺/kg',
              helperText: 'Belli değilse boş bırakın, sonra "Fiyat uygula" ile girin.',
              helperMaxLines: 2,
              isDense: true,
            ),
          ),
          if (onizleme != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Tutar: ${_para.format(onizleme)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppRenkler.basari)),
            ),
          const SizedBox(height: 10),
          _metinAlani(_fisNo, 'Fiş / irsaliye no (isteğe bağlı)'),
          const SizedBox(height: 10),
          _metinAlani(_plaka, 'Araç plakası (isteğe bağlı)'),
          const SizedBox(height: 10),
          _metinAlani(_aciklama, 'Açıklama (isteğe bağlı)'),
          _HataYazisi(_hata),
        ]),
      ),
      actions: [
        TextButton(onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: _kaydediliyor ? null : _kaydet, child: Text(_kaydediliyor ? 'Kaydediliyor…' : 'Kaydet')),
      ],
    );
  }
}

// ───────────────────────── TAHSİLAT / KESİNTİ / EK ─────────────────────────

Future<bool?> hareketPenceresi(
  BuildContext context, {
  required FabrikaRepository repo,
  required Fabrika fabrika,
  FabrikaHareketi? mevcut,
  FabrikaHareketTuru tur = FabrikaHareketTuru.tahsilat,
}) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HareketPenceresi(repo: repo, fabrika: fabrika, mevcut: mevcut, tur: tur),
    );

class _HareketPenceresi extends StatefulWidget {
  final FabrikaRepository repo;
  final Fabrika fabrika;
  final FabrikaHareketi? mevcut;
  final FabrikaHareketTuru tur;
  const _HareketPenceresi({required this.repo, required this.fabrika, this.mevcut, required this.tur});

  @override
  State<_HareketPenceresi> createState() => _HareketPenceresiState();
}

class _HareketPenceresiState extends State<_HareketPenceresi> {
  late final _tutar = TextEditingController(text: widget.mevcut == null ? '' : sayiGirdi(widget.mevcut!.tutar));
  late final _aciklama = TextEditingController(text: widget.mevcut?.aciklama ?? '');
  late DateTime _tarih = widget.mevcut != null ? DateTime.parse(widget.mevcut!.tarih) : _bugun();
  late FabrikaHareketTuru _tur = widget.mevcut?.tur ?? widget.tur;
  String? _hata;
  bool _kaydediliyor = false;

  @override
  void dispose() {
    _tutar.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    final tutar = sayiCoz(_tutar.text);
    if (tutar == null || tutar <= 0) {
      setState(() => _hata = tutar == null ? 'Tutar geçersiz: "${_tutar.text}". Örnek: 125000 ya da 125.000,50' : 'Tutarı yazın.');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final h = FabrikaHareketi(
        id: widget.mevcut?.id,
        fabrikaId: widget.fabrika.id!,
        tarih: gunAnahtari(_tarih),
        tur: _tur,
        tutar: tutar,
        aciklama: _aciklama.text,
      );
      if (widget.mevcut == null) {
        await widget.repo.hareketEkle(h);
      } else {
        await widget.repo.hareketGuncelle(h);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.fabrika.ad, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RadioGroup<FabrikaHareketTuru>(
              groupValue: _tur,
              onChanged: (v) {
                if (!_kaydediliyor && v != null) setState(() => _tur = v);
              },
              child: Column(children: [
                for (final t in FabrikaHareketTuru.values)
                  RadioListTile<FabrikaHareketTuru>(
                    value: t,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.ad),
                    subtitle: Text(t.alacagiArtirir ? 'Fabrikanın borcu artar' : 'Fabrikanın borcu azalır'),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            _TarihSatiri(tarih: _tarih, etkin: !_kaydediliyor, secildi: (d) => setState(() => _tarih = d)),
            const SizedBox(height: 10),
            _sayiAlani(_tutar, 'Tutar', sonek: '₺', otomatikOdak: widget.mevcut == null),
            const SizedBox(height: 10),
            _metinAlani(_aciklama, 'Açıklama (ör. banka havalesi, kalite kesintisi)'),
            _HataYazisi(_hata),
          ]),
        ),
        actions: [
          TextButton(onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: _kaydediliyor ? null : _kaydet, child: Text(_kaydediliyor ? 'Kaydediliyor…' : 'Kaydet')),
        ],
      );
}

// ───────────────────────────── TANK SAYIMI ─────────────────────────────

Future<bool?> tankPenceresi(BuildContext context, {required FabrikaRepository repo, DateTime? tarih}) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TankPenceresi(repo: repo, tarih: tarih ?? _bugun()),
    );

class _TankPenceresi extends StatefulWidget {
  final FabrikaRepository repo;
  final DateTime tarih;
  const _TankPenceresi({required this.repo, required this.tarih});

  @override
  State<_TankPenceresi> createState() => _TankPenceresiState();
}

class _TankPenceresiState extends State<_TankPenceresi> {
  final _kg = TextEditingController();
  final _aciklama = TextEditingController();
  late DateTime _tarih = widget.tarih;
  bool _kayitVar = false;
  bool _yukleniyor = true;
  String? _hata;
  bool _kaydediliyor = false;

  @override
  void initState() {
    super.initState();
    _oku();
  }

  /// Seçili günün kayıtlı tank miktarını kutuya getirir.
  Future<void> _oku() async {
    setState(() => _yukleniyor = true);
    final t = gunAnahtari(_tarih);
    final s = await widget.repo.tankSayimi(t);
    if (!mounted || gunAnahtari(_tarih) != t) return;
    setState(() {
      _kayitVar = s != null;
      _kg.text = s == null ? '' : sayiGirdi(s.kalanKg);
      _aciklama.text = s?.aciklama ?? '';
      _yukleniyor = false;
    });
  }

  @override
  void dispose() {
    _kg.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _kaydet({bool sil = false}) async {
    if (_kaydediliyor || _yukleniyor) return;
    final kg = sil ? 0.0 : sayiCoz(_kg.text);
    if (kg == null) {
      setState(() => _hata = 'Miktar geçersiz: "${_kg.text}". Örnek: 850 ya da 850,5');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      await widget.repo.tankKaydet(gunAnahtari(_tarih), kg, aciklama: _aciklama.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Gün Sonu Tank'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Gün sonunda tankta kalan (ertesi gün sevk edilecek) süt. Tank boşaldıysa 0 yazın ya da boş bırakın.',
              style: TextStyle(fontSize: 13, color: AppRenkler.metinIkincil),
            ),
            const SizedBox(height: 10),
            _TarihSatiri(
              tarih: _tarih,
              etkin: !_kaydediliyor,
              secildi: (d) {
                setState(() => _tarih = d);
                _oku();
              },
            ),
            const SizedBox(height: 10),
            if (_yukleniyor)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else ...[
              _sayiAlani(_kg, 'Tankta kalan (kg)', sonek: 'kg', otomatikOdak: true),
              const SizedBox(height: 10),
              _metinAlani(_aciklama, 'Açıklama (isteğe bağlı)'),
            ],
            _HataYazisi(_hata),
          ]),
        ),
        actions: [
          if (_kayitVar)
            TextButton(
              onPressed: _kaydediliyor || _yukleniyor ? null : () => _kaydet(sil: true),
              style: TextButton.styleFrom(foregroundColor: AppRenkler.hata),
              child: const Text('Sil'),
            ),
          TextButton(onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: _kaydediliyor || _yukleniyor ? null : _kaydet, child: Text(_kaydediliyor ? 'Kaydediliyor…' : 'Kaydet')),
        ],
      );
}

// ───────────────────────────── FİYAT UYGULA ─────────────────────────────

/// Fabrikanın açıkladığı fiyatı bir ayın sevkiyatlarına uygular. Dönüş: değişen sayı (vazgeçilirse null).
Future<int?> fiyatUygulaPenceresi(
  BuildContext context, {
  required FabrikaRepository repo,
  required Fabrika fabrika,
  required String bas,
  required String son,
  required String ayAdi,
}) =>
    showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FiyatUygulaPenceresi(repo: repo, fabrika: fabrika, bas: bas, son: son, ayAdi: ayAdi),
    );

class _FiyatUygulaPenceresi extends StatefulWidget {
  final FabrikaRepository repo;
  final Fabrika fabrika;
  final String bas, son, ayAdi;
  const _FiyatUygulaPenceresi({required this.repo, required this.fabrika, required this.bas, required this.son, required this.ayAdi});

  @override
  State<_FiyatUygulaPenceresi> createState() => _FiyatUygulaPenceresiState();
}

class _FiyatUygulaPenceresiState extends State<_FiyatUygulaPenceresi> {
  final _fiyat = TextEditingController();
  bool _sadeceFiyatsiz = true;
  String? _hata;
  bool _kaydediliyor = false;

  @override
  void dispose() {
    _fiyat.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    final f = sayiCoz(_fiyat.text);
    if (f == null || f <= 0) {
      setState(() => _hata = f == null ? 'Fiyat geçersiz: "${_fiyat.text}". Örnek: 18,75' : 'Fiyatı yazın.');
      return;
    }
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final n = await widget.repo.fiyatUygula(
          fabrikaId: widget.fabrika.id!, start: widget.bas, end: widget.son, birimFiyat: f, sadeceFiyatsiz: _sadeceFiyatsiz);
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.ayAdi} fiyatı'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${widget.fabrika.ad} — ${widget.ayAdi} sevkiyatlarına uygulanacak fabrika fiyatı.',
                style: const TextStyle(fontSize: 13, color: AppRenkler.metinIkincil)),
            const SizedBox(height: 10),
            _sayiAlani(_fiyat, 'Birim fiyat (₺/kg)', sonek: '₺/kg', otomatikOdak: true),
            const SizedBox(height: 6),
            RadioGroup<bool>(
              groupValue: _sadeceFiyatsiz,
              onChanged: (v) {
                if (!_kaydediliyor && v != null) setState(() => _sadeceFiyatsiz = v);
              },
              child: const Column(children: [
                RadioListTile<bool>(
                  value: true,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Yalnız fiyatı girilmemiş sevkiyatlara'),
                ),
                RadioListTile<bool>(
                  value: false,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ayın TÜM sevkiyatlarına (eski fiyatın üzerine yazar)'),
                ),
              ]),
            ),
            _HataYazisi(_hata),
          ]),
        ),
        actions: [
          TextButton(onPressed: _kaydediliyor ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: _kaydediliyor ? null : _kaydet, child: Text(_kaydediliyor ? 'Uygulanıyor…' : 'Uygula')),
        ],
      );
}

// ───────────────────────────── FABRİKA ─────────────────────────────

Future<bool?> fabrikaPenceresi(BuildContext context, {required FabrikaRepository repo, Fabrika? mevcut}) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FabrikaPenceresi(repo: repo, mevcut: mevcut),
    );

class _FabrikaPenceresi extends StatefulWidget {
  final FabrikaRepository repo;
  final Fabrika? mevcut;
  const _FabrikaPenceresi({required this.repo, this.mevcut});

  @override
  State<_FabrikaPenceresi> createState() => _FabrikaPenceresiState();
}

class _FabrikaPenceresiState extends State<_FabrikaPenceresi> {
  late final _ad = TextEditingController(text: widget.mevcut?.ad ?? '');
  late final _telefon = TextEditingController(text: widget.mevcut?.telefon ?? '');
  late final _adres = TextEditingController(text: widget.mevcut?.adres ?? '');
  late final _not = TextEditingController(text: widget.mevcut?.notMetni ?? '');
  String? _hata;
  bool _kaydediliyor = false;

  @override
  void dispose() {
    for (final c in [_ad, _telefon, _adres, _not]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_kaydediliyor) return;
    setState(() {
      _kaydediliyor = true;
      _hata = null;
    });
    try {
      final f = Fabrika(
        id: widget.mevcut?.id,
        ad: _ad.text,
        telefon: _telefon.text,
        adres: _adres.text,
        notMetni: _not.text,
        aktif: widget.mevcut?.aktif ?? true,
      );
      if (widget.mevcut == null) {
        await widget.repo.fabrikaEkle(f);
      } else {
        await widget.repo.fabrikaGuncelle(f);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = _hataMetni(e));
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.mevcut == null ? 'Yeni Fabrika' : 'Fabrikayı Düzenle'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _ad,
              autofocus: widget.mevcut == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Fabrika adı', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telefon,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)', isDense: true),
            ),
            const SizedBox(height: 10),
            _metinAlani(_adres, 'Adres (isteğe bağlı)'),
            const SizedBox(height: 10),
            _metinAlani(_not, 'Not (isteğe bağlı)', satir: 2),
            _HataYazisi(_hata),
          ]),
        ),
        actions: [
          TextButton(onPressed: _kaydediliyor ? null : () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: _kaydediliyor ? null : _kaydet, child: Text(_kaydediliyor ? 'Kaydediliyor…' : 'Kaydet')),
        ],
      );
}

/// Silme onayı (evet → true).
Future<bool> silmeOnayi(BuildContext context, String baslik, String metin) async =>
    (await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(baslik),
        content: Text(metin),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppRenkler.hata),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    )) ==
    true;
