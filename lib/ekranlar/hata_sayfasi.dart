import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HataSayfasi extends StatelessWidget {
  final String hataMesaji;
  const HataSayfasi({super.key, required this.hataMesaji});

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
              const Text(
                'Uygulama Başlatılamadı',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aşağıdaki hata mesajını geliştiriciye iletiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
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
                      onPressed: () {
                        // Uygulamayı yeniden başlat
                        SystemNavigator.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Kapat'),
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
