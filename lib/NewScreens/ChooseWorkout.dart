import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import '../Features/codia/codia_page.dart';
import 'LogRunning.dart';
import 'LogDescribeExercise.dart';
import '../Screens/WeightLifting.dart';
import '../Widgets/WorkoutSessionBanner.dart';
import '../WorkoutSession/WorkoutSessionProvider.dart';
import 'package:provider/provider.dart';

class ChooseWorkout extends StatefulWidget {
  const ChooseWorkout({Key? key}) : super(key: key);

  @override
  State<ChooseWorkout> createState() => _ChooseWorkoutState();
}

class _ChooseWorkoutState extends State<ChooseWorkout> {
  int _selectedIndex = 3;

  @override
  Widget build(BuildContext context) {
    final isBannerVisible = Provider.of<WorkoutSessionProvider>(context).isActive;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/background4.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 29)
                      .copyWith(top: 16, bottom: 8.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Workout',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),

                // Slim gray divider line
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
                        Spacer(flex: 2),
                        // Weight Lifting Option
                        _buildWorkoutCard(
                          'Weight Lifting',
                          'Lift with machines or free weights',
                          'assets/images/dumbbell.png',
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WeightLifting(),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 12),

                        // Running Option
                        _buildWorkoutCard(
                          'Running',
                          'Track your runs, jogs, sprints etc',
                          'assets/images/Shoe.png',
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LogRunning(),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 12),

                        // More Option
                        _buildWorkoutCard(
                          'More',
                          'Create custom exercises',
                          'assets/images/add.png',
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LogDescribeExercise(),
                              ),
                            );
                          },
                        ),
                        Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isBannerVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 90.0 - 0.5, // align exactly with nav bar, account for divider
              child: WorkoutSessionBanner(),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: isBannerVisible ? [] : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 0),
                child: Transform.translate(
                  offset: Offset(0, -5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem('Home', 'assets/images/home.png',
                          _selectedIndex == 0, 0),
                      _buildNavItem('Social', 'assets/images/socialicon.png',
                          _selectedIndex == 1, 1),
                      _buildNavItem('Nutrition', 'assets/images/nutrition.png',
                          _selectedIndex == 2, 2),
                      _buildNavItem('Workout', 'assets/images/dumbbell.png',
                          _selectedIndex == 3, 3),
                      _buildNavItem('Profile', 'assets/images/profile.png',
                          _selectedIndex == 4, 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(
    String title,
    String subtitle,
    String iconPath,
    VoidCallback onTap,
  ) {
    return Container(
      height: 84,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F8FE),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset(
                      iconPath,
                      width: title == 'More' ? 28 : 32,
                      height: title == 'More' ? 28 : 32,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
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
  }

  Widget _buildNavItem(
      String label, String iconPath, bool isSelected, int index) {
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  CodiaPage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: 27.6,
            height: 27.6,
            color: isSelected ? Colors.black : Colors.grey,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.grey,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
