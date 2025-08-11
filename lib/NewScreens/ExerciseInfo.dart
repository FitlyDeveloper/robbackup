import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Screens/WeightLifting.dart';
import 'AddExercise.dart';
import 'package:fl_chart/fl_chart.dart';
import '../WorkoutSession/WeightLiftingActive.dart';

class ExerciseInfo extends StatefulWidget {
  final String exerciseName;
  final String muscle;
  final ExerciseSessionData? sessionData;

  const ExerciseInfo({
    Key? key,
    required this.exerciseName,
    required this.muscle,
    this.sessionData,
  }) : super(key: key);

  @override
  State<ExerciseInfo> createState() => _ExerciseInfoState();
}

class _ExerciseInfoState extends State<ExerciseInfo> {
  bool isFavorite = false;
  String _selectedMetric = 'Weight'; // 'Weight', '1RM', or 'Volume'
  String _selectedTimeRange = 'Last 3 months'; // 'Last 3 months', 'Last year', 'All time'
  
  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isFavorite = prefs.getBool('favorite_${widget.exerciseName}') ?? false;
    });
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isFavorite = !isFavorite;
    });
    await prefs.setBool('favorite_${widget.exerciseName}', isFavorite);
  }

  String _getDisplayMetric() {
    if (widget.sessionData == null) return '0';
    switch (_selectedMetric) {
      case 'Weight':
        return '${widget.sessionData!.heaviestWeight}';
      case '1RM':
        return '${widget.sessionData!.best1RM.toStringAsFixed(1)}';
      case 'Volume':
        return '${widget.sessionData!.bestSetVolume}';
      default:
        return '0';
    }
  }

  String _getMetricUnit() {
    switch (_selectedMetric) {
      case 'Weight':
        return 'kg';
      case '1RM':
        return 'kg';
      case 'Volume':
        return 'kg·reps';
      default:
        return 'kg';
    }
  }

  List<FlSpot> _getChartSpots() {
    if (widget.sessionData == null || widget.sessionData!.sets.isEmpty) {
      return [];
    }

    final value = double.parse(_getDisplayMetric());
    final spots = <FlSpot>[];
    
    // For single data point, place it in the center
    if (widget.sessionData!.sets.length == 1) {
      spots.add(FlSpot(45, value)); // Center horizontally (90/2)
    } else {
      // For multiple data points, use actual data
      spots.add(FlSpot(0, value));
      // Add more spots based on historical data when available
    }
    return spots;
  }

  LineChartData _getChartData() {
    final value = double.parse(_getDisplayMetric());
    final isSinglePoint = widget.sessionData != null && widget.sessionData!.sets.length == 1;
    final unit = _getMetricUnit(); // Get the metric unit

    // Calculate Y-axis range for single point
    final minY = isSinglePoint ? (value - 1).toDouble() : 0.0;
    final maxY = isSinglePoint ? (value + 1).toDouble() : (value * 1.2).toDouble(); // Add 20% buffer for multiple points

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: isSinglePoint ? 1.0 : null, // 1kg intervals for single point
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Color(0xFFEEEEEE),
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: isSinglePoint ? 1.0 : null, // 1kg intervals for single point
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}$unit',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: !isSinglePoint, // Hide dates for single point
            getTitlesWidget: (value, meta) {
              final date = DateTime.now().subtract(Duration(days: (90 - value).toInt()));
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '${date.month}/${date.day}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _getChartSpots(),
          isCurved: !isSinglePoint,
          color: Colors.black,
          barWidth: isSinglePoint ? 0 : 2, // No line for single point
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: isSinglePoint ? 5 : 4, // Slightly larger dot for single point
                color: Colors.black,
                strokeWidth: 0,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: !isSinglePoint,
            color: Colors.black.withOpacity(0.1),
          ),
        ),
      ],
      minY: minY,
      maxY: maxY,
      lineTouchData: LineTouchData(enabled: false), // Disable touch interaction
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.sessionData != null && widget.sessionData!.sets.isNotEmpty;
    final latestDate = hasData ? widget.sessionData!.date : null;
    final displayMetric = _getDisplayMetric();
    final metricUnit = _getMetricUnit();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background4.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 24),
            children: [
              // Header with back button and title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0).copyWith(top: 16, bottom: 8.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(),
                    ),
                    Text(
                      widget.exerciseName,
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
              Container(
                margin: EdgeInsets.symmetric(horizontal: 0),
                height: 0.5,
                color: Color(0xFFBDBDBD),
              ),
              SizedBox(height: 20),
              // Exercise Info Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                child: Container(
                  width: 331,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x14000000),
                        offset: Offset(0, 3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 13),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/dumbbell.png',
                            width: 24,
                            height: 24,
                            color: Colors.grey[700],
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.exerciseName,
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: 15,
                                color: Colors.black,
                                fontFamily: 'SFProDisplay-Regular',
                                decoration: TextDecoration.none,
                              ),
                            ),
                            Text(
                              widget.muscle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0x7f000000),
                                fontFamily: 'SFProDisplay-Regular',
                                fontWeight: FontWeight.normal,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      GestureDetector(
                        onTap: _toggleFavorite,
                        child: Image.asset(
                          isFavorite ? 'assets/images/bookmarkfilled.png' : 'assets/images/bookmark.png',
                          width: 20,
                          height: 20,
                          color: isFavorite ? Color(0xFFFFC300) : Colors.black,
                        ),
                      ),
                      SizedBox(width: 13),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Weight and date info
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 0, top: 14),
                child: Row(
                  children: [
                    Text(
                      '$displayMetric $metricUnit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (latestDate != null) Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '(${latestDate.month}/${latestDate.day})',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    Spacer(),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              backgroundColor: Colors.white,
                              insetPadding: EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                                    child: Text(
                                      'Select Time Range',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  ...['Last 3 months', 'Last year', 'All time'].map((String value) {
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedTimeRange = value;
                                        });
                                        Navigator.pop(context);
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Color(0xFFEEEEEE),
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            value,
                                            style: TextStyle(
                                              fontSize: 17,
                                              color: _selectedTimeRange == value ? Colors.black : Colors.grey[600],
                                              fontWeight: _selectedTimeRange == value ? FontWeight.w600 : FontWeight.normal,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedTimeRange,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // Graph
              Container(
                height: 260,
                child: hasData ? LineChart(_getChartData()) : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No data yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Log this exercise to see progress!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Stat buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildStatButton('Heaviest Weight', _selectedMetric == 'Weight')),
                        SizedBox(width: 8),
                        Expanded(child: _buildStatButton('One Rep Max', _selectedMetric == '1RM')),
                      ],
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.5,
                        child: _buildStatButton('Best Set Volume', _selectedMetric == 'Volume'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // Personal Records title
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/weekstreak.png',
                      width: 24,
                      height: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Personal Records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Personal Records entries
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Column(
                  children: [
                    _buildRecord(
                      'Heaviest Weight:', 
                      hasData ? '${widget.sessionData!.heaviestWeight.round()}kg' : '-'
                    ),
                    Divider(height: 24, thickness: 0.5, color: Color(0xFFEEEEEE)),
                    _buildRecord(
                      'Best 1RM:', 
                      hasData ? '${widget.sessionData!.best1RM.round()}kg' : '-'
                    ),
                    Divider(height: 24, thickness: 0.5, color: Color(0xFFEEEEEE)),
                    _buildRecord(
                      'Best Set Volume:', 
                      hasData ? '${widget.sessionData!.bestSetVolume.round()}kg' : '-'
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              // Set Records title
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 12),
                child: Text(
                  'Set Records',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Set Records table header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: Row(
                  children: [
                    Text(
                      'Reps',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Personal Best',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
              // Set Records
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: hasData ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...widget.sessionData!.setRecords.entries
                      .where((e) => e.value > 0) // Filter out zero weights
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                        final record = entry.value;
                        final isLast = entry.key == widget.sessionData!.setRecords.length - 1;
                        return Column(
                          children: [
                            _buildSetRecordRow(
                              '${record.key}', // reps
                              '${record.value.round()}kg' // weight
                            ),
                            if (!isLast) Divider(height: 24, thickness: 0.5, color: Color(0xFFEEEEEE)),
                          ],
                        );
                      })
                      .toList(),
                  ],
                ) : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No records yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatButton(String label, bool isSelected) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.black : Color(0xFFEEEEEE).withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildRecord(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSetRecordRow(String reps, String weight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              reps,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          Spacer(),
          SizedBox(
            width: 80,
            child: Text(
              weight,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final points = [
      Offset(0, size.height * 0.6),
      Offset(size.width * 0.25, size.height * 0.3),
      Offset(size.width * 0.5, size.height * 0.3),
      Offset(size.width * 0.75, size.height * 0.6),
      Offset(size.width, size.height * 0.7),
    ];

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      path.lineTo(p2.dx, p2.dy);
    }

    canvas.drawPath(path, paint);

    // Draw dots
    final dotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
