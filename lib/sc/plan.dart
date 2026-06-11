import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

class PatientPlanPage extends StatefulWidget {
  final String prescriptionId;
  final String medicationId;

  const PatientPlanPage({
    super.key,
    required this.prescriptionId,
    required this.medicationId,
  });

  @override
  State<PatientPlanPage> createState() => _PatientPlanPageState();
}

class _PatientPlanPageState extends State<PatientPlanPage> {
  final user = FirebaseAuth.instance.currentUser;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Map<String, Map<String, dynamic>> takenStatus = {};
  String medicationName = 'Chargement...';
  Map<String, dynamic> medicationData = {};
  Map<String, dynamic> planData = {};
  bool notificationsEnabled = true;
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 PatientPlanPage initialized with:');
    debugPrint('   prescriptionId: ${widget.prescriptionId}');
    if (widget.medicationId.isEmpty) {
      debugPrint("⚠️ medicationId is empty — loading all medications in this prescription.");
    }
    _initializePage();
  }

  Future<void> _initializePage() async {
    try {
      tz.initializeTimeZones();
      await _initNotifications();
      await _loadMedicationData();
      _listenPlan();
      _listenTaken();
      await _checkNotificationPermissions();
      
      setState(() {
        isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ Error initializing page: $e');
      debugPrint('📋 Stack trace: $stackTrace');
      
      setState(() {
        isLoading = false;
        errorMessage = 'Erreur lors du chargement: ${e.toString()}';
      });
    }
  }

  Future<void> _initNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await flutterLocalNotificationsPlugin.initialize(initSettings);
    } catch (e) {
      debugPrint('⚠️ Notification initialization error: $e');
    }
  }

  Future<void> _checkNotificationPermissions() async {
    try {
      final androidEnabled = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();

      final iosEnabled = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      setState(() {
        notificationsEnabled = androidEnabled ?? iosEnabled ?? true;
      });
    } catch (e) {
      debugPrint('⚠️ Permission check error: $e');
    }
  }

