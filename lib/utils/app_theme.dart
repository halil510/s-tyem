import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── RENK PALETİ ────────────────────────────────────────────────
// Sadece mavi tonu - aşırı yeşil yok
class AppRenkler {
  static const Color birincil      = Color(0xFF1565C0); // koyu mavi
  static const Color birincilAcik  = Color(0xFF1976D2);
  static const Color birincilCok   = Color(0xFFE3F2FD); // çok açık mavi
  static const Color ikincil       = Color(0xFF0288D1); // açık mavi

  static const Color basari        = Color(0xFF2E7D32);
  static const Color uyari         = Color(0xFFE65100);
  static const Color hata          = Color(0xFFC62828);
  static const Color bilgi         = Color(0xFF0277BD);

  static const Color arkaplan      = Color(0xFFF5F7FA);
  static const Color yuzey         = Color(0xFFFFFFFF);
  static const Color yuzeyVar      = Color(0xFFF0F4F8);
  static const Color sinir         = Color(0xFFE0E6ED);
  static const Color sinirAcik     = Color(0xFFF0F4F8);

  static const Color metinAna      = Color(0xFF1A202C);
  static const Color metinIkincil  = Color(0xFF4A5568);
  static const Color metinUcuncul  = Color(0xFF718096);
  static const Color metinIpucu    = Color(0xFFA0AEC0);
}

// ─── TEMA ────────────────────────────────────────────────────────
ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: AppRenkler.birincil,
      secondary: AppRenkler.ikincil,
      surface: AppRenkler.yuzey,
      error: AppRenkler.hata,
    ),
    scaffoldBackgroundColor: AppRenkler.arkaplan,
    fontFamily: 'Poppins',

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppRenkler.yuzey,
      foregroundColor: AppRenkler.metinAna,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppRenkler.metinAna,
      ),
      iconTheme: IconThemeData(color: AppRenkler.metinIkincil),
    ),

    // Card
    cardTheme: CardThemeData(
      color: AppRenkler.yuzey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppRenkler.sinir, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ElevatedButton
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppRenkler.birincil,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // OutlinedButton
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppRenkler.birincil,
        side: const BorderSide(color: AppRenkler.birincil),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // TextField
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppRenkler.yuzeyVar,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppRenkler.sinir),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppRenkler.sinir),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppRenkler.birincil, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppRenkler.hata),
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: AppRenkler.metinIkincil,
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: AppRenkler.metinIpucu,
      ),
    ),

    // BottomNavigationBar
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppRenkler.yuzey,
      selectedItemColor: AppRenkler.birincil,
      unselectedItemColor: AppRenkler.metinUcuncul,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 11),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppRenkler.sinir,
      thickness: 1,
      space: 1,
    ),

    // SnackBar
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: const TextStyle(fontFamily: 'Poppins'),
    ),

    // Text
    textTheme: const TextTheme(
      titleLarge:  TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppRenkler.metinAna, fontSize: 17),
      titleMedium: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppRenkler.metinAna, fontSize: 15),
      titleSmall:  TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, color: AppRenkler.metinAna, fontSize: 13),
      bodyLarge:   TextStyle(fontFamily: 'Poppins', color: AppRenkler.metinAna,      fontSize: 14),
      bodyMedium:  TextStyle(fontFamily: 'Poppins', color: AppRenkler.metinIkincil,  fontSize: 13),
      bodySmall:   TextStyle(fontFamily: 'Poppins', color: AppRenkler.metinUcuncul,  fontSize: 12),
      labelLarge:  TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14),
    ),
  );
}
