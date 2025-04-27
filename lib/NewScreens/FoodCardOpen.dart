import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../Features/codia/codia_page.dart';

// Custom scroll physics optimized for mouse wheel
class SlowScrollPhysics extends ScrollPhysics {
  const SlowScrollPhysics({super.parent});

  @override
  SlowScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SlowScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // Only slow down mouse wheel scrolling, speed up touch scrolling
    if (offset.abs() < 10) {
      // Mouse wheel typically produces smaller offset values
      return offset * 0.3; // Slow down mouse wheel by 70%
    }
    return offset * 1.5; // Speed up touch scrolling by 50%
  }

  @override
  double get minFlingVelocity => super.minFlingVelocity;

  @override
  double get maxFlingVelocity =>
      super.maxFlingVelocity * 1.2; // Increased fling velocity by 20%
}

class FoodCardOpen extends StatefulWidget {
  const FoodCardOpen({super.key});

  @override
  State<FoodCardOpen> createState() => _FoodCardOpenState();
}

class _FoodCardOpenState extends State<FoodCardOpen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isBookmarked = false; // Track bookmark state
  int _counter = 1; // Counter for +/- buttons
  late AnimationController _bookmarkController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnimation;

  @override
  void initState() {
    super.initState();

    // Bookmark animations - simplified
    _bookmarkController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _bookmarkScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(
      CurvedAnimation(
        parent: _bookmarkController,
        curve: Curves.easeOutBack,
      ),
    );

    // Like animations - simplified
    _likeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _likeScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(
      CurvedAnimation(
        parent: _likeController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _bookmarkController.dispose();
    _likeController.dispose();
    super.dispose();
  }

  void _handleBack() {
    Navigator.of(context).pop();
  }

  // Method to increment counter with maximum limit
  void _incrementCounter() {
    setState(() {
      if (_counter < 10) {
        _counter++;
      }
    });
  }

  // Method to decrement counter with minimum limit
  void _decrementCounter() {
    setState(() {
      if (_counter > 1) {
        _counter--;
      }
    });
  }

  // Method to toggle bookmark state with animation
  void _toggleBookmark() {
    setState(() {
      _isBookmarked = !_isBookmarked;
      _bookmarkController.reset();
      _bookmarkController.forward();
    });
  }

  // Method to toggle like state with animation
  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeController.reset();
      _likeController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: Color(0xFFDADADA),
      // Use a stack for better layout control
      body: Stack(
        children: [
          // Scrollable content with extra slow physics for mouse wheel
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              physics: SlowScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gray image header with back button on it
                  Container(
                    height: MediaQuery.of(context).size.width,
                    color: Color(0xFFDADADA),
                    child: Stack(
                      children: [
                        // Meal image
                        Center(
                          child: Image.asset(
                            'assets/images/meal1.png',
                            width: 48,
                            height: 48,
                          ),
                        ),
                        // Back button inside the scrollable area
                        Positioned(
                          top: statusBarHeight + 16,
                          left: 16,
                          child: GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => CodiaPage())),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: Icon(Icons.arrow_back,
                                  color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                        // Share and more buttons
                        Positioned(
                          top: statusBarHeight + 16,
                          right: 16,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {},
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Image.asset(
                                    'assets/images/share.png',
                                    width: 24,
                                    height: 24,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {},
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Image.asset(
                                    'assets/images/more.png',
                                    width: 24,
                                    height: 24,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // White rounded container with gradient
                  Transform.translate(
                    offset: Offset(0, -40), // Move up to create overlap
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(40),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.4, 1],
                          colors: [
                            Color(0xFFFFFFFF),
                            Color(0xFFFFFFFF),
                            Color(0xFFEBEBEB),
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          // Add 20px gap at top of white container
                          SizedBox(height: 20),

                          // Time and interaction buttons
                          Padding(
                            padding: const EdgeInsets.fromLTRB(29, 0, 29, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Left side: Bookmark and time
                                Row(
                                  children: [
                                    // Bookmark button with enhanced animation
                                    GestureDetector(
                                      onTap: _toggleBookmark,
                                      child: AnimatedBuilder(
                                        animation: _bookmarkController,
                                        builder: (context, child) {
                                          return Transform.scale(
                                            scale:
                                                _bookmarkScaleAnimation.value,
                                            child: Image.asset(
                                              _isBookmarked
                                                  ? 'assets/images/bookmarkfilled.png'
                                                  : 'assets/images/bookmark.png',
                                              width: 24,
                                              height: 24,
                                              color: _isBookmarked
                                                  ? Color(0xFFFFC300)
                                                  : Colors.black,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    // Time
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Color(0xFFF2F2F2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '12:07',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),

                                // Right side: Counter with minus and plus buttons
                                Row(
                                  children: [
                                    // Minus button
                                    GestureDetector(
                                      onTap: _decrementCounter,
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                        child: Center(
                                          child: Image.asset(
                                            'assets/images/minus.png',
                                            width: 24,
                                            height: 24,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Counter with smaller width
                                    Container(
                                      width:
                                          24, // Reduced from 40 to bring icons closer
                                      child: Center(
                                        child: Text(
                                          '$_counter',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Plus button
                                    GestureDetector(
                                      onTap: _incrementCounter,
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                        child: Center(
                                          child: Image.asset(
                                            'assets/images/plus.png',
                                            width: 24,
                                            height: 24,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Title and description with adjusted padding
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title and subtitle area with 14px top spacing
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 29, right: 29, top: 14, bottom: 0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Delicious Cake',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Rusty Pelican is so good',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    // Add 20px gap between subtitle and divider
                                    SizedBox(height: 20),
                                  ],
                                ),
                              ),

                              // Divider with correct color and margins
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
                                child: Container(
                                  height: 0.5,
                                  color: Color(0xFFBDBDBD),
                                ),
                              ),

                              // Social sharing buttons
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 48, vertical: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Like button area (left section)
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: _toggleLike,
                                          child: AnimatedBuilder(
                                            animation: _likeController,
                                            builder: (context, child) {
                                              return Transform.scale(
                                                scale:
                                                    _likeScaleAnimation.value,
                                                child: Image.asset(
                                                  _isLiked
                                                      ? 'assets/images/likefilled.png'
                                                      : 'assets/images/like.png',
                                                  width: 24,
                                                  height: 24,
                                                  color: Colors.black,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '2',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Comment button (center section)
                                    Row(
                                      children: [
                                        Image.asset(
                                          'assets/images/comment.png',
                                          width: 24,
                                          height: 24,
                                          color: Colors.black,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '2',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Share button (right section)
                                    Image.asset(
                                      'assets/images/share.png',
                                      width: 24,
                                      height: 24,
                                      color: Colors.black,
                                    ),
                                  ],
                                ),
                              ),

                              // Divider with correct color and margins
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
                                child: Container(
                                  height: 0.5,
                                  color: Color(0xFFBDBDBD),
                                ),
                              ),
                            ],
                          ),

                          // Rest of the content
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Exact 20px gap between divider and calories
                              SizedBox(height: 20),

                              // Calories and macros card
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
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
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Calories circle
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Circle image instead of custom painted progress
                                          Transform.translate(
                                            offset: Offset(0, -3.9),
                                            child: ColorFiltered(
                                              colorFilter: ColorFilter.mode(
                                                Colors.black,
                                                BlendMode.srcIn,
                                              ),
                                              child: Image.asset(
                                                'assets/images/circle.png',
                                                width: 130,
                                                height: 130,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          // Calories text
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '500',
                                                style: TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                              Text(
                                                'Calories',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.normal,
                                                  color: Colors.black,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 5),

                                      // Macros
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          _buildMacro('Protein', '30g',
                                              Color(0xFFD7C1FF)),
                                          _buildMacro(
                                              'Fat', '32g', Color(0xFFFFD8B1)),
                                          _buildMacro('Carbs', '125g',
                                              Color(0xFFB1EFD8)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Gap between calorie box and health score - changed to 15px
                              SizedBox(height: 15),

                              // Health Score
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 20),
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
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.only(
                                            left: 60, right: 12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  'Health Score',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Spacer(),
                                                Text(
                                                  '8/10',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 8),
                                            Container(
                                              width: double.infinity,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Color(0xFFDADADA),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: Container(
                                                  width: double.infinity,
                                                  child: FractionallySizedBox(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    widthFactor: 0.8,
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Color(0xFF75D377),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: -4,
                                        top: -5,
                                        bottom: -5,
                                        child: Image.asset(
                                          'assets/images/heartpink.png',
                                          width: 45,
                                          height: 45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Gap between health score and ingredients label - set to 20px
                              SizedBox(height: 20),

                              // Ingredients
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ingredients',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    // Gap between Ingredients label and boxes - set to 20px
                                    SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildIngredient(
                                            'Cheesecake', '100g', '300 kcal'),
                                        _buildIngredient(
                                            'Berries', '20g', '10 kcal'),
                                      ],
                                    ),
                                    // Gap between rows of ingredient boxes - set to 15px
                                    SizedBox(height: 15),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _buildIngredient(
                                            'Jam', '10g', '20 kcal'),
                                        // Wrap the Add box in a Stack to overlay the icon
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // This handles the box structure and "Add" text alignment
                                            _buildIngredient('Add', '', ''),
                                            // Add the icon as a separate overlay, centered, and pushed down
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top:
                                                      20.0), // Moved down another 10px (was 10)
                                              child: Image.asset(
                                                'assets/images/add.png',
                                                width:
                                                    29.0, // Increased size by 10% (was 26.4)
                                                height:
                                                    29.0, // Increased size by 10% (was 26.4)
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Set exact 20px spacing between Ingredients section and More label
                              SizedBox(height: 20),

                              // More options
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 29),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'More',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    // Set exact 20px spacing between More label and buttons
                                    SizedBox(height: 20),
                                    _buildMoreOption(
                                        'In-Depth Nutrition', 'nutrition.png'),
                                    _buildMoreOption(
                                        'Fix Manually', 'pencilicon.png'),
                                    _buildMoreOption('Fix with AI', 'bulb.png'),
                                  ],
                                ),
                              ),

                              // Extra space at the bottom to account for the Save button
                              SizedBox(height: 120),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // White box at bottom - EXACTLY as in signin.dart
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.148887,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),

          // Save button - EXACTLY as in signin.dart
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
                onPressed: () {},
                style: ButtonStyle(
                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    fontFamily: '.SF Pro Display',
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacro(String name, String amount, Color color) {
    return Column(
      children: [
        Text(name, style: TextStyle(fontSize: 12)),
        SizedBox(height: 4),
        Container(
          width: 80,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 1.0, // Changed from 0.5 to 1.0 to fill entirely
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(amount,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildIngredient(String name, String amount, String calories) {
    final boxWidth = (MediaQuery.of(context).size.width - 78) / 2;
    return Container(
      width: boxWidth,
      height: 110,
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
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SF Pro Display',
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'SF Pro Display',
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 10),
              Text(
                calories,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'SF Pro Display',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOption(String title, String iconAsset) {
    // Base icon size for pencilicon.png
    double baseIconSize = 25.0;
    // Calculate 10% larger size for the other two icons
    double largerIconSize = baseIconSize * 1.1; // 27.5px

    // Determine the size for the current icon
    double iconSize = (iconAsset == 'nutrition.png' || iconAsset == 'bulb.png')
        ? largerIconSize
        : baseIconSize;

    return Container(
      margin: EdgeInsets.only(bottom: 15), // Set gap between boxes to 15px
      padding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
      width: double.infinity,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Add 40px padding before the icon alignment container (35 + 5)
          SizedBox(width: 40),
          // Container to ensure icons align vertically and have space
          SizedBox(
            width: 40, // Keep this width consistent for alignment
            child: Align(
              alignment:
                  Alignment.centerLeft, // Align icon to the left of this box
              child: SizedBox(
                width: iconSize, // Use the calculated size
                height: iconSize, // Use the calculated size
                child: Image.asset(
                  'assets/images/$iconAsset',
                  width: iconSize, // Apply calculated width
                  height: iconSize, // Apply calculated height
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16, // Matches Health Score text size
                  fontWeight: FontWeight.normal,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
                softWrap: false, // Prevent text from wrapping to the next line
                overflow: TextOverflow
                    .visible, // Allow text to overflow container bounds
              ),
            ),
          ),
          // Adjust balance spacing for the added left padding
          SizedBox(width: 88), // (40 padding + 40 icon area + 8 gap)
        ],
      ),
    );
  }
}
