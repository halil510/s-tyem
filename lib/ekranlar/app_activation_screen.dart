import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/app_locker.dart';
import '../core/router/app_router.dart';

class AppActivationScreen extends StatefulWidget {
  const AppActivationScreen({super.key});

  @override
  State<AppActivationScreen> createState() => _AppActivationScreenState();
}

class _AppActivationScreenState extends State<AppActivationScreen> {
  final AppLocker _appLocker = AppLocker();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  
  bool _isLoading = false;
  bool _showPassword = false;
  String _statusMessage = '';
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _checkAlreadyActivated();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _ownerController.dispose();
    super.dispose();
  }

  Future<void> _checkAlreadyActivated() async {
    final isActivated = await _appLocker.isAppActivated();
    final isRegistered = await _appLocker.isDeviceRegistered();
    
    if (isActivated && isRegistered) {
      _navigateToMain();
    }
  }

  Future<void> _activateApp() async {
    if (_passwordController.text.isEmpty || _ownerController.text.isEmpty) {
      _showMessage('Lütfen tüm alanları doldurun', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    final result = await _appLocker.activateApp(
      _passwordController.text.trim(),
      _ownerController.text.trim(),
    );
    
    setState(() => _isLoading = false);
    
    if (result['success'] == true) {
      _showMessage(result['message'].toString(), isError: false);
      
      await Future.delayed(const Duration(seconds: 2));
      _navigateToMain();
    } else {
      _showMessage(result['message'].toString(), isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    setState(() {
      _statusMessage = message;
      _isError = isError;
    });
    
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _statusMessage = '';
        });
      }
    });
  }

  void _navigateToMain() {
    context.go(AppRoutes.main);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                margin: const EdgeInsets.only(bottom: 30),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
              
              const Text(
                'UYGULAMA AKTİVASYONU',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 10),
              
              const Text(
                'Bu cihazı etkinleştirmek için size verilen aktivasyon şifresini girin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              
              const SizedBox(height: 30),
              
              
              TextField(
                controller: _ownerController,
                decoration: const InputDecoration(
                  labelText: 'Gerçek Adınız',
                  hintText: 'Örn: Ahmet Yılmaz',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                obscureText: !_showPassword,
                decoration: InputDecoration(
                  labelText: 'Aktivasyon Şifresi',
                  hintText: 'Halil İbrahim Kabatlı\'dan alın',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() => _showPassword = !_showPassword);
                    },
                  ),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Size verilen aktivasyon şifresini girin.',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Örnek: Ahmet → HALIL_AHMET_123',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              if (_statusMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _isError ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isError ? Colors.red : Colors.green,
                    ),
                  ),
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isError ? Colors.red : Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _activateApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle),
                            SizedBox(width: 10),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'UYGULAMAYI AKTİVE ET',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showMessage('Yardım için: 0555 555 55 55', isError: false);
                  },
                  icon: const Icon(Icons.phone),
                  label: const Text('Yardım İçin Ara'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Column(
                  children: [
                    Text(
                      'HALİL İBRAHİM KABATLI',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '- HALK MARKET TARAFINDAN YAPILMIŞTIR -',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
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