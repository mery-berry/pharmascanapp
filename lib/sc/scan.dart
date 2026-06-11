import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// 🧭 Import your GPS page
import 'gps.dart'; // make sure this import path matches your file name

class ScanPrescriptionPage extends StatefulWidget {
  const ScanPrescriptionPage({super.key});

  @override
  State<ScanPrescriptionPage> createState() => _ScanPrescriptionPageState();
}

class _ScanPrescriptionPageState extends State<ScanPrescriptionPage> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  // Take a photo with camera
  Future<void> _takePhoto() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (pickedFile != null) {
        setState(() => _selectedImage = File(pickedFile.path));
      }
    } catch (e) {
      _showError('Erreur caméra: $e');
    }
  }

  // Import photo from gallery
  Future<void> _importPhoto() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (pickedFile != null) {
        setState(() => _selectedImage = File(pickedFile.path));
      }
    } catch (e) {
      _showError('Erreur galerie: $e');
    }
  }

  // Delete selected photo
  void _deletePhoto() => setState(() => _selectedImage = null);

  // Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // TEST URL FUNCTION
  Future<bool> _testImageUrl(String url) async {
    try {
      print('🧪 TESTING URL: $url');
      final response = await http.get(Uri.parse(url));
      print('📊 Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('✅ URL IS VALID AND ACCESSIBLE');
        return true;
      } else {
        print('❌ URL RETURNS ERROR: ${response.statusCode}');
        print('📄 Response body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ URL TEST FAILED: $e');
      return false;
    }
  }

  // 🧭 Navigate to GPS page after upload
  void _goToGpsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GpsPage()),
    );
  }

  // Upload prescription to Firebase
  Future<void> _uploadPrescription() async {
    if (_selectedImage == null) {
      _showError('Veuillez sélectionner une image');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError("Veuillez vous connecter");
      return;
    }

    String patientName = 'Patient';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        patientName = userDoc.data()!['fullname'] ?? 'Patient';
        print('✅ Found user name: $patientName');
      } else {
        print('⚠️ User document not found, using default name');
      }
    } catch (e) {
      print('❌ Error fetching user data: $e');
    }

    if (!await _selectedImage!.exists()) {
      _showError("Le fichier image n'existe pas");
      return;
    }

    setState(() => _uploading = true);

    try {
      // Create unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'prescriptions/${user.uid}/prescription_$timestamp.jpg';

      print('📁 File name: $fileName');
      print('📊 File size: ${await _selectedImage!.length()} bytes');

      final ref = FirebaseStorage.instance.ref().child(fileName);

      // Upload file with metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {
          'uploadedBy': user.uid,
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      );

      print('🔄 Starting upload...');
      final uploadTask = ref.putFile(_selectedImage!, metadata);
      final TaskSnapshot snapshot = await uploadTask;

      print('📋 Upload state: ${snapshot.state}');
      print('✅ Bytes transferred: ${snapshot.bytesTransferred}');

      if (snapshot.state == TaskState.success) {
        // Get download URL
        print('🔗 Getting download URL...');
        final rawUrl = await snapshot.ref.getDownloadURL();
        final imageUrl = rawUrl.replaceAll('\n', '').trim();

        print('📸 GENERATED URL: $imageUrl');
        print('📏 URL length: ${imageUrl.length}');

        // TEST THE URL
        final bool isUrlValid = await _testImageUrl(imageUrl);

        if (!isUrlValid) {
          _showError("Erreur: URL d'image invalide");
          return;
        }

        // Save to Firestore
        print('💾 Saving to Firestore...');
        await FirebaseFirestore.instance.collection('prescriptions').add({
          'createdby': user.uid,
          'patientName': patientName,
          'date': DateTime.now().toIso8601String(),
          'status': 'En attente',
          'prescriptionImage': imageUrl,
          'createdAt': FieldValue.serverTimestamp(),
          'medicament': '',
          'dosage': '',
          'frequence': '',
          'duree': '',
        });

        if (mounted) {
          setState(() {
            _selectedImage = null;
            _uploading = false;
          });
        }
      } else {
        throw 'Échec du téléchargement: ${snapshot.state}';
      }
    } on FirebaseException catch (e) {
      debugPrint('Firebase error: ${e.code} - ${e.message}');
      _showError("Erreur Firebase: ${e.message ?? e.code}");
    } catch (e, stack) {
      debugPrint('Upload error: $e');
      debugPrint('Stack trace: $stack');
      _showError("Erreur: $e");
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF00C853), Color(0xFF00E676)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),
            const Text(
              "Scanner Ordonnance",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Camera button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                foregroundColor: Colors.black,
              ),
              onPressed: _uploading ? null : _takePhoto,
              icon: const Icon(Icons.photo_camera),
              label: const Text("Prendre une photo"),
            ),
            const SizedBox(height: 12),

            // Gallery button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade200,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                foregroundColor: Colors.black,
              ),
              onPressed: _uploading ? null : _importPhoto,
              icon: const Icon(Icons.image),
              label: const Text("Importer depuis la galerie"),
            ),
            const SizedBox(height: 20),

            // Image preview
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: _selectedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error, color: Colors.red, size: 40),
                                SizedBox(height: 8),
                                Text("Erreur de chargement",
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library,
                              color: Colors.grey, size: 40),
                          SizedBox(height: 8),
                          Text("Aucune image sélectionnée",
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: (_selectedImage != null && !_uploading)
                      ? () async {
                          await _uploadPrescription();
                          _goToGpsPage();
                        }
                      : null,
                  icon: const Icon(Icons.check, color: Colors.blue),
                  label: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Confirmer",
                          style: TextStyle(color: Colors.blue)),
                ),
                const SizedBox(width: 20),
                TextButton.icon(
                  onPressed: (_selectedImage != null && !_uploading)
                      ? _deletePhoto
                      : null,
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text("Supprimer",
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const Spacer(),

            // Send button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                foregroundColor: Colors.white,
              ),
              onPressed: (_selectedImage != null && !_uploading)
                  ? () async {
                      await _uploadPrescription();
                      _goToGpsPage();
                    }
                  : null,
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Envoyer l'ordonnance",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Votre ordonnance est uploadée de manière sécurisée ✅",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
