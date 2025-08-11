import 'package:flutter/material.dart';
import 'AddExercise.dart';
import '../WorkoutSession/WeightLiftingActive.dart';
import 'package:provider/provider.dart';
import '../WorkoutSession/WorkoutSessionProvider.dart';
import '../Screens/WeightLifting.dart';

class StartWorkoutScreen extends StatelessWidget {
  const StartWorkoutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background Image
        Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background4.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(kToolbarHeight),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 16, bottom: 8.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                        Text(
                          'Start Workout',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                            color: Colors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        SizedBox(width: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              // Divider line
              Container(
                margin: EdgeInsets.symmetric(horizontal: 29),
                height: 0.5,
                color: Color(0xFFBDBDBD),
              ),
              // Stats Row
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 29, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStat('Duration', '0'),
                    _buildStat('Volume', '0'),
                    _buildStat('PRs', '0'),
                  ],
                ),
              ),
              Container(
                margin: EdgeInsets.symmetric(horizontal: 29),
                height: 0.5,
                color: Color(0xFFBDBDBD),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 29),
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      SizedBox(height: 40),
                      // Dumbbell Icon
                      Image.asset(
                        'assets/images/dumbbell.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: 12),
                      // Get Started Text
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      SizedBox(height: 8),
                      // Subtitle Text
                      Text(
                        'Add an exercise to get started',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      SizedBox(height: 24),
                      // Add Exercise Button
                      Container(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CodiaPage(),
                              ),
                            );
                            if (result != null && result is List<Exercise>) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WeightLiftingActive(
                                    selectedExercises: result,
                                  ),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/images/add.png',
                                width: 20,
                                height: 20,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Add Exercise',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          // Discard Button
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
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
                                                  child: Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 24),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          'Discard',
                                                          style: TextStyle(
                                                            color: Color(0xFFFF3B30),
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w500,
                                                            fontFamily: 'SF Pro Display',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 16),
                                                InkWell(
                                                  onTap: () => Navigator.of(context).pop(false),
                                                  child: Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 24),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          'Cancel',
                                                          style: TextStyle(
                                                            color: Color(0xFF8E8E93),
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w500,
                                                            fontFamily: 'SF Pro Display',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
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
                                      Navigator.pop(context);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(15),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 20),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/images/trashcan.png',
                                          width: 20,
                                          height: 20,
                                          color: Color(0xFFFF3B30),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Discard',
                                          style: TextStyle(
                                            color: Color(0xFFFF3B30),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          // Finish Button
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    debugPrint('Finish tapped');
                                  },
                                  borderRadius: BorderRadius.circular(15),
                                  child: Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 20),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Settings',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            fontFamily: 'SF Pro Display',
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }
}
