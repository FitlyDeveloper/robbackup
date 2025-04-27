import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  List<Map<String, dynamic>> _workouts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkouts();
  }

  Future<void> _loadWorkouts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final workoutsJson = prefs.getString('saved_workouts');

      if (workoutsJson != null) {
        final List<dynamic> decoded = jsonDecode(workoutsJson);
        _workouts =
            decoded.map((item) => item as Map<String, dynamic>).toList();

        // Sort workouts by date (newest first)
        _workouts.sort((a, b) {
          final DateTime dateA = DateTime.parse(a['date']);
          final DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        });
      }
    } catch (e) {
      print('Error loading workouts: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteWorkout(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workoutsJson = prefs.getString('saved_workouts');

      if (workoutsJson != null) {
        final List<dynamic> workouts = jsonDecode(workoutsJson);
        final filtered =
            workouts.where((workout) => workout['id'] != id).toList();
        await prefs.setString('saved_workouts', jsonEncode(filtered));

        setState(() {
          _workouts =
              filtered.map((item) => item as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      print('Error deleting workout: $e');
    }
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background4.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // AppBar
              PreferredSize(
                preferredSize: Size.fromHeight(kToolbarHeight),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  flexibleSpace: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 29)
                            .copyWith(top: 16, bottom: 8.5),
                        child: Stack(
                          children: [
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Workout History',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 0,
                              child: IconButton(
                                icon: Icon(Icons.arrow_back,
                                    color: Colors.black, size: 24),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Divider line
              Container(
                margin: EdgeInsets.symmetric(horizontal: 29),
                height: 0.5,
                color: Color(0xFFBDBDBD),
              ),

              // Workout History List
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : _workouts.isEmpty
                        ? _buildEmptyState()
                        : _buildWorkoutList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty_state.png',
            width: 120,
            height: 120,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No workouts yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
              fontFamily: 'SF Pro Display',
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Complete a workout and save it\nto see it here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _workouts.length,
      itemBuilder: (context, index) {
        final workout = _workouts[index];
        return _buildWorkoutCard(workout);
      },
    );
  }

  Widget _buildWorkoutCard(Map<String, dynamic> workout) {
    final type = workout['type'] ?? 'Workout';
    final title = workout['title'] ?? 'My Workout';
    final date = _formatDate(workout['date']);
    final distance = workout['distance'] ?? '';
    final time = workout['time'] ?? '';
    final calories = workout['calories'] ?? '';
    final id = workout['id'];

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (direction) {
          _deleteWorkout(id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Workout deleted'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  _loadWorkouts(); // Reload to get the deleted workout back
                },
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    type.toLowerCase().contains('run')
                        ? 'assets/images/Shoe.png'
                        : 'assets/images/Dumbbell.png',
                    width: 24,
                    height: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  Spacer(),
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),

              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (distance.isNotEmpty)
                    _buildStatItem(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: distance,
                    ),
                  if (time.isNotEmpty)
                    _buildStatItem(
                      icon: Icons.access_time,
                      label: 'Duration',
                      value: time,
                    ),
                  if (calories.isNotEmpty)
                    _buildStatItem(
                      icon: Icons.local_fire_department,
                      label: 'Calories',
                      value: calories,
                    ),
                ],
              ),

              if (workout['description'] != null &&
                  workout['description'].toString().isNotEmpty) ...[
                SizedBox(height: 12),
                Text(
                  workout['description'],
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: Colors.black54,
              ),
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }
}
