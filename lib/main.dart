import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/app_view.dart';
import 'package:user_repository/user_repository.dart';

import 'app.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp(FirebaseUserRepo()));
}
