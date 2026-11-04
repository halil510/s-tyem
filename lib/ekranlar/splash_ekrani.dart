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
  String _hataBaslik = '';
  String _hataAciklama = '';
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
    } on VeritabaniGuncellemeHatasi catch (e) {
      _hataGoster(
        baslik: 'Veritabanı Güncellenemedi',
        aciklama: 'Verileriniz SİLİNMEDİ, olduğu gibi duruyor.\n'
            'Uygulamayı kapatıp tekrar açın. Sorun sürerse aşağıdaki '
            'mesajı kopyalayıp geliştiriciye iletin.',
        detay: '$e\n\n${e.yigin ?? ''}',
      );
      return;
    } on VeritabaniAcilisHatasi catch (e) {
      _hataGoster(
        baslik: 'Veritabanı Açılamadı',
        aciklama: 'Verilerinize dokunulmadı. Telefonda yer kalmamış olabilir '
            'ya da dosya başka bir işlem tarafından kullanılıyor olabilir. '
            '"Tekrar Dene"ye basın.',
        detay: '$e\n\n${e.yigin ?? ''}',
      );
      return;
    } catch (e, stack) {
      _hataGoster(
        baslik: 'Uygulama Başlatılamadı',
        aciklama: 'Aşağıdaki hata mesajını geliştiriciye iletiniz.',
        detay: 'Veritabanı hatası:\n$e\n\n$stack',
      );
      return;
    }

    final kurtarma = AppDatabase.instance.kurtarmaYedegi;
    if (kurtarma != null && mounted) {
      await _kurtarmaBildir(kurtarma);
      AppDatabase.instance.kurtarmaBildirildi();
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

  void _hataGoster({
    required String baslik,
    required String aciklama,
    required String detay,
  }) {
    if (!mounted) return;
    setState(() {
      _hataVar = true;
      _hataBaslik = baslik;
      _hataAciklama = aciklama;
      _hataMetni = detay;
    });
  }

  void _tekrarDene() {
    setState(() {
      _hataVar = false;
      _durum = 'Veritabanı hazırlanıyor...';
    });
    _baslat();
  }

  /// Bozuk veritabanı kenara alınıp yenisi kurulduysa kullanıcı mutlaka
  /// bilmeli: aksi halde verilerinin "kaybolduğunu" sanar.
  Future<void> _kurtarmaBildir(String eskiDosya) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: const Text('Veritabanı Bozuk Bulundu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Telefondaki veritabanı dosyası okunamadı. Eski dosya SİLİNMEDİ, '
                'kenara alındı ve uygulama boş bir veritabanıyla açılıyor.\n\n'
                'Verilerinizi geri getirmek için Menü → Yedekleme ekranından '
                'son yedeğinizi geri yükleyin.',
              ),
              const SizedBox(height: 12),
              const Text('Eski dosya:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(eskiDosya, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hataVar) {
      return HataSayfasi(
        baslik: _hataBaslik,
        aciklama: _hataAciklama,
        hataMesaji: _hataMetni,
        onTekrarDene: _tekrarDene,
      );
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
