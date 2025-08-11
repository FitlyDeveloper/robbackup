import 'package:flutter/material.dart';
import 'SaveWorkout.dart';

class LogRunning extends StatefulWidget {
  final double? initialDistance; // in km
  final int? initialTime; // in minutes
  final String? initialTitle; // for editing existing runs
  final String? runId; // ID of the run being edited (null for new runs)
  
  const LogRunning({
    Key? key, 
    this.initialDistance, 
    this.initialTime,
    this.initialTitle,
    this.runId,
  }) : super(key: key);

  @override
  State<LogRunning> createState() => _LogRunningState();
}

class _LogRunningState extends State<LogRunning> {
  final TextEditingController _distanceController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  
  String? selectedDistance;
  String? selectedTime;

  final List<String> distances = ['1 km', '5 km', '10 km', '15 km'];
  final List<String> times = ['15 min', '30 min', '60 min', '90 min'];

  @override
  void initState() {
    super.initState();
    
    // Debug logging for initState
    print('=== LogRunning InitState Debug ===');
    print('Initial distance: ${widget.initialDistance}');
    print('Initial time: ${widget.initialTime}');
    print('Initial title: ${widget.initialTitle}');
    print('Run ID: ${widget.runId}');
    
    // Add listener to distance controller to track changes
    _distanceController.addListener(() {
      print('=== Distance Controller Listener ===');
      print('Controller text changed to: "${_distanceController.text}"');
      print('====================================');
    });
    
    // Pre-fill controllers with initial values if provided
    if (widget.initialDistance != null) {
      _distanceController.text = widget.initialDistance!.toString();
      
      // Check if the initial distance matches any preset button
      String distanceWithUnit = '${widget.initialDistance!.toStringAsFixed(widget.initialDistance! % 1 == 0 ? 0 : 1)} km';
      if (distances.contains(distanceWithUnit)) {
        selectedDistance = distanceWithUnit;
      }
      
      print('Distance controller set to: ${_distanceController.text}');
      print('Selected distance preset: $selectedDistance');
    }
    if (widget.initialTime != null) {
      _timeController.text = widget.initialTime!.toString();
      
      // Check if the initial time matches any preset button
      String timeWithUnit = '${widget.initialTime} min';
      if (times.contains(timeWithUnit)) {
        selectedTime = timeWithUnit;
      }
      
      print('Time controller set to: ${_timeController.text}');
      print('Selected time preset: $selectedTime');
    }
    print('==================================');
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _timeController.dispose();
    super.dispose();
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
          child: Stack(
            children: [
              Column(
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
                                  'Log Running',
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
                  // Divider line
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 29),
                    height: 0.5,
                    color: Color(0xFFBDBDBD),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: 29),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 20),
                          // Distance Section
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/Distance.png',
                                width: 24,
                                height: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Distance',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          // Distance Chips
                          Center(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: distances.map((distance) {
                                return ChoiceChip(
                                  label: Text(
                                    distance,
                                    style: TextStyle(
                                      color: selectedDistance == distance ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  selected: selectedDistance == distance,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      selectedDistance = selected ? distance : null;
                                      if (selected) {
                                        // Extract just the numeric value from the preset (e.g., "10 km" -> "10")
                                        String numericValue = distance.replaceAll(' km', '');
                                        
                                        // Update the controller text
                                        _distanceController.text = numericValue;
                                        
                                        // Debug logging for preset selection
                                        print('=== Preset Distance Debug ===');
                                        print('Preset selected: $distance');
                                        print('Numeric value extracted: $numericValue');
                                        print('Text controller updated to: ${_distanceController.text}');
                                        print('=============================');
                                      } else {
                                        // Clear the text field when preset is deselected
                                        _distanceController.clear();
                                        print('=== Preset Distance Debug ===');
                                        print('Preset deselected, text field cleared');
                                        print('=============================');
                                      }
                                    });
                                  },
                                  backgroundColor: Colors.white,
                                  selectedColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: selectedDistance == distance ? Colors.transparent : Colors.grey[300]!,
                                    ),
                                  ),
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  showCheckmark: false,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ),
                          SizedBox(height: 15),
                          // Distance TextField
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.grey[300]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: TextField(
                                controller: _distanceController,
                                keyboardType: TextInputType.number,
                                cursorColor: Colors.black,
                                cursorWidth: 1.2,
                                textAlign: TextAlign.left,
                                textAlignVertical: TextAlignVertical.center,
                                onChanged: (value) {
                                  // Clear selected preset when user types manually
                                  if (selectedDistance != null) {
                                    setState(() {
                                      selectedDistance = null;
                                    });
                                  }
                                  
                                  // Debug logging for manual input
                                  print('=== Manual Distance Input Debug ===');
                                  print('Manual input value: "$value"');
                                  print('Text controller text: "${_distanceController.text}"');
                                  print('Selected distance preset: $selectedDistance');
                                  print('=====================================');
                                },
                                style: TextStyle(
                                  fontSize: 13.6,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black,
                                  fontFamily: '.SF Pro Display',
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Kilometers',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13.6,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: '.SF Pro Display',
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 15),
                                  isCollapsed: true,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 20),
                          
                          // Time Section
                          Padding(
                            padding: EdgeInsets.only(top: 29),
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/images/timeicon.png',
                                  width: 24,
                                  height: 24,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Time',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          // Time Chips
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: times.map((time) {
                                return ChoiceChip(
                                  label: Text(
                                    time,
                                    style: TextStyle(
                                      color: selectedTime == time ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  selected: selectedTime == time,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      selectedTime = selected ? time : null;
                                      if (selected) {
                                        // Extract just the numeric value from the preset (e.g., "60 min" -> "60")
                                        String numericValue = time.replaceAll(' min', '');
                                        _timeController.text = numericValue;
                                      }
                                    });
                                  },
                                  backgroundColor: Colors.white,
                                  selectedColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: selectedTime == time ? Colors.transparent : Colors.grey[300]!,
                                    ),
                                  ),
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  showCheckmark: false,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ),
                          SizedBox(height: 15),
                          // Time TextField
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.grey[300]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: TextField(
                                controller: _timeController,
                                keyboardType: TextInputType.number,
                                cursorColor: Colors.black,
                                cursorWidth: 1.2,
                                textAlign: TextAlign.left,
                                textAlignVertical: TextAlignVertical.center,
                                onChanged: (value) {
                                  // Clear selected preset when user types manually
                                  if (selectedTime != null) {
                                    setState(() {
                                      selectedTime = null;
                                    });
                                  }
                                },
                                style: TextStyle(
                                  fontSize: 13.6,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black,
                                  fontFamily: '.SF Pro Display',
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Minutes',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13.6,
                                    fontWeight: FontWeight.w400,
                                    fontFamily: '.SF Pro Display',
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 15),
                                  isCollapsed: true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // White box at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.of(context).size.height * 0.148887,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.zero,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                ),
              ),

              // Add button
              Positioned(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).size.height * 0.06,
                child: Container(
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.0689,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: TextButton(
                    onPressed: () {
                      // Get the distance and time values from user input
                      // Clean the distance text to ensure proper parsing
                      String cleanDistanceText = _distanceController.text.trim();
                      double distanceInKm = double.tryParse(cleanDistanceText) ?? 0.0;
                      int timeInMinutes = int.tryParse(_timeController.text.trim()) ?? 0;
                      
                      // Convert distance from kilometers to meters for storage
                      double distanceInMeters = distanceInKm * 1000;
                      
                      // Enhanced debug logging to verify the values
                      print('=== LogRunning Debug ===');
                      print('LogRunning - Raw distance controller text: "${_distanceController.text}"');
                      print('LogRunning - Cleaned distance text: "$cleanDistanceText"');
                      print('LogRunning - Parsed distance in km: $distanceInKm');
                      print('LogRunning - Converted distance in meters: $distanceInMeters');
                      print('LogRunning - Selected distance preset: $selectedDistance');
                      print('LogRunning - Time controller text: "${_timeController.text}"');
                      print('LogRunning - Parsed time in minutes: $timeInMinutes');
                      print('LogRunning - Time in seconds: ${timeInMinutes * 60}');
                      print('=======================');
                      
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SaveWorkout(
                          duration: timeInMinutes * 60, // Convert to seconds
                          volume: 0, 
                          prs: 0, 
                          workoutType: 'running',
                          distance: distanceInMeters, // Store in meters
                          initialTitle: widget.initialTitle, // Pass the initial title for editing
                          runId: widget.runId, // Pass the run ID for editing existing runs
                        )),
                      );
                    },
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                        color: Colors.white,
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
} 