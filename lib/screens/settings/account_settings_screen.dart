import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/face_id_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final FaceIdService _faceIdService = FaceIdService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool hasFaceIdEnrolled = false;
  bool isLoading = false;
  bool isFaceIdAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadFaceIdStatus();
  }

  Future<void> _loadFaceIdStatus() async {
    final enrolled = await _faceIdService.hasFaceIdEnrolled();
    final available = await _faceIdService.isFaceIdAvailable();

    setState(() {
      hasFaceIdEnrolled = enrolled;
      isFaceIdAvailable = available;
    });
  }

  Future<void> _setupFaceId() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await _faceIdService.setupFaceId();

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        if (result['success']) {
          Fluttertoast.showToast(
            msg: "✅ ${result['message']}",
            backgroundColor: Colors.green,
          );

          setState(() {
            hasFaceIdEnrolled = true;
          });
        } else {
          String errorMsg = result['error'] ?? 'Setup failed';
          String? reason = result['reason'];

          Fluttertoast.showToast(
            msg: "❌ $errorMsg${reason != null ? '\n$reason' : ''}",
            backgroundColor: Colors.red,
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });

        Fluttertoast.showToast(msg: "❌ Error: $e", backgroundColor: Colors.red);
      }
    }
  }

  Future<void> _removeFaceId() async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Face ID'),
        content: const Text(
          'Are you sure you want to remove Face ID? You\'ll need to verify your face first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performRemoveFaceId();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _performRemoveFaceId() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await _faceIdService.removeFaceId();

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        if (result['success']) {
          Fluttertoast.showToast(
            msg: "✅ ${result['message']}",
            backgroundColor: Colors.green,
          );

          setState(() {
            hasFaceIdEnrolled = false;
          });
        } else {
          String errorMsg = result['error'] ?? 'Removal failed';

          Fluttertoast.showToast(
            msg: "❌ $errorMsg",
            backgroundColor: Colors.red,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });

        Fluttertoast.showToast(msg: "❌ Error: $e", backgroundColor: Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Account Email',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? 'Not available',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Face ID Section
              const Text(
                'Security Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Face ID Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: hasFaceIdEnrolled
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasFaceIdEnrolled
                        ? Colors.green.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.face,
                              color: hasFaceIdEnrolled
                                  ? Colors.green
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Face ID Authentication',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  hasFaceIdEnrolled
                                      ? '✅ Enrolled & Active'
                                      : '❌ Not Enrolled',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: hasFaceIdEnrolled
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (hasFaceIdEnrolled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!isFaceIdAvailable)
                      Text(
                        '⚠️ Face ID is not available on this device',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      )
                    else
                      Text(
                        hasFaceIdEnrolled
                            ? 'Your face is enrolled for attendance verification. Only your enrolled face can be used to scan QR codes.'
                            : 'Enroll your face to enable Face ID authentication for attendance scanning.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const SizedBox(height: 12),
                    // Buttons
                    if (!hasFaceIdEnrolled && isFaceIdAvailable)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _setupFaceId,
                          icon: const Icon(Icons.face),
                          label: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Enroll Face ID'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      )
                    else if (hasFaceIdEnrolled)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoading ? null : _removeFaceId,
                          icon: const Icon(Icons.delete_outline),
                          label: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Remove Face ID'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Info Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔐 Security & Anti-Cheating',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPoint(
                      '📱 Device Binding',
                      'Your account is bound to your device. You can only use registered device to access account.',
                    ),
                    const SizedBox(height: 8),
                    _buildSecurityPoint(
                      '🔐 One Face Per Account',
                      'Only one face can be enrolled per account. This prevents account sharing.',
                    ),
                    const SizedBox(height: 8),
                    _buildSecurityPoint(
                      '📊 Activity Logging',
                      'All Face ID attempts (success/failure) are logged for security audit.',
                    ),
                    const SizedBox(height: 8),
                    _buildSecurityPoint(
                      '✅ Academic Integrity',
                      'These security measures ensure fair and honest attendance system.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityPoint(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
