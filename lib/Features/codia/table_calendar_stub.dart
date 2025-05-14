import 'package:flutter/material.dart';

// Stub implementation of TableCalendar to fix build
class TableCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final Function(DateTime, DateTime)? onDaySelected;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final Function(CalendarFormat)? onFormatChanged;

  const TableCalendar({
    Key? key,
    required this.focusedDay,
    required this.firstDay,
    required this.lastDay,
    this.onDaySelected,
    this.selectedDay,
    required this.calendarFormat,
    this.onFormatChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          "Calendar temporarily unavailable",
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

// Stub enum for CalendarFormat
enum CalendarFormat { month, twoWeeks, week }
