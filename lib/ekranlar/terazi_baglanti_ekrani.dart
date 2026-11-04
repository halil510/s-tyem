// lib/ekranlar/terazi_baglanti_ekrani.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/terazi_service.dart';
import '../bluetooth/classic_bluetooth_service.dart';

class TeraziBaglantiEkrani extends StatefulWidget {
  const TeraziBaglantiEkrani({super.key});

  @override
  State<TeraziBaglantiEkrani> createState() => _TeraziBaglantiEkraniState();
}

class _TeraziBaglantiEkraniState extends State<TeraziBaglantiEkrani>
    with SingleTickerProviderStateMixin {

  final TeraziService _teraziService = TeraziService();

  // Classic servisi getter ile al
  ClassicBluetoothService get _classicService => _teraziService.classicService;

  List<BluetoothDevice> _bleCihazlar = [];
  List<Map<String, dynamic>> _classicCihazlar = [];
  bool _yukleniyor = false;
  String _aktifTab = 'ble'; // 'ble', 'classic', 'wifi'

  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: "9100");

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _bleCihazlariniTara();
  }

  void _handleTabSelection() {
    setState(() {
      _aktifTab = _getTabName(_tabController.index);
    });
    if (_tabController.index == 0) {
      _bleCihazlariniTara();
    } else if (_tabController.index == 1) {
      _classicCihazlariniTara();
    }
  }

  String _getTabName(int index) {
    switch (index) {
      case 0: return 'ble';
      case 1: return 'classic';
      case 2: return 'wifi';
      default: return 'ble';
    }
  }

  Future<void> _bleCihazlariniTara() async {
    setState(() => _yukleniyor = true);
    try {
      final List<BluetoothDevice> bulunanCihazlar = await _teraziService.scanBLEDevices();
      setState(() {
        _bleCihazlar = bulunanCihazlar;
        _yukleniyor = false;
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
      _hataGoster("BLE tarama hatası: $e");
    }
  }

  Future<void> _classicCihazlariniTara() async {
    setState(() => _yukleniyor = true);
    try {
      final List<Map<String, dynamic>> bulunanCihazlar = await _classicService.getPairedDevices();
      setState(() {
        _classicCihazlar = bulunanCihazlar;
        _yukleniyor = false;
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
      _hataGoster("Classic Bluetooth tarama hatası: $e");
    }
  }

  Future<void> _bleCihazinaBaglan(BluetoothDevice cihaz) async {
    try {
      setState(() => _yukleniyor = true);
      await _teraziService.connectToBLETerazi(cihaz);
      if (!mounted) return;
      Navigator.pop(context, {
        'durum': 'baglandi',
        'tip': 'ble',
        'cihazAdi': cihaz.platformName.isEmpty ? cihaz.remoteId.str : cihaz.platformName
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
      _hataGoster("BLE bağlantı hatası: $e");
    }
  }

  Future<void> _classicCihazinaBaglan(Map<String, dynamic> cihaz) async {
    try {
      setState(() => _yukleniyor = true);
      await _teraziService.connectToClassic(cihaz['address']).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      Navigator.pop(context, {
        'durum': 'baglandi',
        'tip': 'classic',
        'cihazAdi': cihaz['name'] ?? 'Classic Cihaz'
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
      _hataGoster("Classic Bluetooth bağlantı hatası: $e");
    }
  }

  Future<void> _wifiBaglantisiKur() async {
    if (_ipController.text.isEmpty || _portController.text.isEmpty) {
      _hataGoster("Lütfen IP adresi ve port bilgilerini giriniz");
      return;
    }
    try {
      setState(() => _yukleniyor = true);
      await _teraziService.connectWifi(_ipController.text, int.parse(_portController.text));
      if (!mounted) return;
      Navigator.pop(context, {
        'durum': 'baglandi',
        'tip': 'wifi',
        'cihazAdi': '${_ipController.text}:${_portController.text}'
      });
    } catch (e) {
      setState(() => _yukleniyor = false);
      _hataGoster("Wi-Fi bağlantı hatası: $e");
    }
  }

  void _hataGoster(String mesaj) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mesaj),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ------------------------
  // BLE durum metodu
  // ------------------------
  String _getConnectionStateText(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return 'Bağlı';
      case BluetoothConnectionState.connecting:
        return 'Bağlanıyor';
      case BluetoothConnectionState.disconnected:
        return 'Bağlı Değil';
      case BluetoothConnectionState.disconnecting:
        return 'Bağlantı Kesiliyor';
      default:
        return 'Bilinmeyen';
    }
  }

  // ------------------------
  // UI Bölümleri
  // ------------------------
  Widget _buildBLETab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          "Bluetooth Low Energy (BLE) terazileri otomatik olarak tarar",
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_bleCihazlar.isEmpty)
          _buildEmptyState(
            icon: Icons.bluetooth_disabled,
            title: "BLE Cihazı Bulunamadı",
            message: "Terazinizin BLE özelliği açık mı?\nYakınlarda başka BLE cihazları var mı?",
          ),
        for (var cihaz in _bleCihazlar)
          _buildCihazKarti(
            ad: cihaz.platformName.isEmpty ? "Bilinmeyen BLE Cihaz" : cihaz.platformName,
            detayWidget: StreamBuilder<BluetoothConnectionState>(
              stream: cihaz.connectionState,
              initialData: BluetoothConnectionState.disconnected,
              builder: (context, snapshot) {
                final state = snapshot.data!;
                return Text(
                  "ID: ${cihaz.remoteId} • ${_getConnectionStateText(state)}",
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
            icon: Icons.bluetooth,
            iconColor: Colors.blue,
            onTap: () => _bleCihazinaBaglan(cihaz),
            baglantiTipi: "BLE",
          ),
      ],
    );
  }

  Widget _buildClassicTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          "Eşleştirilmiş Classic Bluetooth terazileri",
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_classicCihazlar.isEmpty)
          _buildEmptyState(
            icon: Icons.bluetooth_connected,
            title: "Classic Cihaz Bulunamadı",
            message: "Teraziniz sistem Bluetooth ayarlarından eşleştirildi mi?\nCihazlar otomatik olarak listelenir",
          ),
        for (var cihaz in _classicCihazlar)
          _buildCihazKarti(
            ad: cihaz['name'] ?? 'Bilinmeyen Classic Cihaz',
            detayWidget: Text(
              "Adres: ${cihaz['address']}",
              style: const TextStyle(fontSize: 12),
            ),
            icon: Icons.bluetooth_connected,
            iconColor: Colors.green,
            onTap: () => _classicCihazinaBaglan(cihaz),
            baglantiTipi: "Classic",
          ),
      ],
    );
  }

  Widget _buildWifiTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        const Text(
          "Wi-Fi özellikli teraziler için ağ bağlantısı",
          style: TextStyle(color: Colors.grey, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: "IP Adresi",
                    hintText: "192.168.1.100",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.computer),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: "Port",
                    hintText: "9100",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _wifiBaglantisiKur,
                    icon: const Icon(Icons.wifi),
                    label: const Text("Wi-Fi Teraziye Bağlan"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String message}) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildCihazKarti({
    required String ad,
    Widget? detayWidget,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    required String baglantiTipi,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(ad, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: detayWidget,
        trailing: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: iconColor,
            foregroundColor: Colors.white,
          ),
          child: const Text("Bağlan"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Terazi Bağlantısı"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue[800],
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'BLE'),
            Tab(icon: Icon(Icons.bluetooth_connected), text: 'Classic'),
            Tab(icon: Icon(Icons.wifi), text: 'Wi-Fi'),
          ],
        ),
      ),
      body: _yukleniyor
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cihazlar taranıyor...'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(padding: const EdgeInsets.all(16), child: _buildBLETab()),
                SingleChildScrollView(padding: const EdgeInsets.all(16), child: _buildClassicTab()),
                SingleChildScrollView(padding: const EdgeInsets.all(16), child: _buildWifiTab()),
              ],
            ),
      floatingActionButton: _aktifTab != 'wifi'
          ? FloatingActionButton(
              onPressed: () {
                if (_aktifTab == 'ble') {
                  _bleCihazlariniTara();
                } else if (_aktifTab == 'classic') {
                  _classicCihazlariniTara();
                }
              },
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }
}
