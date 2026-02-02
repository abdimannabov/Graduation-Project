import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/face_id_service.dart';

class FaceIdSetupScreen extends StatefulWidget {
  const FaceIdSetupScreen({super.key});

  @override
  State<FaceIdSetupScreen> createState() => _FaceIdSetupScreenState();
}

class _FaceIdSetupScreenState extends State<FaceIdSetupScreen> {
  final FaceIdService _faceIdService = FaceIdService();
  bool isLoading = false;
  bool isFaceIdAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkFaceIdAvailability();
  }

  Future<void> _checkFaceIdAvailability() async {
    final available = await _faceIdService.isFaceIdAvailable();
    setState(() {
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
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Face ID'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.face,
                        size: 80,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Secure Face ID Authentication',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Info Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔐 Why Face ID?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoPoint(
                      '⚠️ Mandatory Enrollment',
                      'You must enroll Face ID or Fingerprint on this device. The app blocks camera scanning for attendance until you enroll. This is enforced to prevent attendance fraud and is not optional.',
                    ),
                    const SizedBox(height: 8),
                    _buildInfoPoint(
                      '🚫 Prevents Cheating',
                      'Only you can use your account for attendance',
                    ),
                    const SizedBox(height: 8),
                    _buildInfoPoint(
                      '🔒 One Face Only',
                      'You can enroll only ONE face per account',
                    ),
                    const SizedBox(height: 8),
                    _buildInfoPoint(
                      '📱 Uses Phone\'s Built-in',
                      'No additional cost - uses your device\'s Face ID',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Important Notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ Important',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Once you enroll Face ID, only your face can be used for attendance. You cannot add another person\'s face to your account. This prevents cheating and ensures academic integrity.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Availability Check
              if (!isFaceIdAvailable)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: const Text(
                    '❌ Face ID is not available on your device. Please ensure your device supports Face ID or Fingerprint authentication.',
                    style: TextStyle(fontSize: 13, color: Colors.red),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Text(
                    '✅ Face ID is available on your device',
                    style: TextStyle(fontSize: 13, color: Colors.green),
                  ),
                ),

              const SizedBox(height: 40),

              // Setup Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isFaceIdAvailable && !isLoading
                      ? _setupFaceId
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Setup Face ID',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Cancel Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Skip for Now'),
                ),
              ),
              const SizedBox(height: 24),

              // Additional Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '💡 Tip: You can enroll Face ID anytime in Account Settings. However, once enrolled, only that face can be used for attendance scanning.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPoint(String title, String description) {
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
                  fontSize: 14,
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
