import 'package:flutter/material.dart';
import '../NewScreens/AddExercise.dart';
import '../NewScreens/AddRoutine.dart';
import '../NewScreens/StartWorkout.dart';
import '../NewScreens/ChooseWorkout.dart';
import '../Widgets/WorkoutSessionBanner.dart';
import '../WorkoutSession/WorkoutSessionProvider.dart';
import 'package:provider/provider.dart';

class WeightLifting extends StatefulWidget {
  const WeightLifting({Key? key}) : super(key: key);

  @override
  State<WeightLifting> createState() => _WeightLiftingState();
}

class _WeightLiftingState extends State<WeightLifting> {
  bool _isRoutineExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
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
              // Main Content
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
                                  Navigator.of(context).pushReplacement(
                                    PageRouteBuilder(
                                      opaque: false,
                                      pageBuilder: (context, animation, secondaryAnimation) => ChooseWorkout(),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return Stack(
                                          children: [
                                            child,
                                            SlideTransition(
                                              position: Tween<Offset>(
                                                begin: Offset.zero,
                                                end: const Offset(1.0, 0.0),
                                              ).animate(CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeInOut,
                                              )),
                                              child: Container(
                                                color: Colors.transparent,
                                                child: this.widget,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  );
                                },
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                              Text(
                                'Weight Lifting',
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 29),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 20),
                              // Quick Start Section
                              Text(
                                'Quick Start',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              SizedBox(height: 15),
                              // Start Workout Button
                              Container(
                                width: double.infinity,
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
                                      debugPrint('Start Workout tapped');
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const StartWorkoutScreen(),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(15),
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Image.asset(
                                            'assets/images/add.png',
                                            width: 20,
                                            height: 20,
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Start Workout',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 29),
                              // Routines Section
                              Text(
                                'Routines',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              SizedBox(height: 15),
                              // Routines Row
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 90,
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
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const AddRoutine(),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(15),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/images/clipboard.png',
                                                width: 28,
                                                height: 28,
                                                fit: BoxFit.contain,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'Add Routine',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: Container(
                                      height: 90,
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
                                            // Handle routines for you
                                          },
                                          borderRadius: BorderRadius.circular(15),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Image.asset(
                                                'assets/images/profile.png',
                                                width: 28,
                                                height: 28,
                                                fit: BoxFit.contain,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                'Routines For You',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black,
                                                  fontFamily: 'SF Pro Display',
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 15),
                              // My Routines Button
                              Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isRoutineExpanded = !_isRoutineExpanded;
                                    });
                                  },
                                  child: Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Color(0xFFEEEEEE),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'My Routines (1)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(
                                            _isRoutineExpanded
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons.keyboard_arrow_down_rounded,
                                            size: 18,
                                            color: Colors.black,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_isRoutineExpanded) ...[
                                SizedBox(height: 20),
                                Container(
                                  width: double.infinity,
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
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Push',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Bench Press (Barbell), Incline Chest Press (Machine), Triceps Pushdown...',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.grey[600],
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                        SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 48,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              // Handle start routine
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.black,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                            ),
                                            child: Text(
                                              'Start Routine',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.white,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Add a white background container to fill the bottom 20px gap
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 20.0,
          child: Container(color: Colors.white),
        ),
        Consumer<WorkoutSessionProvider>(
          builder: (context, session, child) {
            if (!session.isActive) return SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: WorkoutSessionBanner(extendToBottom: true),
            );
          },
        ),
      ],
    );
  }
}
