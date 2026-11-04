import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/database/app_database.dart';
import '../core/router/app_router.dart';
import '../utils/app_locker.dart';
import 'hata_sayfasi.dart';

/// Açılış (splash) ekranı: önce veritabanını (migration'lar dahil) açar,
/// sonra aktivasyon/lisans kontrolü yapar. Bu iki adım kasıtlı olarak
/// ayrı try/catch bloklarında tutulur — böylece bir veritabanı hatası
/// ile bir aktivasyon hatası birbirine karışmaz ve kullanıcıya doğru
/// hata mesajı gösterilir.
class SplashVeGuvenlik extends StatefulWidget {
  const SplashVeGuvenlik({super.key});

  @override
  State<SplashVeGuvenlik> createState() => _SplashVeGuvenlikState();
}

class _SplashVeGuvenlikState extends State<SplashVeGuvenlik>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  String _durum = 'Veritabanı hazırlanıyor...';
  bool _hataVar = false;
  String _hataMetni = '';
  bool _animasyonBasladi = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _baslat();
  }

  Future<void> _baslat() async {
    // Adım 1: Animasyon
    await Future.delayed(const Duration(milliseconds: 300));
    _ctrl.forward();
    setState(() => _animasyonBasladi = true);

    // Adım 2: DB başlat (migration'lar dahil)
    try {
      setState(() => _durum = 'Veritabanı açılıyor...');
      await AppDatabase.instance.database;
      setState(() => _durum = 'Hazır');
    } catch (e, stack) {
      setState(() {
        _hataVar = true;
        _hataMetni = 'Veritabanı hatası:\n$e\n\n$stack';
      });
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));

    // Adım 3: Aktivasyon kontrolü
    try {
      setState(() => _durum = 'Güvenlik kontrolü...');
      final locker = AppLocker();
      final aktif = await locker.isAppActivated();
      if (!aktif) {
        if (mounted) context.go(AppRoutes.activate);
        return;
      }
      final kayitli = await locker.isDeviceRegistered();
      if (!kayitli) {
        if (mounted) context.go(AppRoutes.activate);
        return;
      }
    } catch (e) {
      // Aktivasyon hatası → aktivasyon ekranına yönlendir
      if (mounted) context.go(AppRoutes.activate);
      return;
    }

    // Adım 4: Ana ekrana geç
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) context.go(AppRoutes.main);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hataVar) {
      return HataSayfasi(hataMesaji: _hataMetni);
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1565C0).withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Image.asset('assets/images/sut_sisesi.png', fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Süt & Yem Takip',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1A237E), letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Text('Yönetim Sistemi', style: TextStyle(fontSize: 14, color: Colors.blue[600], letterSpacing: 1.2)),
              const SizedBox(height: 48),
              const SizedBox(
                width: 36, height: 36,
                child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF1565C0)),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _durum,
                  key: ValueKey(_durum),
                  style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                ),
              ),
              const SizedBox(height: 60),
              if (_animasyonBasladi)
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      Text(
                        'HALİL İBRAHİM KABATLI',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue[900], letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'HALK MARKET',
                        style: TextStyle(fontSize: 11, color: Colors.blue[700], letterSpacing: 2.0),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
