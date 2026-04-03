import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web desteklenmiyor');
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Bu platform desteklenmiyor');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBh_nySoq9ikhwlwgZgkjcPTTc9q4VcZQk',
    appId: '1:712176340011:ios:9ba6f120496bd040022e6e',
    messagingSenderId: '712176340011',
    projectId: 'acilyardim-aeaf4',
    storageBucket: 'acilyardim-aeaf4.firebasestorage.app',
    iosBundleId: 'com.example.acilYardim',
    iosClientId: '712176340011-fl2kisdcpr7skjmk07nskhd3i1kq1dbs.apps.googleusercontent.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBJAaocvaqOKcA7CYjbsZPP4G0miQmp7u0',
    appId: '1:712176340011:android:a80204ecbe8271f1022e6e',
    messagingSenderId: '712176340011',
    projectId: 'acilyardim-aeaf4',
    storageBucket: 'acilyardim-aeaf4.firebasestorage.app',
  );
}
