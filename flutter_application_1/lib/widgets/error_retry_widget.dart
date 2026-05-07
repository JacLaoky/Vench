import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants.dart';

class ErrorRetryWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;

  const ErrorRetryWidget({
    super.key,
    required this.onRetry,
    this.message = 'Unable to connect to server.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: AppColors.red, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Connection Failed',
                style: TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.dim, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: AppColors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Retry',
                        style: TextStyle(
                            color: AppColors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
