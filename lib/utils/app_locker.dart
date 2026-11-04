import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';

class AppLocker {
  static final AppLocker _instance = AppLocker._internal();
  factory AppLocker() => _instance;
  AppLocker._internal();

  // Sabit anahtarlar
  static const String _deviceKey = 'registered_device_id';
  static const String _passwordKey = 'app_password_hash';
  static const String _ownerKey = 'owner_name';
  static const String _isActivatedKey = 'app_activated';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const String _lockUntilKey = 'lock_until';
  static const String _lastAccessKey = 'last_access';
  static const String _securityQuestionKey = 'security_question';
  static const String _securityAnswerKey = 'security_answer_hash';
  static const String _autoLockKey = 'auto_lock_enabled';
  static const String _autoLockTimeKey = 'auto_lock_time';

  // Varsayılan master şifre
  static const String _defaultMasterPassword = "ibrahim8583791";

  // Güvenlik ayarları
  static const int _maxFailedAttempts = 5;
  static const int _lockDurationMinutes = 15;
  static const int _defaultAutoLockTime = 5; // Dakika

  // Eski sistem uyumluluğu için (kullanılan yerlerde)
  static final Map<String, String> _userPasswords = {
    'AHMET': 'ibrahim8583791',
    'MEHMET': 'HALIL_MEHMET_456', 
    'ALİ': 'HALIL_ALI_789',
    'VELİ': 'HALIL_VELI_101',
    'AYŞE': 'HALIL_AYSE_202',
    'FATMA': 'HALIL_FATMA_303',
    'HASAN': 'HALIL_HASAN_404',
    'HÜSEYİN': 'HALIL_HUSEYIN_505',
    'ZEYNEP': 'HALIL_ZEYNEP_606',
    'MUSTAFA': 'HALIL_MUSTAFA_707',
  };

