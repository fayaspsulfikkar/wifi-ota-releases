import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> removeAkshayn() async {
  final usersRef = FirebaseFirestore.instance.collection('users');
  final snapshot = await usersRef.where('username', isEqualTo: 'akshayn').get();
  
  for (final doc in snapshot.docs) {
    await doc.reference.delete();
  }
}
