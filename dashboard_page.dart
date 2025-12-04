import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart' as mqtt_server;
import 'package:mqtt_client/mqtt_browser_client.dart' as mqtt_browser;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // Ancien:
   static const String brokerIp = "192.168.56.1";

  // Nouveau : IP de ton PC / broker MQTT sur le Wi-Fi ETUD-CH
 // static const String brokerIp = "172.16.29.163";

  static const int wsPort = 9001;   // garde si ton broker a un listener websockets 9001
  static const int tcpPort = 1883;  // port MQTT classique
  String temperature = "--";
  String humidity = "--";
  int currentPageIndex = 0;

  late mqtt.MqttClient client;
  bool mqttConnected = false;
  bool mqttConnecting = false;
  String mqttStatusText = "MQTT déconnecté";

  @override
  void initState() {
    super.initState();
    connectMQTT();
  }

  Future<void> connectMQTT() async {
    if (mqttConnecting) return;

    setState(() {
      mqttConnecting = true;
      mqttStatusText = "Connexion MQTT...";
    });

    try {
      final clientId = "flutter_client_${DateTime.now().millisecondsSinceEpoch}";

      if (kIsWeb) {
        final browserClient = mqtt_browser.MqttBrowserClient('ws://$brokerIp', clientId);
        browserClient.port = wsPort;
        client = browserClient;
      } else {
        client = mqtt_server.MqttServerClient(brokerIp, clientId);
        (client as mqtt_server.MqttServerClient).port = tcpPort;
      }

      client.logging(on: true);
      client.keepAlivePeriod = 60;
      client.autoReconnect = true;
      client.onConnected = onConnected;
      client.onDisconnected = onDisconnected;
      client.onAutoReconnect = () => debugPrint("🔄 Auto-reconnexion en cours...");

      final connMess = mqtt.MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(mqtt.MqttQos.atLeastOnce);

      client.connectionMessage = connMess;

      debugPrint("🔄 Connexion MQTT à $brokerIp:${kIsWeb ? wsPort : tcpPort}");
      await client.connect();

      if (client.connectionStatus?.state == mqtt.MqttConnectionState.connected) {
        client.subscribe('iot/temperature', mqtt.MqttQos.atLeastOnce);
        client.subscribe('iot/humidity', mqtt.MqttQos.atLeastOnce);
        debugPrint("✅ Souscription aux topics réussie");

        client.updates?.listen((messages) {
          final mqtt.MqttReceivedMessage recMess = messages[0];
          final mqtt.MqttPublishMessage msg = recMess.payload as mqtt.MqttPublishMessage;
          final payload = mqtt.MqttPublishPayload.bytesToStringAsString(msg.payload.message);

          if (!mounted) return;

          setState(() {
            if (recMess.topic == 'iot/temperature') {
              temperature = payload;
              debugPrint("🌡️ Température reçue: $payload°C");
            }
            if (recMess.topic == 'iot/humidity') {
              humidity = payload;
              debugPrint("💧 Humidité reçue: $payload%");
            }
          });
        });
      } else {
        throw Exception("Échec: ${client.connectionStatus?.returnCode}");
      }
    } catch (e) {
      debugPrint("❌ Erreur MQTT: $e");
      if (!mounted) return;
      setState(() {
        mqttConnected = false;
        mqttStatusText = "MQTT : Erreur de connexion";
      });
      try {
        client.disconnect();
      } catch (_) {}
    } finally {
      if (!mounted) return;
      setState(() => mqttConnecting = false);
    }
  }

  void onConnected() {
    debugPrint("✅ MQTT connecté avec succès!");
    if (!mounted) return;
    setState(() {
      mqttConnected = true;
      mqttStatusText = "MQTT : Connecté ✓";
    });
  }

  void onDisconnected() {
    debugPrint("⚠️ MQTT déconnecté");
    if (!mounted) return;
    setState(() {
      mqttConnected = false;
      mqttStatusText = "MQTT : Déconnecté";
    });
  }

  void logout() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord IoT'),
        backgroundColor: Colors.green,
        actions: [
          if (!mqttConnected)
            IconButton(
              tooltip: "Reconnecter MQTT",
              onPressed: mqttConnecting ? null : connectMQTT,
              icon: mqttConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _getPage(currentPageIndex),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          if (index == 3) {
            logout();
          } else {
            setState(() => currentPageIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historique'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alertes'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Déconnexion'),
        ],
      ),
    );
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return DashboardContent(
          temperature: temperature,
          humidity: humidity,
          mqttStatus: mqttStatusText,
          mqttConnected: mqttConnected,
          mqttConnecting: mqttConnecting,
          onReconnect: connectMQTT,
        );
      case 1:
        return const HistoriqueContent();
      case 2:
        return AlertesContent(
          temperature: temperature,
          humidity: humidity,
        );
      default:
        return DashboardContent(
          temperature: temperature,
          humidity: humidity,
          mqttStatus: mqttStatusText,
          mqttConnected: mqttConnected,
          mqttConnecting: mqttConnecting,
          onReconnect: connectMQTT,
        );
    }
  }

  @override
  void dispose() {
    try {
      client.disconnect();
    } catch (_) {}
    super.dispose();
  }
}

