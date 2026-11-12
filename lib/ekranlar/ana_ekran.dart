import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/veri_surumu_provider.dart';
import 'dashboard_ekrani.dart';
import 'cari_listesi.dart';
import 'sut_ekrani.dart';
import 'yem_ekrani.dart';
import 'ode_ekrani.dart';
import 'sut_fiyat_ekrani.dart';
import 'yem_fiyat_ekrani.dart';
import 'fiyat_yonetim_ekrani.dart';
import 'fiyat_hesaplama_ekrani.dart';
import 'hizli_sut_giris.dart';
import '../ekranlar/yedekleme_ekrani.dart';
import '../core/router/app_router.dart';
import '../features/donem/donem_ekrani.dart';
import '../features/fis/fis_ekranlari.dart';
import '../features/cari/cari_excel_ekrani.dart';
import '../features/raporlar/rapor_ekrani.dart';
import '../senkron/otomatik_esitleyici.dart';
import '../senkron/senkron_ekrani.dart';
import 'cari/pasif_cariler_ekrani.dart';
import 'cari/toplama_sirasi_ekrani.dart';
import '../widgetlar/otomatik_yedekleyici.dart';

class AnaEkran extends StatefulWidget {
  const AnaEkran({super.key});

  @override
  State<AnaEkran> createState() => _AnaEkranState();
}

class _AnaEkranState extends State<AnaEkran> {
  int _selectedIndex = 0;

  static const List<Widget> _ekranlar = [
    DashboardEkrani(),
    CariListesi(),
    SutEkrani(),
    YemEkrani(),
    OdeEkrani(),
  ];

  static const List<String> _basliklar = ['Özet', 'Cariler', 'Süt Girişi', 'Yem Girişi', 'Ödemeler'];

  static const List<_NavItem> _navItems = [
    _NavItem(label: 'Özet', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, renk: Color(0xFF1B6B3A)),
    _NavItem(label: 'Cariler', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, renk: Color(0xFF1A237E)),
    _NavItem(label: 'Süt', icon: Icons.water_drop_outlined, activeIcon: Icons.water_drop, renk: Color(0xFF0D47A1)),
    _NavItem(label: 'Yem', icon: Icons.grass_outlined, activeIcon: Icons.grass, renk: Color(0xFF1B5E20)),
    _NavItem(label: 'Ödemeler', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, renk: Color(0xFFB71C1C)),
  ];

  @override
  Widget build(BuildContext context) {
    // Gün değişince (gece yarısı / sabah arka plandan dönüş) tüm sekmeleri
    // yenile: Özet'in "Bugün"ü, Cariler'in "bu ay" toplamı güncel kalsın.
    return Consumer(
      builder: (context, ref, child) {
        ref.listen<AsyncValue<DateTime>>(bugunProvider, (onceki, simdi) {
          final eski = onceki?.valueOrNull, yeni = simdi.valueOrNull;
          if (eski != null && yeni != null && eski != yeni) ref.veriDegisti();
        });
        return child!;
      },
      child: OtomatikYedekleyici(child: OtomatikEsitleyici(child: _sekmeler(context))),
    );
  }