  // Cihaz ID'sini al
  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id ?? "android_${DateTime.now().millisecondsSinceEpoch}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? "ios_${DateTime.now().millisecondsSinceEpoch}";
      }
      
      return "device_${DateTime.now().millisecondsSinceEpoch}";
    } catch (e) {
      return "error_device_${DateTime.now().millisecondsSinceEpoch}";
    }
  }

  // Hash hesapla
  String _calculateHash(String input, {String salt = ""}) {
    final saltBytes = utf8.encode(salt.isNotEmpty ? salt : _getDeviceSalt());
    final inputBytes = utf8.encode(input);
    final combinedBytes = [...saltBytes, ...inputBytes];
    
    // Çift hash uygula
    final firstHash = sha256.convert(combinedBytes);
    final secondHash = sha512.convert(utf8.encode(firstHash.toString()));
    
    return secondHash.toString();
  }

  // Cihaza özel salt oluştur
  String _getDeviceSalt() {
    return "HALIL_DEVICE_SALT_2024";
  }

  // Uygulama kilitli mi kontrol et
  Future<bool> isAppLocked() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = prefs.getInt(_lockUntilKey) ?? 0;
    
    if (lockUntil > DateTime.now().millisecondsSinceEpoch) {
      return true;
    }
    
    // Otomatik kilitleme kontrolü
    if (await isAutoLockEnabled()) {
      final lastAccess = prefs.getInt(_lastAccessKey) ?? 0;
      final autoLockTime = prefs.getInt(_autoLockTimeKey) ?? _defaultAutoLockTime;
      final lockTime = autoLockTime * 60 * 1000; // Dakikayı milisaniyeye çevir
      
      if (lastAccess > 0 && 
          DateTime.now().millisecondsSinceEpoch - lastAccess > lockTime) {
        return true;
      }
    }
    
    return false;
  }

  // Kalan kilitleme süresini getir
  Future<String> getLockTimeRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = prefs.getInt(_lockUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (lockUntil <= now) return "";
    
    final remainingSeconds = ((lockUntil - now) / 1000).ceil();
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  // Uygulama aktif mi kontrol et
  Future<bool> isAppActivated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isActivatedKey) ?? false;
  }

  // Cihaz kayıtlı mı kontrol et
  Future<bool> isDeviceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredDeviceId = prefs.getString(_deviceKey);
    
    if (registeredDeviceId == null) return false;
    
    final currentDeviceId = await _getDeviceId();
    final currentHash = _calculateHash(currentDeviceId);
    
    return registeredDeviceId == currentHash;
  }

  // Uygulamayı ilk defa etkinleştir
  Future<Map<String, dynamic>> activateApp(String password, String ownerName, 
      {String securityQuestion = "", String securityAnswer = ""}) async {
    try {
      // Master şifre kontrolü
      if (password != _defaultMasterPassword) {
        return {
          'success': false,
          'message': '❌ Geçersiz master şifre!',
          'locked': false
        };
      }

      // Cihaz hash'ini hesapla ve kaydet
      final prefs = await SharedPreferences.getInstance();
      final currentDeviceId = await _getDeviceId();
      final deviceHash = _calculateHash(currentDeviceId);
      
      await prefs.setString(_deviceKey, deviceHash);
      await prefs.setString(_ownerKey, ownerName);
      await prefs.setBool(_isActivatedKey, true);
      
      // Güvenlik sorusu ve cevabını kaydet
      if (securityQuestion.isNotEmpty && securityAnswer.isNotEmpty) {
        await prefs.setString(_securityQuestionKey, securityQuestion);
        await prefs.setString(_securityAnswerKey, _calculateHash(securityAnswer));
      }
      
      // Varsayılan otomatik kilitlemeyi etkinleştir
      await prefs.setBool(_autoLockKey, true);
      await prefs.setInt(_autoLockTimeKey, _defaultAutoLockTime);
      
      // Son erişim zamanını güncelle
      await _updateLastAccessTime();
      
      return {
        'success': true,
        'message': '✅ Uygulama başarıyla aktif edildi!',
        'locked': false
      };
      
    } catch (e) {
      return {
        'success': false,
        'message': '❌ Hata: ${e.toString()}',
        'locked': false
      };
    }
  }

  // Şifre doğrulama
  Future<Map<String, dynamic>> verifyPassword(String password) async {
    try {
      // Önce kilit kontrolü
      if (await isAppLocked()) {
        return {
          'success': false,
          'message': '⏳ Uygulama kilitli!',
          'locked': true,
          'remainingTime': await getLockTimeRemaining()
        };
      }

      final prefs = await SharedPreferences.getInstance();
      
      // Varsayılan şifreyi kontrol et
      if (password == _defaultMasterPassword) {
        await _resetFailedAttempts();
        await _updateLastAccessTime();
        return {
          'success': true,
          'message': '✅ Şifre doğru!',
          'locked': false
        };
      }
      
      // Kayıtlı hash'li şifreyi kontrol et
      final savedHash = prefs.getString(_passwordKey);
      if (savedHash != null) {
        final inputHash = _calculateHash(password);
        if (inputHash == savedHash) {
          await _resetFailedAttempts();
          await _updateLastAccessTime();
          return {
            'success': true,
            'message': '✅ Şifre doğru!',
            'locked': false
          };
        }
      }
      
      // Yanlış şifre - hata sayacını artır
      await _incrementFailedAttempts();
      final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
      final remainingAttempts = _maxFailedAttempts - failedAttempts;
      
      if (failedAttempts >= _maxFailedAttempts) {
        await _lockApp();
        return {
          'success': false,
          'message': '🔒 Çok fazla hatalı giriş! Uygulama kilitlendi.',
          'locked': true,
          'remainingTime': await getLockTimeRemaining()
        };
      }
      
      return {
        'success': false,
        'message': '❌ Yanlış şifre! Kalan deneme: $remainingAttempts',
        'locked': false,
        'remainingAttempts': remainingAttempts
      };
      
    } catch (e) {
      return {
        'success': false,
        'message': '❌ Doğrulama hatası: ${e.toString()}',
        'locked': false
      };
    }
  }

  // Şifre değiştir
  Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) async {
    try {
      final verification = await verifyPassword(oldPassword);
      
      if (!verification['success'] || verification['locked']) {
        return {
          'success': false,
          'message': verification['message'],
          'locked': verification['locked']
        };
      }
      
      if (newPassword.length < 6) {
        return {
          'success': false,
          'message': '❌ Şifre en az 6 karakter olmalıdır!',
          'locked': false
        };
      }
      
      final prefs = await SharedPreferences.getInstance();
      final newHash = _calculateHash(newPassword);
      
      await prefs.setString(_passwordKey, newHash);
      
      return {
        'success': true,
        'message': '✅ Şifre başarıyla değiştirildi!',
        'locked': false
      };
      
    } catch (e) {
      return {
        'success': false,
        'message': '❌ Hata: ${e.toString()}',
        'locked': false
      };
    }
  }

  // Güvenlik sorusu ile şifre sıfırlama
  Future<Map<String, dynamic>> resetPasswordWithSecurityQuestion(
      String answer, String newPassword) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAnswerHash = prefs.getString(_securityAnswerKey);
      
      if (savedAnswerHash == null) {
        return {
          'success': false,
          'message': '❌ Güvenlik sorusu ayarlanmamış!',
          'locked': false
        };
      }
      
      final answerHash = _calculateHash(answer);
      
      if (answerHash != savedAnswerHash) {
        return {
          'success': false,
          'message': '❌ Güvenlik sorusu cevabı yanlış!',
          'locked': false
        };
      }
      
      if (newPassword.length < 6) {
        return {
          'success': false,
          'message': '❌ Şifre en az 6 karakter olmalıdır!',
          'locked': false
        };
      }
      
      final newHash = _calculateHash(newPassword);
      await prefs.setString(_passwordKey, newHash);
      await _resetFailedAttempts();
      
      return {
        'success': true,
        'message': '✅ Şifre başarıyla sıfırlandı!',
        'locked': false
      };
      
    } catch (e) {
      return {
        'success': false,
        'message': '❌ Hata: ${e.toString()}',
        'locked': false
      };
    }
  }

  // Otomatik kilitleme ayarlarını değiştir
  Future<void> setAutoLock(bool enabled, {int minutes = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLockKey, enabled);
    if (enabled) {
      await prefs.setInt(_autoLockTimeKey, minutes);
    }
  }

  // Otomatik kilitleme aktif mi
  Future<bool> isAutoLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLockKey) ?? false;
  }

  // Otomatik kilitleme süresini getir
  Future<int> getAutoLockTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_autoLockTimeKey) ?? _defaultAutoLockTime;
  }

  // Hatalı giriş sayısını artır
  Future<void> _incrementFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_failedAttemptsKey) ?? 0;
    await prefs.setInt(_failedAttemptsKey, current + 1);
  }

  // Hatalı giriş sayısını sıfırla
  Future<void> _resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
  }

  // Uygulamayı kilitle
  Future<void> _lockApp() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = DateTime.now()
        .add(Duration(minutes: _lockDurationMinutes))
        .millisecondsSinceEpoch;
    await prefs.setInt(_lockUntilKey, lockUntil);
  }

  // Son erişim zamanını güncelle
  Future<void> _updateLastAccessTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastAccessKey, DateTime.now().millisecondsSinceEpoch);
  }

  // Manuel olarak kilidi aç
  Future<void> unlockApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lockUntilKey);
    await _resetFailedAttempts();
    await _updateLastAccessTime();
  }

  // Sahip bilgisini getir
  Future<String> getOwnerInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ownerKey) ?? "Kayıtlı Değil";
  }

  // Kullanılan şifreyi getir (eski sistem uyumluluğu için)
  Future<String> getUsedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    final usedPass = prefs.getString(_passwordKey);
    
    if (usedPass == null) return "Kullanılmamış";
    
    // Master şifre kontrolü
    if (_defaultMasterPassword == "ibrahim8583791") {
      return "MASTER (${_defaultMasterPassword.substring(0, 5)}...)";
    }
    
    return "Özel şifre (${usedPass.substring(0, 5)}...)";
  }

  // Eski sistem uyumluluğu için statik metodlar
  static Map<String, String> getUserPasswords() {
    return _userPasswords;
  }

  static void updatePassword(String username, String newPassword) {
    if (_userPasswords.containsKey(username)) {
      _userPasswords[username] = newPassword;
    }
  }

  // Güvenlik sorusunu getir
  Future<String> getSecurityQuestion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_securityQuestionKey) ?? "Güvenlik sorusu ayarlanmamış";
  }

  // Cihaz bilgilerini göster
  Future<Map<String, String>> getDeviceInfo() async {
    final deviceId = await _getDeviceId();
    final deviceHash = _calculateHash(deviceId);
    
    return {
      'device_id': deviceId.length > 30 ? deviceId.substring(0, 30) + "..." : deviceId,
      'device_hash': deviceHash.substring(0, 20),
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
  }

  // İstatistikleri getir
  Future<Map<String, dynamic>> getStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    final lastAccess = prefs.getInt(_lastAccessKey) ?? 0;
    final autoLockEnabled = prefs.getBool(_autoLockKey) ?? false;
    final autoLockTime = prefs.getInt(_autoLockTimeKey) ?? _defaultAutoLockTime;
    
    String lastAccessStr = "Hiç erişilmedi";
    if (lastAccess > 0) {
      final duration = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastAccess));
      if (duration.inMinutes < 1) {
        lastAccessStr = "Az önce";
      } else if (duration.inHours < 1) {
        lastAccessStr = "${duration.inMinutes} dakika önce";
      } else if (duration.inDays < 1) {
        lastAccessStr = "${duration.inHours} saat önce";
      } else {
        lastAccessStr = "${duration.inDays} gün önce";
      }
    }
    
    return {
      'failed_attempts': failedAttempts,
      'remaining_attempts': _maxFailedAttempts - failedAttempts,
      'last_access': lastAccessStr,
      'auto_lock': autoLockEnabled ? 'Aktif ($autoLockTime dakika)' : 'Pasif',
      'is_locked': await isAppLocked(),
      'lock_remaining': await getLockTimeRemaining(),
    };
  }

  // Uygulamayı tamamen sıfırla (sadece geliştirici için)
  Future<void> resetApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}