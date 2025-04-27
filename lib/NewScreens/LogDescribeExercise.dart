import 'package:flutter/material.dart';
import 'SaveWorkout.dart';

class LogDescribeExercise extends StatefulWidget {
  const LogDescribeExercise({Key? key}) : super(key: key);

  @override
  State<LogDescribeExercise> createState() => _LogDescribeExerciseState();
}

class _LogDescribeExerciseState extends State<LogDescribeExercise> {
  final TextEditingController _exerciseController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  
  String? selectedDistance;
  String? selectedTime;
  bool showIntensity = false;
  double intensityValue = 0.0;

  final List<String> distances = ['1 km', '5 km', '10 km', '15 km'];
  final List<String> times = ['15 min', '30 min', '60 min', '90 min'];

  String getIntensityLabel() {
    if (intensityValue <= 0.2) return 'Extremely Light';
    if (intensityValue <= 0.4) return 'Light';
    if (intensityValue <= 0.6) return 'Moderate';
    if (intensityValue <= 0.8) return 'Difficult';
    return 'Maximum Effort';
  }

  String getIntensityDescription() {
    if (intensityValue <= 0.2) return 'Very gentle movement, barely felt like exercise.';
    if (intensityValue <= 0.4) return 'Easy activity, could maintain for hours.';
    if (intensityValue <= 0.6) return 'Breathing heavily but can hold a conversation.';
    if (intensityValue <= 0.8) return 'Difficult to speak, sweating heavily.';
    return 'All-out effort, cannot maintain for long.';
  }

  @override
  void dispose() {
    _exerciseController.dispose();
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
                      flexibleSpace: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 29)
                            .copyWith(top: 16, bottom: 8.5),
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                'Describe Exercise',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              child: IconButton(
                                icon: Icon(Icons.arrow_back, color: Colors.black, size: 24),
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Divider line
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 29),
                    height: 0.5,
                    color: Color(0xFFBDBDBD),
                  ),
                  SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: 29),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 20),
                          // Exercise Section
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/add.png',
                                width: 24,
                                height: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Exercise',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          // Exercise TextField
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
                                controller: _exerciseController,
                                keyboardType: TextInputType.text,
                                cursorColor: Colors.black,
                                cursorWidth: 1.2,
                                textAlign: TextAlign.left,
                                textAlignVertical: TextAlignVertical.center,
                                style: TextStyle(
                                  fontSize: 13.6,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.black,
                                  fontFamily: '.SF Pro Display',
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Swimming, football, cycling etc',
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
                          
                          // Distance/Intensity Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    showIntensity = false;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/images/Distance.png',
                                      width: 24,
                                      height: 24,
                                      color: !showIntensity ? Colors.black : Colors.grey,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Distance',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                        color: !showIntensity ? Colors.black : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    showIntensity = true;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/images/intensity.png',
                                      width: 24,
                                      height: 24,
                                      color: showIntensity ? Colors.black : Colors.grey,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Intensity',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                        color: showIntensity ? Colors.black : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 15),
                          
                          // Intensity Card or Distance Chips based on selection
                          if (showIntensity)
                            Container(
                              padding: EdgeInsets.all(15),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    getIntensityLabel(),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    getIntensityDescription(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(height: 15),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 2,
                                      activeTrackColor: Colors.black,
                                      inactiveTrackColor: Colors.grey[300],
                                      thumbColor: Colors.black,
                                      overlayColor: Colors.black.withOpacity(0.1),
                                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: RoundSliderOverlayShape(overlayRadius: 20),
                                    ),
                                    child: Slider(
                                      value: intensityValue,
                                      onChanged: (value) {
                                        setState(() {
                                          intensityValue = value;
                                        });
                                      },
                                      min: 0.0,
                                      max: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: [
                                // Distance Chips
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
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
                                            _distanceController.text = distance.replaceAll(' km', '');
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
                              ],
                            ),
                          
                          SizedBox(height: 20),
                          
                          // Time Section
                          Row(
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
                          SizedBox(height: 15),
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
                                        _timeController.text = time.replaceAll(' min', '');
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SaveWorkout()),
                      );
                    },
                    child: Text(
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