Future<void> _loadMedicationData() async {
  try {
    debugPrint('📥 Loading medication data...');

    // If no specific medication, just show all meds under this prescription
    if (widget.medicationId.isEmpty) {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('prescriptions')
          .doc(widget.prescriptionId)
          .collection('medications')
          .get();

      if (medsSnapshot.docs.isNotEmpty) {
        // Pick first medication just to display something
        medicationData = medsSnapshot.docs.first.data();
        medicationName = _getMedicationName(medicationData);
        debugPrint('💊 Loaded first medication as fallback: $medicationName');
      } else {
        medicationName = 'Aucun médicament trouvé';
      }

      setState(() {});
      return;
    }

    // Normal case: medicationId provided
    final medSnapshot = await FirebaseFirestore.instance
        .collection('prescriptions')
        .doc(widget.prescriptionId)
        .collection('medications')
        .doc(widget.medicationId)
        .get();

    if (medSnapshot.exists) {
      medicationData = medSnapshot.data() ?? {};
      debugPrint('💊 Medication data loaded: $medicationData');
      medicationName = _getMedicationName(medicationData);
      setState(() {});
    } else {
      debugPrint('❌ Medication document does not exist');
      setState(() {
        medicationName = 'Médicament non trouvé';
      });
    }
  } catch (e) {
    debugPrint('❌ Error loading medication data: $e');
    setState(() {
      medicationName = 'Erreur de chargement';
      errorMessage = 'Impossible de charger les données du médicament';
    });
  }
}


  String _getMedicationName(Map<String, dynamic> data) {
    // Try different possible field names
    final possibleFieldNames = [
      'medicationName',
      'name', 
      'medication',
      'drugName',
      'medicineName',
      'title'
    ];

    for (final fieldName in possibleFieldNames) {
      final value = data[fieldName];
      if (value != null && value.toString().isNotEmpty) {
        debugPrint("✅ Found medication name in field '$fieldName': $value");
        return value.toString();
      }
    }

    debugPrint("❌ No medication name found. Available fields: ${data.keys}");
    return 'Médicament';
  }

  void _listenPlan() {
      if (widget.medicationId.isEmpty) {
    debugPrint('⚠️ Skipping plan listener — no medicationId.');
    return;
  }
    try {
      debugPrint('👂 Listening to plan updates...');
      
      FirebaseFirestore.instance
          .collection('prescriptions')
          .doc(widget.prescriptionId)
          .collection('medications')
          .doc(widget.medicationId)
          .collection('plan')
          .doc('plan')
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) {
          debugPrint('📋 No plan document found');
          return;
        }
        
        final data = snapshot.data()!;
        debugPrint('📋 Plan data updated: $data');
        
        setState(() => planData = data);

        // Get timeslots from various possible field names
        final timeslots = _getTimeslots(data);
        final startDate = _getStartDate(data);
        final duration = _getDuration(data);

        debugPrint('⏰ Timeslots: $timeslots, Start: $startDate, Duration: $duration');

        if (timeslots.isNotEmpty && notificationsEnabled) {
          _scheduleNotifications(timeslots, startDate, duration);
        }
      }, onError: (error) {
        debugPrint('❌ Error listening to plan: $error');
        setState(() {
          errorMessage = 'Erreur de connexion au plan';
        });
      });
    } catch (e) {
      debugPrint('❌ Error setting up plan listener: $e');
    }
  }

  List<String> _getTimeslots(Map<String, dynamic> data) {
    // Try multiple possible field names for timeslots
    final possibleFieldNames = ['timeslots', 'slots', 'hours', 'takingTimes'];
    
    for (final fieldName in possibleFieldNames) {
      final value = data[fieldName];
      if (value is List) {
        return List<String>.from(value);
      }
    }
    
    return [];
  }

  DateTime _getStartDate(Map<String, dynamic> data) {
    // Try multiple possible field names for start date
    final possibleFieldNames = ['startDate', 'start', 'beginDate'];
    
    for (final fieldName in possibleFieldNames) {
      final value = data[fieldName];
      if (value is Timestamp) {
        return value.toDate();
      }
    }
    
    return DateTime.now();
  }

  int _getDuration(Map<String, dynamic> data) {
    // Try multiple possible field names for duration
    final possibleFieldNames = ['duration', 'durationDays', 'days', 'treatmentDuration'];
    
    for (final fieldName in possibleFieldNames) {
      final value = data[fieldName];
      if (value != null) {
        if (value is String) return int.tryParse(value) ?? 7;
        if (value is int) return value;
      }
    }
    
    return 7; // Default duration
  }

  void _listenTaken() {
      if (widget.medicationId.isEmpty) {
    debugPrint('⚠️ Skipping taken listener — no medicationId.');
    return;
  }
    try {
      debugPrint('👂 Listening to taken status...');
      
      FirebaseFirestore.instance
          .collection('prescriptions')
          .doc(widget.prescriptionId)
          .collection('medications')
          .doc(widget.medicationId)
          .collection('taken')
          .snapshots()
          .listen((snapshot) {
        Map<String, Map<String, dynamic>> status = {};
        for (var doc in snapshot.docs) {
          status[doc.id] = {
            'istaken': doc['istaken'] ?? false,
            'takenAt': doc['takenAt'],
          };
        }
        debugPrint('✅ Taken status updated: $status');
        setState(() => takenStatus = status);
      }, onError: (error) {
        debugPrint('❌ Error listening to taken status: $error');
      });
    } catch (e) {
      debugPrint('❌ Error setting up taken listener: $e');
    }
  }

  Future<void> _markTaken(String timeslot) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('prescriptions')
          .doc(widget.prescriptionId)
          .collection('medications')
          .doc(widget.medicationId)
          .collection('taken')
          .doc(timeslot);

      await ref.set({
        'istaken': true,
        'takenAt': Timestamp.now(),
      }, SetOptions(merge: true));

      debugPrint('✅ Marked $timeslot as taken');
    } catch (e) {
      debugPrint('❌ Error marking as taken: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur: ${e.toString()}")),
      );
    }
  }

  int _slotHour(String slot) {
    switch (slot.toLowerCase()) {
      case 'morning': return 8;
      case 'noon': return 12;
      case 'evening': return 18;
      case 'bedtime': return 22;
      default: return 8;
    }
  }

  String _slotToFrench(String slot) {
    switch (slot.toLowerCase()) {
      case 'morning': return 'matin';
      case 'noon': return 'midi';
      case 'evening': return 'soir';
      case 'bedtime': return 'coucher';
      default: return slot;
    }
  }

  Future<void> _scheduleNotifications(List<String> timeslots, DateTime startDate, int duration) async {
    try {
      final location = tz.local;
      await _cancelMedicationNotifications();

      for (int day = 0; day < duration; day++) {
        final date = startDate.add(Duration(days: day));

        for (String slot in timeslots) {
          final hour = _slotHour(slot);
          final tzScheduledTime = tz.TZDateTime(location, date.year, date.month, date.day, hour);

          if (tzScheduledTime.isAfter(tz.TZDateTime.now(location))) {
            await flutterLocalNotificationsPlugin.zonedSchedule(
              _generateNotificationId(slot, day),
              '💊 Rappel: $medicationName',
              'C\'est l\'heure de la prise du ${_slotToFrench(slot)}',
              tzScheduledTime,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'medication_reminders',
                  'Rappels de Médicaments',
                  channelDescription: 'Notifications pour la prise de médicaments',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
                iOS: DarwinNotificationDetails(
                  sound: 'default',
                  presentAlert: true,
                  presentBadge: true,
                  presentSound: true,
                ),
              ),
              androidAllowWhileIdle: true,
              uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
              payload: 'medication|${widget.medicationId}|$slot',
            );
          }
        }
      }
      
      debugPrint('✅ Notifications scheduled for $duration days');
    } catch (e) {
      debugPrint('❌ Error scheduling notifications: $e');
    }
  }

  int _generateNotificationId(String slot, int day) {
    return widget.medicationId.hashCode + slot.hashCode + (day * 1000);
  }

  Future<void> _cancelMedicationNotifications() async {
    try {
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      for (var notification in pending) {
        if (notification.payload?.contains(widget.medicationId) == true) {
          await flutterLocalNotificationsPlugin.cancel(notification.id);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error canceling notifications: $e');
    }
  }

  String _getTakenTime(String slot) {
    final info = takenStatus[slot];
    if (info != null && info['takenAt'] != null) {
      final ts = info['takenAt'] as Timestamp;
      final dt = ts.toDate();
      return 'à ${dt.hour}h${dt.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chargement...'),
          backgroundColor: Colors.green,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Erreur'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _initializePage,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Plan de prise - $medicationName'),
        backgroundColor: Colors.green,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Medication Info
          if (medicationData.isNotEmpty) ...[
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medicationName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (medicationData['goal'] != null) 
                      Text('Objectif: ${medicationData['goal']}'),
                    if (medicationData['mealRelation'] != null) 
                      Text('Prise: ${medicationData['mealRelation']}'),
                    if (planData.isNotEmpty && _getDuration(planData) > 0) 
                      Text('Durée: ${_getDuration(planData)} jours'),
                  ],
                ),
              ),
            ),
          ],

          // Timeslots
          Expanded(
            child: takenStatus.isEmpty 
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Aucune prise programmée',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Prises programmées:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      ...takenStatus.keys.map((slot) {
                        final taken = takenStatus[slot]?['istaken'] ?? false;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Icon(
                              taken ? Icons.check_circle : Icons.schedule,
                              color: taken ? Colors.green : Colors.orange,
                            ),
                            title: Text(
                              _slotToFrench(slot).toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold, 
                                color: taken ? Colors.green : Colors.black
                              ),
                            ),
                            subtitle: Text(
                              taken ? 'Pris ✅ ${_getTakenTime(slot)}' : 'À prendre à ${_slotHour(slot)}h',
                            ),
                            trailing: taken
                                ? null
                                : ElevatedButton(
                                    onPressed: () => _markTaken(slot),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                    child: const Text('Marquer comme pris'),
                                  ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}