// ====================================
// DASHBOARD CONTENT (MQTT temps réel)
// ====================================
class DashboardContent extends StatelessWidget {
  final String temperature;
  final String humidity;
  final String mqttStatus;
  final bool mqttConnected;
  final bool mqttConnecting;
  final VoidCallback onReconnect;

  const DashboardContent({
    super.key,
    required this.temperature,
    required this.humidity,
    required this.mqttStatus,
    required this.mqttConnected,
    required this.mqttConnecting,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: mqttConnected
                    ? Colors.green.shade100
                    : mqttConnecting
                        ? Colors.orange.shade100
                        : Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    mqttConnected
                        ? Icons.check_circle
                        : mqttConnecting
                            ? Icons.sync
                            : Icons.error,
                    color: mqttConnected
                        ? Colors.green
                        : mqttConnecting
                            ? Colors.orange
                            : Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    mqttStatus,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: mqttConnected
                          ? Colors.green.shade900
                          : mqttConnecting
                              ? Colors.orange.shade900
                              : Colors.red.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            _buildSensorCard(
              icon: Icons.thermostat,
              iconColor: Colors.orange,
              label: 'Température',
              value: temperature == "--" ? temperature : "$temperature °C",
              gradient: LinearGradient(
                colors: [Colors.orange.shade100, Colors.orange.shade50],
              ),
            ),
            const SizedBox(height: 20),

            _buildSensorCard(
              icon: Icons.water_drop,
              iconColor: Colors.blue,
              label: 'Humidité',
              value: humidity == "--" ? humidity : "$humidity %",
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.blue.shade50],
              ),
            ),

            if (!mqttConnected && !mqttConnecting) ...[
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: onReconnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnecter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required LinearGradient gradient,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Icon(icon, size: 56, color: iconColor),
              const SizedBox(height: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================
// HISTORIQUE CONTENT (API MySQL)
// ====================================
class HistoriqueContent extends StatefulWidget {
  const HistoriqueContent({super.key});

  @override
  State<HistoriqueContent> createState() => _HistoriqueContentState();
}

class _HistoriqueContentState extends State<HistoriqueContent> {
  List<dynamic> data = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('http://localhost/iot_backend/api/get_history.php'),
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          data = jsonData['data'] ?? [];
          loading = false;
        });
      } else {
        throw Exception('Erreur serveur: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadHistory,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Historique IoT',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: loadHistory,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualiser',
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 64),
                            const SizedBox(height: 16),
                            Text('Erreur: $error', textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: loadHistory,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      )
                    : data.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('Aucune donnée disponible'),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: data.length,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemBuilder: (context, index) {
                              final item = data[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.green.shade100,
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      const Icon(Icons.thermostat, color: Colors.orange, size: 20),
                                      Text(' ${item['temperature']}°C'),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.water_drop, color: Colors.blue, size: 20),
                                      Text(' ${item['humidity']}%'),
                                    ],
                                  ),
                                  subtitle: Text(item['created_at']),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ====================================
// ALERTES CONTENT (Alertes agricoles)
// ====================================
class AlertesContent extends StatelessWidget {
  final String temperature;
  final String humidity;

  const AlertesContent({
    super.key,
    required this.temperature,
    required this.humidity,
  });

