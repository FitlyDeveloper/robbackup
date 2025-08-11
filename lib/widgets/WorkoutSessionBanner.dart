import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../WorkoutSession/WorkoutSessionProvider.dart';

class WorkoutSessionBanner extends StatelessWidget {
  final bool extendToBottom;
  const WorkoutSessionBanner({Key? key, this.extendToBottom = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkoutSessionProvider>(
      builder: (context, session, child) {
        if (!session.isActive) return SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner container
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(0),
                  bottomRight: Radius.circular(0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 8,
                    offset: Offset(0, -2), // Only top shadow
                  ),
                ],
              ),
              height: extendToBottom ? 92 : 72,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Centered label
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Center(
                      child: Text(
                        'Workout in Progress',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Color(0xFF8E8E93),
                          fontFamily: 'SF Pro Display',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  // Resume/Discard row
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: session.onResume,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset('assets/images/playbutton.png', width: 18, height: 18),
                              SizedBox(width: 8),
                              Text(
                                'Resume',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'SF Pro Display',
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final shouldDiscard = await showDialog<bool>(
                              context: context,
                              barrierColor: Colors.black.withOpacity(0.5),
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                insetPadding: EdgeInsets.symmetric(horizontal: 24),
                                child: Center(
                                  child: Container(
                                    width: 338,
                                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 16,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Discard Workout?',
                                          style: TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'SF Pro Display',
                                            color: Colors.black,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        SizedBox(height: 24),
                                        InkWell(
                                          onTap: () => Navigator.of(context).pop(true),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/images/trashcan.png',
                                                width: 15,
                                                height: 15,
                                                color: Color(0xFFFF3B30),
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Discard',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Color(0xFFFF3B30),
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: 'SF Pro Display',
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 16),
                                        InkWell(
                                          onTap: () => Navigator.of(context).pop(false),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/images/CLOSEicon.png',
                                                width: 15,
                                                height: 15,
                                                color: Color(0xFFBDBDBD),
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Cancel',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Color(0xFF8E8E93),
                                                  fontWeight: FontWeight.w500,
                                                  fontFamily: 'SF Pro Display',
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                            if (shouldDiscard == true) {
                              Provider.of<WorkoutSessionProvider>(context, listen: false).endSession();
                            }
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ColorFiltered(
                                colorFilter: ColorFilter.mode(Color(0xFFFF3B30), BlendMode.srcIn),
                                child: Image.asset('assets/images/trashcan.png', width: 18, height: 18),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Discard',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFFF3B30),
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'SF Pro Display',
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (extendToBottom) SizedBox(height: 20),
                ],
              ),
            ),
            if (!extendToBottom)
              Container(
                width: double.infinity,
                height: 0.5,
                color: const Color(0xFFBDBDBD),
              ),
          ],
        );
      },
    );
  }
} 