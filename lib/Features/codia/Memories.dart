import 'package:flutter/material.dart';
// Memories calendar, now synced to real time

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<StatefulWidget> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  final List<String> _monthNames = const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  int _daysInMonth(int year, int month) {
    // Day 0 of next month is the last day of current month
    return DateTime(year, month + 1, 0).day;
  }

  int _firstWeekdayOffset(int year, int month) {
    // DateTime.weekday: Mon=1 ... Sun=7; we want 0-based offset for grid
    return DateTime(year, month, 1).weekday - 1;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background4.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Header with back button and title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 29)
                      .copyWith(top: 16, bottom: 8.5),
              child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                      // Back button (styled like signin.dart - simple IconButton)
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.black, size: 24),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),

                      // Memories title (sized like 'Today' text but centered position)
                    Text(
                        'Memories',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                          color: Colors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),

                      // Empty space to balance the header (same width as back button)
                      SizedBox(width: 24),
                  ],
                ),
              ),

                // Slim gray divider line
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 29),
                  height: 1,
                  color: Color(0xFFBDBDBD),
                ),

                // Current month calendar (real time)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 20, bottom: 8),
                        child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                      ),
                    ],
                  ),
              child: Column(
                children: [
                        // Month header (current)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Builder(builder: (context) {
                            final now = DateTime.now();
                            final currentTitle = '${_monthNames[now.month - 1]} ${now.year}';
                            return Text(
                              currentTitle,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            );
                          }),
                        ),

                        // Weekday headers
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildWeekdayHeader('Mon'),
                            _buildWeekdayHeader('Tue'),
                            _buildWeekdayHeader('Wed'),
                            _buildWeekdayHeader('Thu'),
                            _buildWeekdayHeader('Fri'),
                            _buildWeekdayHeader('Sat'),
                            _buildWeekdayHeader('Sun'),
                          ],
                        ),

                        SizedBox(height: 15),

                        // Calendar days (current)
                        Builder(builder: (context) {
                          final now = DateTime.now();
                          final days = _daysInMonth(now.year, now.month);
                          final offset = _firstWeekdayOffset(now.year, now.month);
                          return _buildCalendarGrid(days, now.day, leadingEmpty: offset);
                        }),
                      ],
                    ),
                  ),
                ),

                // Previous month calendar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 8, bottom: 8),
                        child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                      ),
                    ],
                  ),
              child: Column(
                children: [
                        // Month header (previous)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Builder(builder: (context) {
                            final now = DateTime.now();
                            final prev = DateTime(now.year, now.month - 1, 1);
                            final title = '${_monthNames[prev.month - 1]} ${prev.year}';
                            return Text(
                              title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                              ),
                            );
                          }),
                        ),

                        // Weekday headers
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildWeekdayHeader('Mon'),
                            _buildWeekdayHeader('Tue'),
                            _buildWeekdayHeader('Wed'),
                            _buildWeekdayHeader('Thu'),
                            _buildWeekdayHeader('Fri'),
                            _buildWeekdayHeader('Sat'),
                            _buildWeekdayHeader('Sun'),
                          ],
                        ),

                        SizedBox(height: 15),

                        // Calendar days (previous month – no highlight)
                        Builder(builder: (context) {
                          final now = DateTime.now();
                          final prev = DateTime(now.year, now.month - 1, 1);
                          final days = _daysInMonth(prev.year, prev.month);
                          final offset = _firstWeekdayOffset(prev.year, prev.month);
                          return _buildCalendarGrid(days, null, leadingEmpty: offset);
                        }),
                      ],
                    ),
                  ),
                ),

                // Add space at the bottom
                SizedBox(height: 90),
              ],
            ),
                          ),
                        ),
                      ),
    );
  }

  Widget _buildWeekdayHeader(String day) {
    return Text(
      day,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.black,
      ),
    );
  }

  Widget _buildCalendarGrid(int daysInMonth, int? highlightDay,
      {int leadingEmpty = 0}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: leadingEmpty + daysInMonth,
      itemBuilder: (context, index) {
        if (index < leadingEmpty) {
          return const SizedBox.shrink();
        }
        final day = index - leadingEmpty + 1;
        return _buildCalendarDay(day, isHighlighted: day == highlightDay);
      },
    );
  }

  Widget _buildCalendarDay(int day, {bool isHighlighted = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: isHighlighted
            ? Border.all(color: Color(0xFFDADADA), width: 1.875)
            : null,
        shape: BoxShape.circle,
      ),
      child: Center(
                          child: Text(
          day.toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
