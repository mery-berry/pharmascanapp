// mes.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class MessagesPage extends StatefulWidget {
  final String pharmacyId;

  const MessagesPage({super.key, required this.pharmacyId});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final TextEditingController _controller = TextEditingController();
  final User? user = FirebaseAuth.instance.currentUser;
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    try {
      final text = _controller.text.trim();
      final uid = user?.uid;
      if (uid == null) return;

      final firestore = FirebaseFirestore.instance;
      final conversationRef = firestore
          .collection("pharmacies")
          .doc("default_pharmacy")
          .collection("conversations")
          .doc(uid);

      // CRITICAL FIX: Ensure patientId is stored as a FIELD, not just document ID
      await conversationRef.set({
        "patientId": uid, // This field is required for the chat list query
        "pharmacyName": widget.pharmacyId,
        "lastMessage": text,
        "lastTimestamp": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Add the actual message
      await conversationRef.collection("messages").add({
        "sender": "patient",
        "text": text,
        "timestamp": FieldValue.serverTimestamp(),
      });

      _controller.clear();
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureConversationStructure();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // NEW METHOD: Fix existing conversations that don't have patientId field
  void _ensureConversationStructure() async {
    final uid = user?.uid;
    if (uid == null) return;

    try {
      final conversationRef = FirebaseFirestore.instance
          .collection("pharmacies")
          .doc(widget.pharmacyId)
          .collection("conversations")
          .doc(uid);

      final doc = await conversationRef.get();
      
      // If conversation exists but doesn't have patientId field, add it
      if (doc.exists && !doc.data()!.containsKey('patientId')) {
        await conversationRef.set({
          'patientId': uid, // Add the missing field
          'lastTimestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        print("Fixed conversation structure for: $uid");
      }
    } catch (e) {
      print("Error ensuring conversation structure: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = user?.uid ?? "guest";

    return Scaffold(
      appBar: AppBar(
        title: Text("Chat with ${widget.pharmacyId}"),
        backgroundColor: const Color(0xFF00C853),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("pharmacies")
                  .doc(widget.pharmacyId)
                  .collection("conversations")
                  .doc(uid)
                  .collection("messages")
                  .orderBy("timestamp", descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No messages yet\nStart the conversation!",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data() as Map<String, dynamic>;
                    final isMe = data["sender"] == "patient";
                    final text = data["text"] ?? "";
                    
                    String time = "";
                    if (data["timestamp"] != null) {
                      time = DateFormat("hh:mm a")
                          .format((data["timestamp"] as Timestamp).toDate());
                    }

                    return MessageBubble(
                      text: text,
                      isMe: isMe,
                      time: time,
                      isPharmacist: !isMe,
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, -2),
              blurRadius: 4,
              color: Colors.black.withOpacity(0.1),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: "Type your message...",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(50),
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String time;
  final bool isPharmacist;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.time,
    required this.isPharmacist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) 
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green[100],
              child: const Icon(
                Icons.local_pharmacy,
                size: 16,
                color: Colors.green,
              ),
            ),
          if (!isMe) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMe ? Colors.blue.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              child: const Icon(
                Icons.person,
                size: 16,
                color: Colors.grey,
              ),
            ),
        ],
      ),
    );
  }
}