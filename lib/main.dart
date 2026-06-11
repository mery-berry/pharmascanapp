import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'sc/firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'sc/login.dart';
import 'sc/gps.dart';
import 'sc/scan.dart';
import 'sc/suivi.dart';
import 'sc/notif.dart';
import 'sc/plist.dart';
import 'sc/plan.dart';
import 'sc/chat.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("📩 Background message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  tz.initializeTimeZones();

  // Background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notifications
  await _initNotifications();

  // ✅ Check for initial message (app launched via notification)
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();

  runApp(MyApp(initialMessage: initialMessage));
}

class MyApp extends StatelessWidget {
  final RemoteMessage? initialMessage;
  const MyApp({super.key, this.initialMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          if (snapshot.hasData) {
            final user = snapshot.data!;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final fullname = userSnapshot.data?.get('fullname') ?? "Utilisateur";

                // ✅ If launched from notification, navigate immediately
                if (initialMessage != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _handleInitialMessage(context, initialMessage!);
                  });
                }

                return HomeScreen(username: fullname);
              },
            );
          }

          return const LoginScreen();
        },
      ),
    );
  }

  void _handleInitialMessage(BuildContext context, RemoteMessage message) {
    final data = message.data;
    final type = data['type'] ?? '';
    final pharmacyId = data['pharmacyId'] ?? '';
    final prescriptionId = data['prescriptionId'] ?? '';
    final medicationId = data['medicationId'] ?? '';
    final orderId = data['orderId'] ?? '';

    print('🚀 Initial message navigation:');
    print('  Type: $type');
    print('  PharmacyId: $pharmacyId');
    print('  PrescriptionId: $prescriptionId');
    print('  OrderId: $orderId');

    if (type == 'message' && pharmacyId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatListPage()),
      );
    } else if (type == 'plan' && prescriptionId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PatientPlanPage(
            prescriptionId: prescriptionId,
            medicationId: medicationId,
          ),
        ),
      );
    } else if (type == 'suivi') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SuiviPage()));
    } else if (type == 'order_ready' && orderId.isNotEmpty) {
      // ✅ ADD THIS: Handle order_ready notifications
      Navigator.push(context, MaterialPageRoute(builder: (_) => SuiviPage()));
    } else {
      print('❌ No matching navigation for type: $type');
      // Stay on home screen
    }
  }
}

Future<void> _initNotifications() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission for iOS / Android 13+
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');

  // Get the FCM token and save it to Firestore
  String? token = await messaging.getToken();
  debugPrint('📲 FCM Token: $token');

  final user = FirebaseAuth.instance.currentUser;
  if (user != null && token != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }

  // Foreground listener
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("💬 Foreground message: ${message.notification?.title}");
    debugPrint("💬 Message data: ${message.data}");
  });

  // Notification tap (app opened from background)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint("🚀 Notification tapped: ${message.notification?.title}");
    debugPrint("🚀 Message data: ${message.data}");
  });
}

// REMOVE THE DUPLICATE MyAppp CLASS - KEEP ONLY THE ONE ABOVE

class HomeScreen extends StatefulWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cityName = 'Loading...';

  @override
  void initState() {
    super.initState();
    _getCity();
  }

  Future<void> _getCity() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _cityName = 'Location off');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _cityName = 'Permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _cityName = 'Permission denied forever');
        return;
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);

      setState(() {
        _cityName = placemarks.isNotEmpty
            ? placemarks.first.locality ?? 'Unknown'
            : 'Unknown';
      });
    } catch (_) {
      setState(() => _cityName = 'Error');
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color green = Color(0xFF00C853);

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: green,
              ),
              accountName: Text(widget.username),
              accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundImage: AssetImage('images/icons/user.png'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: green),
              title: const Text('Profile'),
              onTap: () {
                // Navigate to profile page
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_pharmacy, color: green),
              title: const Text('Pharmacies de garde'),
              onTap: () {
                // Navigate to pharmacies page
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: green),
              title: const Text('Paramètres'),
              onTap: () {
                // Navigate to settings page
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 40),
            decoration: const BoxDecoration(
              color: green,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(80),
                bottomRight: Radius.circular(80),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Builder(
                        builder: (context) => IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.5,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _cityName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const NotifPage()),
                                );
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.notifications_none,
                                      color: Colors.white, size: 28),
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(FirebaseAuth.instance.currentUser?.uid)
                                          .collection('notifications')
                                          .where('read', isEqualTo: false)
                                          .snapshots(),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData ||
                                            snapshot.data!.docs.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        int count = snapshot.data!.docs.length;
                                        return Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 18,
                                            minHeight: 18,
                                          ),
                                          child: Center(
                                            child: Text(
                                              count.toString(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  "Bienvenue ${widget.username} !",
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Que souhaitez-vous faire aujourd'hui ?",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              padding: const EdgeInsets.all(20),
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              children: [
                _buildMenuItem(Icons.camera_alt, "Scanner\nL'ordonnance", () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanPrescriptionPage()),
                  );
                }),
                _buildMenuItem(
                    Icons.location_on_outlined, "Pharmacies\nà proximité", () {
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const GpsPage()));
                }),
                _buildMenuItem(Icons.message_outlined, "Messages", () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    var userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser!.uid)
                        .get();
                    String pharmacyId = "default_pharmacy";
                    if (userDoc.exists && userDoc.data()!.containsKey('pharmacyId')) {
                      pharmacyId = userDoc['pharmacyId'];
                    }
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatListPage(),
                      ),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    print("Error fetching pharmacyId: $e");
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Erreur lors de la récupération de la pharmacie')),
                    );
                  }
                }),
                _buildMenuItem(
                    Icons.local_shipping_outlined, "Suivi de\ncommande", () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SuiviPage())
                  );
                }),
                _buildMenuItem(
                    Icons.calendar_today, "Planning des\nmédicaments", () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PatientPrescriptionsPage(),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: Colors.black),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}