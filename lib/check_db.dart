import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final users = await FirebaseFirestore.instance.collection('users').get();
  for (var doc in users.docs) {
    print('USER: ${doc.data()}');
  }

  final rooms = await FirebaseFirestore.instance.collection('rooms').get();
  for (var doc in rooms.docs) {
    print('ROOM: ${doc.data()}');
  }
}
