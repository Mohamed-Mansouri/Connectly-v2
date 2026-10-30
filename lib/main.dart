import 'package:flutter/material.dart';
import 'app/local_app_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalAppLoader());
}
