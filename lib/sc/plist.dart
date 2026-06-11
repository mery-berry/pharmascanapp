import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'plan.dart'; // PatientPlanPage

class PatientPrescriptionsPage extends StatefulWidget {
  const PatientPrescriptionsPage({super.key});

  @override
  State<PatientPrescriptionsPage> createState() =>
      _PatientPrescriptionsPageState();
}

class _PatientPrescriptionsPageState extends State<PatientPrescriptionsPage> {
  final user = FirebaseAuth.instance.currentUser;
  String? patientName;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPatientName();
  }

  Future<void> _loadPatientName() async {
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists) {
        setState(() {
          patientName = doc.data()?['fullname'];
          isLoading = false;
        });
        debugPrint("✅ Patient name loaded: $patientName");
      } else {
        debugPrint("⚠️ No user document found for UID: ${user!.uid}");
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error loading patient name: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🔹 Entered PatientPrescriptionsPage.build()");
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Veuillez vous connecter.")),
      );
    }

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (patientName == null) {
      return const Scaffold(
        body: Center(child: Text("Impossible de récupérer le nom du patient.")),
      );
    }
    
    debugPrint("👤 Logged in UID: ${user?.uid}");
    debugPrint("🎯 Using patientName: $patientName");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes Ordonnances'),
        backgroundColor: Colors.green,
      ),
      
      body: StreamBuilder<QuerySnapshot>(
        
        stream: FirebaseFirestore.instance
            .collection('prescriptions')
            .where('createdby', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .where('status', isEqualTo: 'Plan validé')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            debugPrint("📡 Prescriptions fetched: ${snapshot.data!.docs.length}");
            for (var doc in snapshot.data!.docs) {
              debugPrint("🧾 Doc ID: ${doc.id}, createdby: ${doc['createdby']}, status: ${doc['status']}");
            }
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          final prescriptions = snapshot.data?.docs ?? [];

          if (prescriptions.isEmpty) {
            return const Center(
              child: Text('Aucune ordonnance trouvée.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: prescriptions.length,
            itemBuilder: (context, index) {
              final doc = prescriptions[index];
              final data = doc.data() as Map<String, dynamic>;
              
              // Use prescription ID instead of patient name
              final displayName = doc.id;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.description, color: Colors.green),
                  title: Text("Ordonnance: $displayName"),
                  subtitle: Text("Statut: ${data['status'] ?? 'Inconnu'}"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MedicationsListPage(
                          prescriptionId: doc.id,
                          createdby: user!.uid, // UID of the patient
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class MedicationsListPage extends StatelessWidget {
  final String prescriptionId;
  final String createdby; // UID of patient

  const MedicationsListPage({
    required this.prescriptionId,
    required this.createdby,
  });

  @override
  Widget build(BuildContext context) {
    // Get the reference to the specific prescription doc for this patient
    final medsRef = FirebaseFirestore.instance
        .collection('prescriptions')
        .doc(prescriptionId) // doc directly
        .collection('medications');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Médicaments'),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: medsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }

          final meds = snapshot.data?.docs ?? [];

          if (meds.isEmpty) {
            return const Center(
              child: Text('Aucun médicament trouvé.'),
            );
          }

          // Debug: Print all medication data
          for (final med in meds) {
            debugPrint("💊 Medication data for ${med.id}: ${med.data()}");
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: meds.length,
            itemBuilder: (context, index) {
              final medDoc = meds[index];
              final data = medDoc.data() as Map<String, dynamic>? ?? {};

              // Debug individual medication
              debugPrint("🔍 Building medication item $index: $data");

              // Try multiple possible field names for medication name
              final String name = _getMedicationName(data);
              final duration = data['durationDays']?.toString() ?? 'Inconnue';
              final timeslots = (data['timeslots'] as List?)?.join(', ') ?? '—';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.medication, color: Colors.green),
                  title: Text(name),
                  subtitle: Text('Durée: $duration jours\nPrises: $timeslots'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PatientPlanPage(
                          prescriptionId: prescriptionId,
                          medicationId: medDoc.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helper method to get medication name from various possible field names
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

    // If no name found, check all fields to help debug
    debugPrint("❌ No medication name found. Available fields: ${data.keys}");
    
    // Return a default name with medication ID or other info
    if (data.isNotEmpty) {
      // Try to use the first non-empty string field as fallback
      for (final entry in data.entries) {
        if (entry.value is String && entry.value.toString().isNotEmpty) {
          return "${entry.key}: ${entry.value}";
        }
      }
    }

    return 'Médicament';
  }
}