  List<Map<String, dynamic>> _getAlertes() {
    List<Map<String, dynamic>> alertes = [];
    
    double? temp = double.tryParse(temperature);
    double? hum = double.tryParse(humidity);

    // Alertes TEMPÉRATURE (Agriculture)
    if (temp != null) {
      if (temp < 10) {
        alertes.add({
          'icon': Icons.ac_unit,
          'color': Colors.blue,
          'title': '🥶 TEMPÉRATURE TRÈS FROIDE',
          'message': 'Température: ${temp.toStringAsFixed(1)}°C - RISQUE DE GEL ! Protégez vos cultures immédiatement.',
          'severity': 'CRITIQUE',
        });
      } else if (temp >= 10 && temp <= 20) {
        alertes.add({
          'icon': Icons.thermostat,
          'color': Colors.lightBlue,
          'title': '❄️ Température Froide',
          'message': 'Température: ${temp.toStringAsFixed(1)}°C - Croissance ralentie. Surveillez vos plantes sensibles.',
          'severity': 'ATTENTION',
        });
      } else if (temp > 20 && temp <= 30) {
        alertes.add({
          'icon': Icons.check_circle,
          'color': Colors.green,
          'title': '✅ Température Optimale',
          'message': 'Température: ${temp.toStringAsFixed(1)}°C - Conditions idéales pour la croissance des cultures.',
          'severity': 'OK',
        });
      } else if (temp > 30 && temp <= 35) {
        alertes.add({
          'icon': Icons.wb_sunny,
          'color': Colors.orange,
          'title': '🌡️ Température Chaude',
          'message': 'Température: ${temp.toStringAsFixed(1)}°C - Augmentez la fréquence d\'arrosage.',
          'severity': 'ATTENTION',
        });
      } else if (temp > 35) {
        alertes.add({
          'icon': Icons.warning,
          'color': Colors.red,
          'title': '🔥 TEMPÉRATURE TRÈS CHAUDE',
          'message': 'Température: ${temp.toStringAsFixed(1)}°C - DANGER ! Stress thermique critique. Arrosage urgent + ombrage.',
          'severity': 'CRITIQUE',
        });
      }
    }

    // Alertes HUMIDITÉ (Agriculture)
    if (hum != null) {
      if (hum < 30) {
        alertes.add({
          'icon': Icons.water_drop_outlined,
          'color': Colors.brown,
          'title': '💧 Humidité Très Faible',
          'message': 'Humidité: ${hum.toStringAsFixed(1)}% - Sol très sec. Irrigation immédiate requise.',
          'severity': 'ATTENTION',
        });
      } else if (hum >= 30 && hum <= 80) {
        alertes.add({
          'icon': Icons.check_circle_outline,
          'color': Colors.green,
          'title': '✅ Humidité Normale',
          'message': 'Humidité: ${hum.toStringAsFixed(1)}% - Conditions d\'humidité favorables.',
          'severity': 'OK',
        });
      } else if (hum > 80) {
        alertes.add({
          'icon': Icons.water_damage,
          'color': Colors.blueGrey,
          'title': '💦 Humidité Très Élevée',
          'message': 'Humidité: ${hum.toStringAsFixed(1)}% - Risque élevé de maladies fongiques. Ventilation nécessaire.',
          'severity': 'ATTENTION',
        });
      }
    }

    return alertes;
  }

  @override
  Widget build(BuildContext context) {
    final alertes = _getAlertes();
    final alertesCritiques = alertes.where((a) => a['severity'] == 'CRITIQUE').toList();
    final alertesAttention = alertes.where((a) => a['severity'] == 'ATTENTION').toList();
    final alertesOk = alertes.where((a) => a['severity'] == 'OK').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🌾 Alertes Agricoles',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Surveillance en temps réel des conditions',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Résumé des alertes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryCard('Critiques', alertesCritiques.length, Colors.red),
              _buildSummaryCard('Attention', alertesAttention.length, Colors.orange),
              _buildSummaryCard('Normal', alertesOk.length, Colors.green),
            ],
          ),
          const SizedBox(height: 24),

          // Liste des alertes
          if (alertes.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    Icon(Icons.sensors_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Aucune donnée de capteur disponible'),
                  ],
                ),
              ),
            )
          else
            ...alertes.map((alerte) => _buildAlerteCard(alerte)).toList(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlerteCard(Map<String, dynamic> alerte) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: alerte['color'], width: 5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: alerte['color'].withOpacity(0.2),
            child: Icon(alerte['icon'], color: alerte['color'], size: 28),
          ),
          title: Text(
            alerte['title'],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              alerte['message'],
              style: const TextStyle(fontSize: 14),
            ),
          ),
          trailing: Chip(
            label: Text(
              alerte['severity'],
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: alerte['color'],
          ),
        ),
      ),
    );
  }
}
