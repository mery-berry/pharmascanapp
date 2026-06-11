import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SuiviPage extends StatelessWidget {
  const SuiviPage({super.key});

  Color _getStatusColor(String status) {
    switch (status) {
      case "Terminée":
        return Colors.blue;
      case "Plan validé":
        return Colors.green;
      case "En attente":
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "Terminée":
        return Icons.inventory_2; // ready
      case "Plan validé":
        return Icons.check_circle; // delivered
      case "En attente":
      default:
        return Icons.hourglass_bottom; // waiting
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Veuillez vous connecter.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Suivi de mes ordonnances"),
        backgroundColor: Colors.green,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('prescriptions')
            .where('createdby', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(), // <-- all prescriptions, not just latest
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Erreur : ${snapshot.error}"));
          }

          final prescriptions = snapshot.data?.docs ?? [];

          if (prescriptions.isEmpty) {
            return const Center(child: Text("Aucune ordonnance trouvée."));
          }

          return ListView.builder(
  padding: const EdgeInsets.all(16),
  itemCount: prescriptions.length,
  itemBuilder: (context, index) {
    final doc = prescriptions[index];
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final status = data['status'] ?? 'Inconnu';
    final prescriptionId = doc.id; // <-- use prescriptionId
    final createdAt = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: Icon(
          _getStatusIcon(status),
          color: _getStatusColor(status),
          size: 32,
        ),
        title: Text(
          "Ordonnance: $prescriptionId", // <-- show prescription ID
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Statut : $status\n"
          "${createdAt != null ? "Créée le : ${createdAt.toLocal()}" : ""}",
        ),
        trailing: Text(
          status.toUpperCase(),
          style: TextStyle(
            color: _getStatusColor(status),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  },
);

        },
      ),
    );
  }
}
