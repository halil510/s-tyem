import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/bt_cihaz_suzgeci.dart';
import '../../../models/terazi_cihaz_model.dart';
import '../providers/terazi_providers.dart';
import '../services/terazi_baglanti_durumu.dart';

/// Profesyonel terazi bağlantı yönetim ekranı.
///
/// Eski ekrana göre farkları:
/// - Ayrıntılı bağlantı durumu göstergesi (bağlanıyor / yeniden
///   bağlanıyor / hata) üstte sabit bir banner olarak gösterilir.
/// - "Kayıtlı Cihazlar" sekmesi: daha önce bağlanılmış tüm cihazları
///   listeler, birini "varsayılan" yapmaya ya da silmeye izin verir.
/// - Canlı ağırlık okuması, bağlıyken ekranın üstünde büyük puntoyla
///   gösterilir — teraziye bağlanırken anında doğrulama sağlar.
class TeraziBaglantiEkraniPro extends ConsumerStatefulWidget {
  const TeraziBaglantiEkraniPro({super.key});

  @override
  ConsumerState<TeraziBaglantiEkraniPro> createState() => _TeraziBaglantiEkraniProState();
}

class _TeraziBaglantiEkraniProState extends ConsumerState<TeraziBaglantiEkraniPro>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');

  List<BluetoothDevice> _bleCihazlar = [];
  List<Map<String, dynamic>> _classicCihazlar = [];

  /// Taramada etraftaki HER cihaz (telefon, saat, kulaklık…) çıkar; isimsizler varsayılan gizli,
  /// adı teraziye benzeyenler (HC-05, Scale, Terazi…) en üstte.
  bool _isimsizGoster = false;

  static BtCihaz _bleBt(BluetoothDevice d) =>
      BtCihaz(ad: d.platformName.isNotEmpty ? d.platformName : d.advName, adres: d.remoteId.str);
  static BtCihaz _klasikBt(Map<String, dynamic> d) =>
      BtCihaz(ad: d['name']?.toString() ?? '', adres: d['address']?.toString() ?? '', eslesmis: true);

  List<BluetoothDevice> get _bleSirali {
    final m = {for (final d in _bleCihazlar) d.remoteId.str: d};
    return [
      for (final c in BtCihazSuzgeci.sirala(_bleCihazlar.map(_bleBt), BtAranan.terazi, isimsizleriGoster: _isimsizGoster)) m[c.adres]!,
    ];
  }

  List<BtCihaz> get _klasikSirali =>
      BtCihazSuzgeci.sirala(_classicCihazlar.map(_klasikBt), BtAranan.terazi, isimsizleriGoster: _isimsizGoster);

  Widget? _isimsizSecenegi(Iterable<BtCihaz> cihazlar) {
    final n = BtCihazSuzgeci.isimsizSayisi(cihazlar);
    if (n == 0) return null;
    return SwitchListTile(
      key: const ValueKey('isimsizGoster'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: _isimsizGoster,
      title: Text('İsimsiz cihazları da göster ($n)'),
      subtitle: const Text('Terazi isimsiz görünüyorsa açın'),
      onChanged: (v) => setState(() => _isimsizGoster = v),
    );
  }
  bool _taraniyor = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final durumAsync = ref.watch(teraziDurumStreamProvider);
    final agirlikAsync = ref.watch(teraziAgirlikStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Terazi Bağlantısı', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Bluetooth LE'),
            Tab(text: 'Bluetooth'),
            Tab(text: 'Wi-Fi'),
            Tab(text: 'Kayıtlılar'),
          ],
        ),
      ),
      body: Column(
        children: [
          _DurumBanner(durumAsync: durumAsync, agirlikAsync: agirlikAsync),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _bleSekmesi(),
                _classicSekmesi(),
                _wifiSekmesi(),
                _kayitliCihazlarSekmesi(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── BLE ─────────────────────────────────────────────
  Widget _bleSekmesi() {
    return _SekmeIskeleti(
      taraBaslik: 'Bluetooth LE Cihazlarını Tara',
      taraniyor: _taraniyor,
      onTara: () async {
        setState(() => _taraniyor = true);
        try {
          final notifier = ref.read(teraziBaglantiNotifierProvider.notifier);
          final sonuc = await notifier.bleTara();
          setState(() => _bleCihazlar = sonuc);
        } catch (e) {
          _hataGoster(e);
        } finally {
          if (mounted) setState(() => _taraniyor = false);
        }
      },
      altSecenek: _isimsizSecenegi(_bleCihazlar.map(_bleBt)),
      cihazSayisi: _bleSirali.length,
      cihazBuilder: (i) {
        final d = _bleSirali[i];
        final bt = _bleBt(d);
        return _CihazSatiri(
          ad: bt.gorunenAd,
          oneri: BtCihazSuzgeci.benziyor(bt.ad, BtAranan.terazi),
          altBaslik: d.remoteId.str,
          onBagla: () async {
            try {
              await ref.read(teraziBaglantiNotifierProvider.notifier).bleyeBagla(d);
            } catch (e) {
              _hataGoster(e);
            }
          },
        );
      },
    );
  }

  // ── CLASSIC ─────────────────────────────────────────
  Widget _classicSekmesi() {
    return _SekmeIskeleti(
      taraBaslik: 'Eşlenmiş Cihazları Listele',
      taraniyor: _taraniyor,
      onTara: () async {
        setState(() => _taraniyor = true);
        try {
          final servis = await ref.read(teraziServiceProvider.future);
          final sonuc = await servis.classicEslenmisCihazlar();
          setState(() => _classicCihazlar = sonuc);
        } catch (e) {
          _hataGoster(e);
        } finally {
          if (mounted) setState(() => _taraniyor = false);
        }
      },
      altSecenek: _isimsizSecenegi(_classicCihazlar.map(_klasikBt)),
      cihazSayisi: _klasikSirali.length,
      cihazBuilder: (i) {
        final bt = _klasikSirali[i];
        final ad = bt.isimsiz ? bt.adres : bt.ad.trim();
        final adres = bt.adres;
        return _CihazSatiri(
          ad: bt.gorunenAd,
          oneri: BtCihazSuzgeci.benziyor(bt.ad, BtAranan.terazi),
          altBaslik: adres,
          onBagla: () async {
            try {
              await ref.read(teraziBaglantiNotifierProvider.notifier).classicBagla(adres, cihazAdi: ad);
            } catch (e) {
              _hataGoster(e);
            }
          },
        );
      },
    );
  }

  // ── WIFI ────────────────────────────────────────────
  Widget _wifiSekmesi() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Terazi IP Adresi', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _ipController,
            decoration: InputDecoration(
              hintText: '192.168.1.100',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Port', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () async {
                final ip = _ipController.text.trim();
                final port = int.tryParse(_portController.text.trim()) ?? 9100;
                if (ip.isEmpty) return;
                try {
                  await ref.read(teraziBaglantiNotifierProvider.notifier).wifiBagla(ip, port);
                } catch (e) {
                  _hataGoster(e);
                }
              },
              icon: const Icon(Icons.wifi),
              label: const Text('Wi-Fi ile Bağlan'),
            ),
          ),
        ],
      ),
    );
  }

  // ── KAYITLI CİHAZLAR ────────────────────────────────
  Widget _kayitliCihazlarSekmesi() {
    final kayitliAsync = ref.watch(kayitliTeraziCihazlariProvider);
    return kayitliAsync.when(
      data: (cihazlar) {
        if (cihazlar.isEmpty) {
          return const Center(child: Text('Henüz kayıtlı terazi yok'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: cihazlar.length,
          itemBuilder: (context, i) {
            final c = cihazlar[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.varsayilan ? AppColors.primary : AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    c.baglantiTuru == TeraziBaglantiTuru.wifi ? Icons.wifi : Icons.bluetooth,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.cihazAdi, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${c.baglantiTuru.gorunenAd} · ${c.cihazAdresi}',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (c.varsayilan)
                    const Icon(Icons.star_rounded, color: AppColors.accent, size: 20)
                  else
                    IconButton(
                      icon: const Icon(Icons.star_border_rounded, size: 20),
                      onPressed: () => ref
                          .read(teraziBaglantiNotifierProvider.notifier)
                          .varsayilanYap(c.id!),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                    onPressed: () => ref
                        .read(teraziBaglantiNotifierProvider.notifier)
                        .cihaziSil(c.id!),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Hata: $e')),
    );
  }

  void _hataGoster(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hata: $e'), backgroundColor: AppColors.danger),
    );
  }
}

class _DurumBanner extends StatelessWidget {
  final AsyncValue<TeraziBaglantiDurumu> durumAsync;
  final AsyncValue<String> agirlikAsync;
  const _DurumBanner({required this.durumAsync, required this.agirlikAsync});

  @override
  Widget build(BuildContext context) {
    final durum = durumAsync.valueOrNull ?? TeraziBaglantiDurumu.bagliDegil;
    final renk = switch (durum) {
      TeraziBaglantiDurumu.bagli => AppColors.success,
      TeraziBaglantiDurumu.hata => AppColors.danger,
      TeraziBaglantiDurumu.bagliDegil => AppColors.textSecondary,
      _ => AppColors.warning,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: renk.withOpacity(0.10),
      child: Row(
        children: [
          if (durum.mesgul)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(durum.aktifBaglanti ? Icons.check_circle : Icons.circle_outlined, color: renk, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(durum.gorunenMetin, style: TextStyle(color: renk, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          if (durum.aktifBaglanti)
            Text(
              '${agirlikAsync.valueOrNull ?? "0.00"} kg',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}

class _SekmeIskeleti extends StatelessWidget {
  final String taraBaslik;
  final bool taraniyor;
  final VoidCallback onTara;
  final int cihazSayisi;
  final Widget Function(int index) cihazBuilder;

  /// Tarama düğmesinin altında (ör. "İsimsiz cihazları da göster").
  final Widget? altSecenek;

  const _SekmeIskeleti({
    required this.taraBaslik,
    required this.taraniyor,
    required this.onTara,
    required this.cihazSayisi,
    required this.cihazBuilder,
    this.altSecenek,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: taraniyor ? null : onTara,
              icon: taraniyor
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(taraniyor ? 'Taranıyor...' : taraBaslik),
            ),
          ),
        ),
        if (altSecenek != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: altSecenek),
        Expanded(
          child: cihazSayisi == 0
              ? const Center(child: Text('Cihaz bulunamadı — taramayı deneyin'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cihazSayisi,
                  itemBuilder: (context, i) => cihazBuilder(i),
                ),
        ),
      ],
    );
  }
}

class _CihazSatiri extends StatelessWidget {
  final String ad;
  final String altBaslik;
  final VoidCallback onBagla;

  /// Adı teraziye benziyor (HC-05, Scale, Terazi…) → "terazi olabilir" etiketi.
  final bool oneri;

  const _CihazSatiri({required this.ad, required this.altBaslik, required this.onBagla, this.oneri = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.scale_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ad, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (oneri)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: const Text('terazi olabilir', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                  ),
                Text(altBaslik, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: onBagla,
            child: const Text('Bağlan'),
          ),
        ],
      ),
    );
  }
}
