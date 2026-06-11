import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'mes.dart';       // MessagesPage
import 'plist.dart';      // PatientPlanPage
import 'suivi.dart';     // SuiviPage

class NotifPage extends StatefulWidget {
  const NotifPage({super.key});

  @override
  State<NotifPage> createState() => _NotifPageState();
}

class _NotifPageState extends State<NotifPage> {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    if (user == null) return;

    // Request permissions (iOS / Android 13+)
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground messages: log only (Cloud Function saves to Firestore)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("📱 Foreground message: ${message.notification?.title}");
    });

    // Background / terminated: navigate using message.data
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("🚀 App opened from notification");
      if (message.data.isNotEmpty) _handleNavigation(message.data);
    });
  }

  // Navigate based on type & IDs in Firestore or FCM
  void _handleNavigation(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final pharmacyId = data['pharmacyId'] ?? '';
    final prescriptionId = data['prescriptionId'] ?? '';
    final medicationId = data['medicationId'] ?? '';
    final orderId = data['orderId'] ?? '';

    debugPrint('🔔 Notification data: $data'); // Debug print

    if (type == 'message' && pharmacyId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MessagesPage(pharmacyId: pharmacyId)),
      );
    } else if (type == 'plan') {
  debugPrint('🩺 Navigating to PatientPlanPage: prescriptionId=$prescriptionId, medicationId=$medicationId');

  if (prescriptionId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Notification plan invalide — prescriptionId manquant.")),
    );
    return;
  }

  try {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationsListPage(
          prescriptionId: prescriptionId,
          createdby: FirebaseAuth.instance.currentUser!.uid,
         // medicationId: medicationId,//
        ),
      ),
    );
  } catch (e, st) {
    debugPrint('🔥 Crash in PatientPlanPage: $e');
    debugPrint(st.toString());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Erreur lors de l’ouverture du plan.")),
    );
  }
}
 else if (type == 'suivi') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SuiviPage()));
    } else if (type == 'order_ready' && orderId.isNotEmpty) {
      // ✅ Navigate to SuiviPage when order is marked as ready
      Navigator.push(context, MaterialPageRoute(builder: (_) => SuiviPage()));
    } else {
      debugPrint('❌ Invalid notification: type=$type, data=$data'); // Debug print
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notification invalide ou incomplète.")),
      );
    }
  }

  Future<void> _markAsRead(DocumentSnapshot doc) async {
    await doc.reference.update({'read': true});
  }

  Future<void> _markAllAsRead() async {
    if (user == null) return;

    final unreadNotifications = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unreadNotifications.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked ${unreadNotifications.docs.length} as read')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            onPressed: _markAllAsRead,
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Aucune notification",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final notif = docs[index];
              final data = notif.data() as Map<String, dynamic>;
              final type = data['type'] ?? '';
              final pharmacyId = data['pharmacyId'] ?? '';
              final prescriptionId = data['prescriptionId'] ?? '';
              final medicationId = data['medicationId'] ?? '';
              final read = data['read'] ?? false;

              IconData icon;
              Color iconColor;
              switch (type) {
                case "message":
                  icon = Icons.message;
                  iconColor = Colors.blue;
                  break;
                case "plan":
                  icon = Icons.alarm;
                  iconColor = Colors.green;
                  break;
                case "suivi":
                  icon = Icons.local_shipping;
                  iconColor = Colors.orange;
                  break;
                default:
                  icon = Icons.notifications;
                  iconColor = Colors.grey;
              }

              return ListTile(
                leading: Icon(icon, color: iconColor),
                title: Text(
                  data['title'] ?? '',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: read ? Colors.grey : Colors.black),
                ),
                subtitle: Text(data['body'] ?? ''),
                tileColor: read ? null : Colors.blue.shade50,
                trailing: read
                    ? const Icon(Icons.check, color: Colors.green, size: 16)
                    : const Icon(Icons.circle, color: Colors.blue, size: 10),
                onTap: () async {
                  await _markAsRead(notif);
                  _handleNavigation({
                    'type': type,
                    'pharmacyId': pharmacyId,
                    'prescriptionId': prescriptionId,
                    'medicationId': medicationId,
                    'orderId': data['orderId'] ?? '',
                  });
                },
              );
            },
          );
        },
      ),
    );
  }
}