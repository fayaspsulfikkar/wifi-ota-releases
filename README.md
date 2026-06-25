# StealthFlashlight

StealthFlashlight is a discreet, persistent private audio room disguised as a functional flashlight utility application. It provides end-to-end WebRTC voice communication via Firebase signaling, hidden behind a fully functional flashlight interface.

## Features
*   **Fully Functional Flashlight**: Operates as a normal flashlight app with strobe and SOS features.
*   **Stealth UI**: The audio features are hidden beneath the flashlight interface.
*   **Persistent Private Audio Room**: Establish a secure, low-latency voice connection via WebRTC.
*   **Background Operation**: The application maintains connections even when running in the background.

## Technology Stack
*   **Frontend**: Flutter / Dart
*   **Backend**: Firebase (Authentication, Firestore, Cloud Functions, Cloud Messaging)
*   **Real-time Communication**: WebRTC (`flutter_webrtc`)

## Prerequisites
To build and run this project, you will need:
*   [Flutter SDK](https://flutter.dev/docs/get-started/install) (version 3.12.2 or higher)
*   [Node.js](https://nodejs.org/) (for running backend scripts)
*   A Firebase Project with Authentication, Firestore, and Cloud Messaging enabled.

## Setup Instructions

### 1. Clone the repository
```bash
git clone https://github.com/yourusername/StealthFlashlight.git
cd StealthFlashlight
```

### 2. Firebase Configuration
You must provide your own Firebase configuration files. 
*   **Android**: Download `google-services.json` from the Firebase Console and place it in the root directory and `wifi/android/app/google-services.json`.
*   **Node.js Scripts**: Download your Firebase Admin SDK service account key as `service_account.json` and place it in the root directory for use with the utility scripts.

*(Note: These files are ignored by git to prevent accidental exposure of credentials).*

### 3. Install Dependencies
```bash
cd wifi
flutter pub get
```

### 4. Run the Application
```bash
flutter run
```

## Contributing
Contributions are welcome! Please read the [Contributing Guidelines](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
