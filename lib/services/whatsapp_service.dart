import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

class WhatsAppService {
  static Future<bool> sendToWhatsApp(String phone, String message) async {
    try {
      debugPrint('📱 WhatsApp gönderimi başlıyor...');
      debugPrint('📞 Orijinal telefon: $phone');
      
      // Telefon numarasını temizle ve formatla
      String cleanPhone = telefonNormalize(phone);
      
      if (cleanPhone.isEmpty) {
        debugPrint('❌ Geçersiz telefon numarası: $phone');
        return false;
      }
      
      debugPrint('✅ Formatlanmış telefon: $cleanPhone');
      debugPrint('💬 Mesaj uzunluğu: ${message.length} karakter');
      
      // WhatsApp URL'i oluştur
      final encodedMessage = Uri.encodeComponent(message);
      final String whatsappUrl = 'https://wa.me/$cleanPhone?text=$encodedMessage';
      final Uri url = Uri.parse(whatsappUrl);
      
      debugPrint('🔗 WhatsApp URL: $whatsappUrl');
      
      // URL'i açmaya çalış
      if (await canLaunchUrl(url)) {
        debugPrint('🚀 WhatsApp URL açılıyor...');
        final bool success = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        
        if (success) {
          debugPrint('✅ WhatsApp başarıyla açıldı');
          return true;
        } else {
          debugPrint('❌ WhatsApp açılamadı');
          return false;
        }
      } else {
        debugPrint('❌ WhatsApp URL açılamıyor');
        
        // Alternatif 1: intent kullanarak açmayı dene
        try {
          final String intentUrl = 'intent://send?phone=$cleanPhone&text=$encodedMessage#Intent;scheme=smsto;package=com.whatsapp;action=android.intent.action.SENDTO;end';
          final Uri intentUri = Uri.parse(intentUrl);
          
          if (await canLaunchUrl(intentUri)) {
            return await launchUrl(intentUri);
          }
        } catch (e) {
          debugPrint('❌ Intent ile açma başarısız: $e');
        }
        
        return false;
      }
    } catch (e, st) {
      debugPrint('❌ WhatsApp gönderim hatası: $e');
      debugPrint('Stack trace: $st');
      return false;
    }
  }
  
  /// Türkiye cep numarasını WhatsApp biçimine (90 + 10 hane) çevirir;
  /// geçersizse boş metin döner. Tüm ekranlar bunu kullanır.
  static String telefonNormalize(String phone) {
    if (phone.isEmpty) return '';
    
    // 1. Tüm boşluk ve özel karakterleri kaldır
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
        
    // 2. Numara boş mu kontrol et
    if (cleaned.isEmpty) return '';
    
    // 3. Türkiye numaraları için formatlama
    // Kural: 90 + 10 hane = 12 hane
    if (cleaned.length >= 10 && cleaned.length <= 13) {
      // Senaryo 1: 05550020005 (11 hane) -> 905550020005
      if (cleaned.startsWith('0') && cleaned.length == 11) {
        cleaned = '90' + cleaned.substring(1);
      }
      // Senaryo 2: 5550020005 (10 hane) -> 905550020005
      else if (cleaned.length == 10) {
        cleaned = '90' + cleaned;
      }
      // Senaryo 3: 905550020005 (12 hane) -> zaten doğru
      else if (cleaned.startsWith('90') && cleaned.length == 12) {
        // Zaten doğru
      }
      // Senaryo 4: +905550020005 (+ ve 12 hane) -> 905550020005
      else if (phone.contains('+90') && cleaned.length == 12) {
        // + işareti temizlenmiş zaten
      }
      // Senaryo 5: 9055500200056 (13 hane) -> son 12 haneyi al
      else if (cleaned.length == 13) {
        cleaned = cleaned.substring(cleaned.length - 12);
      }
    }
        
    // 4. Son kontrol: 12 haneli mi ve 90 ile başlıyor mu?
    if (cleaned.length == 12 && cleaned.startsWith('90')) {
      return cleaned;
    }
        return '';
  }

