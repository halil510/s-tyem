import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HataSayfasi extends StatelessWidget {
  final String hataMesaji;
  final String baslik;
  final String aciklama;

  /// Verilirse "Kapat" yerine "Tekrar Dene" düğmesi gösterilir.
  final VoidCallback? onTekrarDene;

  const HataSayfasi({
    super.key,
    required this.hataMesaji,
    this.baslik = 'Uygulama Başlatılamadı',
    this.aciklama = 'Aşağıdaki hata mesajını geliştiriciye iletiniz.',
    this.onTekrarDene,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline, size: 56, color: Colors.red),
              ),
              const SizedBox(height: 24),
              Text(
                baslik,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                aciklama,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Hata detayı — scroll edilebilir
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      hataMesaji,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: hataMesaji));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Hata kopyalandı')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Kopyala'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTekrarDene ?? () => SystemNavigator.pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(onTekrarDene == null ? Icons.close : Icons.refresh, size: 16),
                      label: Text(onTekrarDene == null ? 'Kapat' : 'Tekrar Dene'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
