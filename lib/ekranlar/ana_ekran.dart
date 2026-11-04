import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    _NavItem(label: 'Öde', icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, renk: Color(0xFFB71C1C)),
  ];

  @override
  Widget build(BuildContext context) {
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
            PopupMenuItem(value: 'hizli_sut', child: Row(children: [
              Icon(Icons.speed_rounded, color: Colors.blue[700], size: 18),
              const SizedBox(width: 10),
              const Text('Hızlı Süt Girişi'),
            ])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'sut_fiyat', child: Row(children: [
              Icon(Icons.water_drop, color: Colors.blue[700], size: 18),
              const SizedBox(width: 10),
              const Text('Süt Fiyatları'),
            ])),
            PopupMenuItem(value: 'yem_fiyat', child: Row(children: [
              Icon(Icons.grass, color: Colors.green[700], size: 18),
              const SizedBox(width: 10),
              const Text('Yem Fiyatları'),
            ])),
            PopupMenuItem(value: 'fiyat_gecmisi', child: Row(children: [
              Icon(Icons.trending_up_rounded, color: Colors.indigo[700], size: 18),
              const SizedBox(width: 10),
              const Text('Piyasa Fiyat Notları'),
            ])),
            PopupMenuItem(value: 'aylik_hesaplama', child: Row(children: [
              Icon(Icons.calculate_outlined, color: Colors.deepPurple[700], size: 18),
              const SizedBox(width: 10),
              const Text('Aylık Hesaplama & Rapor'),
            ])),
            PopupMenuItem(value: 'donem', child: Row(children: [
              Icon(Icons.lock_clock_outlined, color: Colors.brown[700], size: 18),
              const SizedBox(width: 10),
              const Text('Dönem Kapanışı & Hakediş'),
            ])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'terazi', child: Row(children: [
              Icon(Icons.scale_outlined, color: Colors.teal[700], size: 18),
              const SizedBox(width: 10),
              const Text('Terazi Bağlantısı'),
            ])),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'yedekleme', child: Row(children: [
              Icon(Icons.backup_outlined, color: Colors.grey[700], size: 18),
              const SizedBox(width: 10),
              const Text('Yedekleme'),
            ])),
          ],
          onSelected: (value) {
            if (value == 'hizli_sut') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HizliSutGiris()));
            } else if (value == 'sut_fiyat') Navigator.push(context, MaterialPageRoute(builder: (_) => const SutFiyatEkrani()));
            else if (value == 'yem_fiyat') Navigator.push(context, MaterialPageRoute(builder: (_) => const YemFiyatEkrani()));
            else if (value == 'fiyat_gecmisi') Navigator.push(context, MaterialPageRoute(builder: (_) => const FiyatYonetimEkrani()));
            else if (value == 'aylik_hesaplama') Navigator.push(context, MaterialPageRoute(builder: (_) => const FiyatHesaplamaEkrani()));
            else if (value == 'donem') Navigator.push(context, MaterialPageRoute(builder: (_) => const DonemEkrani()));
            else if (value == 'terazi') context.push(AppRoutes.terazi);
            else if (value == 'yedekleme') Navigator.push(context, MaterialPageRoute(builder: (_) => const YedeklemeEkrani()));
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, _navBarItem),
          ),
        ),
      ),
    );
  }

  Widget _navBarItem(int index) {
    final item = _navItems[index];
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: selected
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? item.renk.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.activeIcon : item.icon,
                color: selected ? item.renk : Colors.grey[500], size: 22),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(item.label, style: TextStyle(color: item.renk, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ],
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