  // Mesaj oluşturma fonksiyonları - AYNEN KALDI
  static String createSutRaporuMessage({
    required String cariAd,
    required double gunlukToplam,
    required double haftalikToplam,
    required double aylikToplam,
    required String tarih,
  }) {
    return '''
*Süt Raporu - $tarih*

Sayın $cariAd,

Süt bilgileriniz aşağıdaki gibidir:

📊 *Günlük Toplam:* ${gunlukToplam.toStringAsFixed(2)} kg
📊 *Haftalık Toplam:* ${haftalikToplam.toStringAsFixed(2)} kg  
📊 *Aylık Toplam:* ${aylikToplam.toStringAsFixed(2)} kg

Teşekkür ederiz.
*Süt Yem Takip Sistemi*''';
  }

  static String createYemRaporuMessage({
    required String cariAd,
    required double toplamYem,
    required String yemDetay,
    required String tarih,
  }) {
    return '''
*Yem Raporu - $tarih*

Sayın $cariAd,

Yem bilgileriniz aşağıdaki gibidir:

🌾 *Toplam Yem:* ${toplamYem.toStringAsFixed(2)} kg

${yemDetay.isEmpty ? 'Henüz yem kaydı bulunmuyor' : 'Yem Detayları:\n$yemDetay'}

Teşekkür ederiz.
*Süt Yem Takip Sistemi*''';
  }

  static String createOdemeBildirimiMessage({
    required String cariAd,
    required double tutar,
    required String donem,
  }) {
    return '''
*Ödeme Bildirimi*

Sayın $cariAd,

$donem dönemine ait ödemeniz bulunmaktadır:

💰 *Tutar:* ${tutar.toStringAsFixed(2)} ₺

Lütfen ödemenizi en kısa sürede gerçekleştiriniz.

Teşekkür ederiz.
*Süt Yem Takip Sistemi*''';
  }
  
  static String createHesapOzetiMessage({
    required String cariAd,
    required String ayAdi,
    required double sutKg,
    required double sutFiyat,
    required double sutTutar,
    required double yemKg,
    required double yemTutar,
    double odeme = 0,
    double tahsilat = 0,
    required double kalanBorc,
  }) {
    // Süt (alacak) ve yem (borç) TOPLANMAZ — birbirinden düşülür:
    // ay net = (süt + tahsilat) − (yem + ödeme).
    final buAyNet = (sutTutar + tahsilat) - (yemTutar + odeme);
    final kapaliMi = kalanBorc.abs() < 0.005;
    final alacakliMi = kalanBorc > 0;
    final durumSatiri = kapaliMi
        ? '✅ *Hesabınız kapalı, borç/alacak yok.*'
        : (alacakliMi
            ? '💰 *Alacaklısınız:* ${kalanBorc.abs().toStringAsFixed(2)} ₺ (tarafınıza ödenecek)'
            : '📌 *Borçlusunuz:* ${kalanBorc.abs().toStringAsFixed(2)} ₺ (sizden tahsil edilecek)');

    final satirlar = <String>[
      '🥛 *Süt (Alacak):* ${sutKg.toStringAsFixed(2)} kg × ${sutFiyat.toStringAsFixed(2)} ₺ = ${sutTutar.toStringAsFixed(2)} ₺',
      if (yemKg > 0 || yemTutar > 0)
        '🌾 *Yem (Borç):* ${yemKg.toStringAsFixed(2)} kg = ${yemTutar.toStringAsFixed(2)} ₺',
      if (odeme > 0) '💵 *Size Ödenen:* ${odeme.toStringAsFixed(2)} ₺',
      if (tahsilat > 0) '🧾 *Sizden Alınan:* ${tahsilat.toStringAsFixed(2)} ₺',
      '📊 *Bu Ay Net:* ${buAyNet.toStringAsFixed(2)} ₺',
    ];

    return '''
*Hesap Özeti - $ayAdi*

Sayın $cariAd,

$ayAdi dönemine ait hesap özetiniz aşağıdaki gibidir:

${satirlar.join('\n')}

$durumSatiri

Teşekkür ederiz.
*Süt Yem Takip Sistemi*''';
  }

  static String createOzelMesaj({
    required String cariAd,
    required String mesaj,
  }) {
    return '''
*Mesaj*

Sayın $cariAd,

$mesaj

Teşekkür ederiz.
*Süt Yem Takip Sistemi*''';
  }
}