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
    appId: '1:712176340011:ios:c5ba9923b50c71b9022e6e',
    messagingSenderId: '712176340011',
    projectId: 'acilyardim-aeaf4',
    storageBucket: 'acilyardim-aeaf4.firebasestorage.app',
    iosBundleId: 'com.MesutAltintas.AcilYardim',
    iosClientId: '712176340011-h11hpmmhs7eo2o2mim37g4gdl21uf56i.apps.googleusercontent.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBJAaocvaqOKcA7CYjbsZPP4G0miQmp7u0',
    appId: '1:712176340011:android:036eec7c463e61ec022e6e',
    messagingSenderId: '712176340011',
    projectId: 'acilyardim-aeaf4',
    storageBucket: 'acilyardim-aeaf4.firebasestorage.app',
  );
}
