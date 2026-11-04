import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/fiyat_model.dart';
import '../core/providers/repository_providers.dart';
import '../sabitler/renkler.dart';

/// Genel (cariye bağlı olmayan) süt alış / yem satış fiyat geçmişi.
///
/// Not: Bu, `sut_fiyat_ekrani.dart` / `yem_fiyat_ekrani.dart` içindeki
/// CARİ BAZLI fiyatlardan farklıdır — burası işletmenin kendi genel
/// alış/satış fiyat geçmişini (piyasa fiyatı) kayıt altına almak için.
///
/// Bu ekran daha önce kodda vardı ama `Fiyat` modeliyle uyumsuz, artık
/// var olmayan metodlar çağırıyordu (derlenemezdi) ve hiçbir yerden
/// çağrılmıyordu. Bu turda hem `FiyatRepository`ye taşınarak düzeltildi
/// hem de Ana Ekran menüsüne bağlandı.
class FiyatYonetimEkrani extends ConsumerStatefulWidget {
  const FiyatYonetimEkrani({super.key});
  @override
  ConsumerState<FiyatYonetimEkrani> createState() => _FiyatYonetimEkraniState();
}

class _FiyatYonetimEkraniState extends ConsumerState<FiyatYonetimEkrani>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Fiyat> _sutFiyatlari = [];
  List<Fiyat> _yemFiyatlari = [];
  bool _yukleniyor = true;
  double _guncelSut = 0;
  double _guncelYem = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _yukle();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final repo = await ref.read(fiyatRepositoryProvider.future);
      final sut = await repo.getByUrunTuru('sut');
      final yem = await repo.getByUrunTuru('yem');
      final guncelSutFiyat = await repo.getGuncel('sut');
      final guncelYemFiyat = await repo.getGuncel('yem');
      if (mounted) {
        setState(() {
          _sutFiyatlari = sut;
          _yemFiyatlari = yem;
          _guncelSut = guncelSutFiyat?.birimFiyat ?? 0;
          _guncelYem = guncelYemFiyat?.birimFiyat ?? 0;
          _yukleniyor = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _fiyatEkle(String tur) async {
    final fiyatCtrl = TextEditingController();
    final notCtrl   = TextEditingController();
    DateTime seciliTarih = DateTime.now();
    final renk = tur == 'sut' ? C.mavi : C.yesil;
    final ad   = tur == 'sut' ? 'Süt Alış' : 'Yem Satış';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(tur == 'sut' ? Icons.water_drop : Icons.grass, color: renk, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('$ad Fiyatı Ekle',
              style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 15))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: () async {
                final t = await showDatePicker(
                  context: ctx, initialDate: seciliTarih,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (t != null) setSt(() => seciliTarih = t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: renk.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: renk.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today, size: 16, color: renk),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Geçerlilik: ${DateFormat('dd MMMM yyyy', 'tr_TR').format(seciliTarih)}',
                    style: TextStyle(fontSize: 13, color: renk, fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500))),
                  Icon(Icons.edit, size: 14, color: renk.withOpacity(0.5)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: fiyatCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: renk,
                fontFamily: 'Poppins'),
              decoration: InputDecoration(
                labelText: 'Birim Fiyat (₺/kg)',
                hintText: (tur == 'sut' ? _guncelSut : _guncelYem).toStringAsFixed(2),
                suffixText: '₺',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notCtrl,
              decoration: const InputDecoration(
                labelText: 'Not (opsiyonel)',
                prefixIcon: Icon(Icons.note_alt_outlined),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: renk),
              onPressed: () async {
                final val = double.tryParse(fiyatCtrl.text.replaceAll(',', '.'));
                if (val == null || val <= 0) return;
                final repo = await ref.read(fiyatRepositoryProvider.future);
                await repo.insert(Fiyat(
                  urunTuru: tur,
                  birimFiyat: val,
                  tarih: DateFormat('yyyy-MM-dd').format(seciliTarih),
                  aciklama: notCtrl.text.trim().isEmpty ? null : notCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
                _yukle();
                if (mounted) _snack('$ad fiyatı eklendi ₺${val.toStringAsFixed(2)}/kg', renk);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sil(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: const Text('Bu fiyat kaydını silmek istiyor musunuz?',
          style: TextStyle(fontFamily: 'Poppins')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: C.kirmizi),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    final repo = await ref.read(fiyatRepositoryProvider.future);
    await repo.delete(id);
    _yukle();
    if (mounted) _snack('Fiyat silindi', C.kirmizi);
  }

  void _snack(String m, Color renk) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: renk, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final isSut = _tab.index == 0;
    return Scaffold(
      backgroundColor: C.arkaplan,
      appBar: AppBar(
        title: const Text('Piyasa Fiyat Notları'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tab,
              indicatorColor: C.mavi,
              labelColor: C.mavi,
              unselectedLabelColor: C.metinUc,
              labelStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.water_drop, size: 16), text: 'Süt Alış'),
                Tab(icon: Icon(Icons.grass, size: 16), text: 'Yem Satış'),
              ],
            ),
            Container(height: 1, color: C.sinir),
          ]),
        ),
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator(color: C.mavi))
          : Column(children: [
              const _HesabaEtkiYokBandi(),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _sayfa('sut', _sutFiyatlari, _guncelSut),
                    _sayfa('yem', _yemFiyatlari, _guncelYem),
                  ],
                ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _fiyatEkle(isSut ? 'sut' : 'yem'),
        backgroundColor: isSut ? C.mavi : C.yesil,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(isSut ? 'Süt Fiyatı Ekle' : 'Yem Fiyatı Ekle',
          style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _sayfa(String tur, List<Fiyat> liste, double guncel) {
    final renk = tur == 'sut' ? C.mavi : C.yesil;
    final ad   = tur == 'sut' ? 'Süt Alış' : 'Yem Satış';
    final ikon = tur == 'sut' ? Icons.water_drop : Icons.grass;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [renk, renk.withOpacity(0.75)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Güncel $ad Fiyatı',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85), fontFamily: 'Poppins')),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₺${guncel.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800,
                  color: Colors.white, fontFamily: 'Poppins')),
              Padding(
                padding: const EdgeInsets.only(bottom: 5, left: 4),
                child: Text('/kg',
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.75), fontFamily: 'Poppins')),
              ),
            ]),
          ])),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(ikon, color: Colors.white, size: 30),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      Row(children: [
        const Icon(Icons.history_rounded, size: 16, color: C.metinUc),
        const SizedBox(width: 6),
        const Text('Fiyat Geçmişi',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.metinIki, fontFamily: 'Poppins')),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text('${liste.length} kayıt',
            style: TextStyle(fontSize: 11, color: renk, fontFamily: 'Poppins')),
        ),
      ]),
      const SizedBox(height: 10),

      if (liste.isEmpty)
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: C.yuzey, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.sinir)),
          child: Column(children: [
            Icon(ikon, size: 40, color: C.sinir),
            const SizedBox(height: 8),
            const Text('Henüz fiyat kaydı yok',
              style: TextStyle(color: C.metinUc, fontFamily: 'Poppins')),
          ]),
        )
      else
        ...liste.asMap().entries.map((e) {
          final isGuncel = e.key == 0;
          final f = e.value;
          final tarih = DateTime.parse(f.tarih);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: C.yuzey,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGuncel ? renk.withOpacity(0.5) : C.sinir,
                width: isGuncel ? 1.5 : 1),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isGuncel ? renk.withOpacity(0.12) : C.yuzeyVar,
                  borderRadius: BorderRadius.circular(11)),
                child: Icon(ikon, color: isGuncel ? renk : C.metinUc, size: 20),
              ),
              title: Row(children: [
                Text('₺${f.birimFiyat.toStringAsFixed(2)}/kg',
                  style: TextStyle(fontWeight: FontWeight.w700,
                    color: isGuncel ? renk : C.metinAna,
                    fontFamily: 'Poppins', fontSize: 16)),
                if (isGuncel) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text('Güncel',
                      style: TextStyle(fontSize: 10, color: renk,
                        fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                  ),
                ],
              ]),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 2),
                Text('${DateFormat('dd MMMM yyyy', 'tr_TR').format(tarih)} tarihinden itibaren',
                  style: const TextStyle(fontSize: 11, color: C.metinUc, fontFamily: 'Poppins')),
                if (f.aciklama != null && f.aciklama!.isNotEmpty)
                  Text(f.aciklama!,
                    style: const TextStyle(fontSize: 11, color: C.metinIki, fontFamily: 'Poppins')),
              ]),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: C.kirmizi, size: 20),
                onPressed: () => _sil(f.id!),
              ),
            ),
          );
        }),
      const SizedBox(height: 80),
    ]);
  }
}

/// Bu ekrandaki fiyatlar hiçbir bakiye/ekstre/rapor hesabına girmez;
/// kullanıcı buraya girdiği fiyatın uygulandığını sanmasın.
class _HesabaEtkiYokBandi extends StatelessWidget {
  const _HesabaEtkiYokBandi();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Bu ekran yalnızca not amaçlıdır; buradaki fiyatlar hesaplara '
            'GİRMEZ. Carilerin süt/yem tutarları Menü → Süt Fiyatları ve '
            'Yem Fiyatları ekranlarındaki aylık fiyatlarla hesaplanır.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontFamily: 'Poppins'),
          ),
        ),
      ]),
    );
  }
}
