import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'signup.dart';
import '../main.dart'; // where your HomeScreen is

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _version = '';
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = "Version ${info.version}";
    });
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Veuillez entrer votre e-mail';
    final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Format e-mail invalide';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Veuillez entrer le mot de passe';
    if (value.length < 6) return 'Le mot de passe doit contenir au moins 6 caractères';
    return null;
  }

Future<void> _login() async {
  if (_formKey.currentState!.validate()) {
    try {
      // Authenticate
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = userCredential.user!.uid;

      // ✅ Fetch username from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

          // In login.dart, change:
      String username = userDoc.data()?['fullname'] ?? "Utilisateur";      print("Current user UID: $uid");

      // Navigate to HomeScreen with the username
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(username: username),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = "Erreur de connexion";
      if (e.code == 'user-not-found') {
        message = "Aucun compte trouvé pour cet e-mail.";
      } else if (e.code == 'wrong-password') {
        message = "Mot de passe incorrect.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              // ✅ Header
              Container(
                height: MediaQuery.of(context).size.height * 0.38,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(60),
                    bottomRight: Radius.circular(60),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Image.asset(
                          'images/icons/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        "Votre confort est notre souci",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              const Text(
                "Se connecter",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              // ✅ Form
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Email
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          hintText: 'someone@test.com',
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              setState(() {
                                _obscure = !_obscure;
                              });
                            },
                          ),
                        ),
                        validator: _validatePassword,
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          child: const Text("Mot de passe oublié ?"),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C853),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Navigate to signup
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignUpScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Créer un nouveau compte",
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Text(
                        _version,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
