import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

Future<void> _signUp() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _loading = true);

  try {
    UserCredential userCred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    User? user = userCred.user;

    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fullname': nameController.text.trim(),   // ✅ fixed
        'email': emailController.text.trim(),     // ✅ fixed
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    Navigator.pop(context); // back to login
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Compte créé avec succès ✅")),
    );
  } on FirebaseAuthException catch (e) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.message ?? "Erreur")));
  } finally {
    setState(() => _loading = false);
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              // Header
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
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Image.asset(
                      'images/icons/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "Créer un compte",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration:
                            const InputDecoration(labelText: 'Nom complet'),
                        validator: (v) =>
                            v == null || v.isEmpty ? "Entrez votre nom" : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                        validator: (v) =>
                            v == null || !v.contains("@") ? "Email invalide" : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: passwordController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: "Mot de passe",
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () {
                              setState(() => _obscure = !_obscure);
                            },
                          ),
                        ),
                        validator: (v) => v != null && v.length < 6
                            ? "6 caractères minimum"
                            : null,
                      ),
                      const SizedBox(height: 20),
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
                          onPressed: _loading ? null : _signUp,
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text("S'inscrire"),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Déjà un compte ? Se connecter"),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