  Widget _sekmeler(BuildContext context) {
    return PopScope(
      // Özet (Dashboard) sekmesindeyken geri tuşu normal davranır
      // (uygulamadan çıkar). Diğer sekmelerdeyken (Cariler, Süt, Yem,
      // Ödemeler) geri tuşu uygulamadan çıkmak yerine Özet sekmesine
      // döner — mobilde beklenen davranış budur.
      canPop: _selectedIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: _buildAppBar(),
        body: IndexedStack(index: _selectedIndex, children: _ekranlar),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(_basliklar[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      centerTitle: false,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1A237E),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.withOpacity(0.12)),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          itemBuilder: (ctx) => [
            _menuOgesi('hizli_sut', Icons.speed_rounded, Colors.blue[700], 'Hızlı Süt Girişi'),
            _menuOgesi('rota', Icons.route_outlined, Colors.blue[700], 'Toplama Sırası (Rota)'),
            _menuOgesi('pasif', Icons.person_off_outlined, Colors.blueGrey[600], 'Pasif Cariler'),
            _menuOgesi('excel_cari', Icons.upload_file_rounded, Colors.green[700], "Excel'den Cari İçeri Al"),
            const PopupMenuDivider(),
            _menuOgesi('sut_fiyat', Icons.water_drop, Colors.blue[700], 'Süt Fiyatları'),
            _menuOgesi('yem_fiyat', Icons.grass, Colors.green[700], 'Yem Fiyatları'),
            _menuOgesi('fiyat_gecmisi', Icons.trending_up_rounded, Colors.indigo[700], 'Piyasa Fiyat Notları'),
            _menuOgesi('raporlar', Icons.insights_rounded, Colors.indigo[700], 'Raporlar'),
            _menuOgesi('aylik_hesaplama', Icons.calculate_outlined, Colors.deepPurple[700], 'Aylık Hesaplama & Rapor'),
            _menuOgesi('donem', Icons.lock_clock_outlined, Colors.brown[700], 'Dönem Kapanışı & Hakediş'),
            const PopupMenuDivider(),
            _menuOgesi('terazi', Icons.scale_outlined, Colors.teal[700], 'Terazi Bağlantısı'),
            _menuOgesi('fis_yazici', Icons.print_outlined, Colors.teal[700], 'Fiş Yazıcısı'),
            _menuOgesi('senkron', Icons.cloud_sync_outlined, Colors.teal[700], 'Çoklu Cihaz ve Bulut'),
            const PopupMenuDivider(),
            _menuOgesi('yedekleme', Icons.backup_outlined, Colors.grey[700], 'Yedekleme'),
          ],
          onSelected: (value) {
            if (value == 'hizli_sut') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HizliSutGiris()));
            } else if (value == 'rota') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ToplamaSirasiEkrani()));
            } else if (value == 'pasif') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PasifCarilerEkrani()));
            } else if (value == 'excel_cari') {
              // İçe alınca veriDegisti → Cariler, Süt, Yem sekmeleri kendiliğinden yenilenir.
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CariExcelIceAktarmaEkrani()));
            } else if (value == 'sut_fiyat') Navigator.push(context, MaterialPageRoute(builder: (_) => const SutFiyatEkrani()));
            else if (value == 'yem_fiyat') Navigator.push(context, MaterialPageRoute(builder: (_) => const YemFiyatEkrani()));
            else if (value == 'fiyat_gecmisi') Navigator.push(context, MaterialPageRoute(builder: (_) => const FiyatYonetimEkrani()));
            else if (value == 'raporlar') Navigator.push(context, MaterialPageRoute(builder: (_) => const RaporAnaEkrani()));
            else if (value == 'aylik_hesaplama') Navigator.push(context, MaterialPageRoute(builder: (_) => const FiyatHesaplamaEkrani()));
            else if (value == 'donem') Navigator.push(context, MaterialPageRoute(builder: (_) => const DonemEkrani()));
            else if (value == 'terazi') context.push(AppRoutes.terazi);
            else if (value == 'fis_yazici') Navigator.push(context, MaterialPageRoute(builder: (_) => const FisYaziciAyarlariEkrani()));
            else if (value == 'senkron') Navigator.push(context, MaterialPageRoute(builder: (_) => const SenkronEkrani()));
            else if (value == 'yedekleme') Navigator.push(context, MaterialPageRoute(builder: (_) => const YedeklemeEkrani()));
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      key: const ValueKey('altPanel'),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [for (var i = 0; i < _navItems.length; i++) Expanded(child: _navBarItem(i))],
          ),
        ),
      ),
    );
  }

  /// Her sekmede ikon + yazı HER ZAMAN görünür (eskiden yazı yalnız seçili
  /// sekmede çıkıyordu); seçili sekme renk ve zemin ile belirginleşir.
  Widget _navBarItem(int index) {
    final item = _navItems[index];
    final selected = _selectedIndex == index;
    final renk = selected ? item.renk : Colors.grey[600]!;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedIndex = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? item.renk.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(selected ? item.activeIcon : item.icon, color: renk, size: 24),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: renk,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color renk;
  const _NavItem({required this.label, required this.icon, required this.activeIcon, required this.renk});
}

/// ⋮ menü öğesi: uzun yazı (ör. "Dönem Kapanışı & Hakediş") dar ekranda ya da
/// büyük yazı boyutunda taşmaz, kısalır.
PopupMenuItem<String> _menuOgesi(String deger, IconData ikon, Color? renk, String yazi) => PopupMenuItem(
      value: deger,
      child: Row(children: [
        Icon(ikon, color: renk, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(yazi, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
