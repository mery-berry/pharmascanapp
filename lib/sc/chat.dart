import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'mes.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final uid = user?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("User not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Mes pharmacies"),
        backgroundColor: const Color(0xFF00C853),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup("conversations") // all conversation docs across pharmacies
            .where("patientId", isEqualTo: uid)
            .orderBy("lastTimestamp", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("Vous n'avez encore discuté avec aucune pharmacie"),
            );
          }

          final chats = snapshot.data!.docs;

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final data = chat.data() as Map<String, dynamic>;
              final pharmacyId = chat.reference.parent.parent!.id;
              final lastMessage = data["lastMessage"] ?? "";
              final timestamp = data["lastTimestamp"] as Timestamp?;
              final time = timestamp != null
                  ? "${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2,'0')}"
                  : "";

              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.local_pharmacy),
                ),
                title: Text(pharmacyId), // optionally fetch pharmacy name if you stored it
                subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(time),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessagesPage(pharmacyId: pharmacyId),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
