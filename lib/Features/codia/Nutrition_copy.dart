import 'package:flutter/material.dart';

class CodiaPage extends StatefulWidget {
  CodiaPage({super.key});

  @override
  State<StatefulWidget> createState() => _CodiaPage();
}

class _CodiaPage extends State<CodiaPage> {
  // Define color constants with the specified hex codes
  final Color yellowColor = Color(0xFFF3D960);
  final Color redColor = Color(0xFFDA7C7C);
  final Color greenColor = Color(0xFF78C67A);

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
                      // Back button
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.black, size: 24),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),

                      // In-Depth Nutrition title
                      Text(
                        'In-Depth Nutrition',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro',
                          color: Colors.black,
                        ),
                      ),

                      // Empty space to balance the header
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

                SizedBox(height: 20),

                // Vitamins Section
                _buildNutrientSection(
                  title: "Vitamins",
                  count: "0/13",
                  nutrients: [
                    NutrientInfo(
                        name: "Vitamin A",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: greenColor),
                    NutrientInfo(
                        name: "Vitamin C",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin D",
                        value: "0/",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor,
                        hasInfo: true),
                    NutrientInfo(
                        name: "Vitamin E",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin K",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Vitamin B1",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin B2",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Vitamin B3",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin B5",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Vitamin B6",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin B7",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Vitamin B9",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                    NutrientInfo(
                        name: "Vitamin B12",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: redColor),
                  ],
                ),

                SizedBox(height: 20),

                // Minerals Section
                _buildNutrientSection(
                  title: "Minerals",
                  count: "0/15",
                  nutrients: [
                    NutrientInfo(
                        name: "Calcium",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Chloride",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Chromium",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Copper",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Fluoride",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Iodine",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Iron",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Magnesium",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Manganese",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Molybdenum",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Phosphorus",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Potassium",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Selenium",
                        value: "0/0 mcg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Sodium",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Zinc",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                  ],
                ),

                SizedBox(height: 20),

                // Other Nutrients Section
                _buildNutrientSection(
                  title: "Other",
                  count: "0/8",
                  nutrients: [
                    NutrientInfo(
                        name: "Fiber",
                        value: "0/0 g",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Cholesterol",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Omega-3",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Omega-6",
                        value: "0/0 g",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Sodium",
                        value: "0/0 mg",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Sugar",
                        value: "0/0 g",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                    NutrientInfo(
                        name: "Saturated Fats",
                        value: "0/0 g",
                        percent: "0%",
                        progress: 0,
                        progressColor: yellowColor),
                  ],
                ),

                // Bottom padding
                SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Class to hold nutrient information
  Widget _buildNutrientSection({
    required String title,
    required String count,
    required List<NutrientInfo> nutrients,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 29),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header section with divider
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Info icon on left
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: Center(
                      child: Text(
                        "i",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro',
                        ),
                      ),
                    ),
                  ),

                  // Title in center
                  Expanded(
                    child: Center(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro',
                        ),
                      ),
                    ),
                  ),

                  // Counter on right
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                      fontFamily: 'SF Pro',
                    ),
                  ),
                ],
              ),
            ),

            // Divider line under header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.withOpacity(0.3),
              ),
            ),

            // Nutrients list
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: nutrients.map((nutrient) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nutrient name and values row
                      Row(
                        children: [
                          // Name
                          Expanded(
                            flex: 2,
                            child: Text(
                              nutrient.name,
                              style: TextStyle(
                                fontSize: 17,
                                color: Colors.black,
                                fontFamily: 'SF Pro',
                              ),
                            ),
                          ),
                          // Value with aligned slash
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                // Use RichText to align the slash character
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'SF Pro',
                                      color: Colors.black,
                                    ),
                                    children:
                                        _formatValueWithSlash(nutrient.value),
                                  ),
                                ),
                                if (nutrient.hasInfo)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Image.asset(
                                      'assets/images/questionmark.png',
                                      width: 15,
                                      height: 15,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Percentage
                          Text(
                            nutrient.percent,
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'SF Pro',
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 6),

                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: nutrient.progress,
                          minHeight: 8,
                          backgroundColor: Colors.grey.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              nutrient.progressColor),
                        ),
                      ),

                      SizedBox(height: 12),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to format the value with aligned slash
  List<TextSpan> _formatValueWithSlash(String value) {
    // If the value contains a slash, split it and align
    if (value.contains('/')) {
      List<String> parts = value.split('/');
      String leftPart = parts[0];
      String rightPart = parts.length > 1 ? parts[1] : '';

      return [
        TextSpan(
          text: leftPart,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
        TextSpan(
          text: '/',
          style: TextStyle(
            fontSize: 14, // Increased by 1
            fontFamily: 'SF Pro',
          ),
        ),
        TextSpan(
          text: rightPart,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
      ];
    } else {
      // If no slash, just return the value as is
      return [
        TextSpan(
          text: value,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
      ];
    }
  }
}

// Simple class to hold nutrient info
class NutrientInfo {
  final String name;
  final String value;
  final String percent;
  final double progress;
  final Color progressColor;
  final bool hasInfo;

  NutrientInfo({
    required this.name,
    required this.value,
    required this.percent,
    required this.progress,
    required this.progressColor,
    this.hasInfo = false,
  });
}
