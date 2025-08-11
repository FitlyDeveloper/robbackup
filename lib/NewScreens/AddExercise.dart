import 'package:flutter/material.dart';
import 'package:grouped_list/grouped_list.dart';
import 'ExerciseInfo.dart';
import '../services/favorites_service.dart';
import '../WorkoutSession/WeightLiftingActive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CodiaPage extends StatefulWidget {
  CodiaPage({super.key});

  @override
  State<StatefulWidget> createState() => _CodiaPage();
}

class _CodiaPage extends State<CodiaPage> {
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<int> _selectedIndices = {};
  String? _selectedMuscleGroup;
  bool _showFavorites = false;
  List<Map<String, String>> _favorites = [];

  @override
  void initState() {
    super.initState();
    exercises.sort((a, b) => a.name.compareTo(b.name));
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteKeys = prefs.getKeys().where((key) => key.startsWith('favorite_'));
    setState(() {
      _favorites = favoriteKeys.where((key) {
        final isFavorite = prefs.getBool(key) ?? false;
        return isFavorite;
      }).map((key) {
        final name = key.replaceFirst('favorite_', '');
        final exercise = exercises.firstWhere((ex) => ex.name == name);
        return {
          'name': exercise.name,
          'muscle': exercise.muscle,
        };
      }).toList();
    });
  }

  void _toggleFavorite(Exercise exercise) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'favorite_${exercise.name}';
    final isFavorite = prefs.getBool(key) ?? false;
    await prefs.setBool(key, !isFavorite);
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredExercises = exercises.where((ex) {
      final matchesSearch = _searchQuery.isEmpty || 
          ex.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesMuscle = _selectedMuscleGroup == null || 
          _selectedMuscleGroup == 'All muscles' ||
          ex.muscle.toLowerCase() == _selectedMuscleGroup!.toLowerCase();
      return matchesSearch && matchesMuscle;
    }).toList();

    final displayedExercises = _showFavorites
        ? exercises.where((ex) => _favorites.any((fav) =>
            fav['name'] == ex.name && fav['muscle'] == ex.muscle)).toList()
        : filteredExercises.where((ex) => !_favorites.any((fav) =>
            fav['name'] == ex.name && fav['muscle'] == ex.muscle)).toList();

    return Material(
      color: Colors.white,
      child: SizedBox(
        width: 393,
        height: 852,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              width: 393,
              top: 0,
              height: 852,
              child: Image.asset(
                'assets/images/background4.jpg',
                width: 393,
                height: 852,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 16, bottom: 8.5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                          Text(
                            'Add Exercise',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'SF Pro Display',
                              decoration: TextDecoration.none,
                            ),
                          ),
                          SizedBox(width: 24),
                        ],
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 29),
                      height: 0.5,
                      color: Color(0xFFBDBDBD),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 31,
              width: 331,
              top: 119,
              height: 40,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 331,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xffffffff),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x14000000),
                          offset: Offset(0, 3),
                          blurRadius: 8)
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 12),
                      Image.asset(
                        'assets/images/Search.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.cover,
                        color: Colors.black.withOpacity(0.5),
                        colorBlendMode: BlendMode.srcIn,
                        errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.search,
                            color: Colors.grey.withOpacity(0.5),
                            size: 18),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            textSelectionTheme: TextSelectionThemeData(
                              selectionColor: Colors.grey[300],
                              selectionHandleColor: Colors.grey[300],
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              fontSize: 13.6,
                              color: const Color(0xFF000000),
                              fontFamily: 'SFProDisplay-Regular',
                              fontWeight: FontWeight.normal,
                            ),
                            cursorColor: Colors.black,
                            cursorWidth: 1.2,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search Exercise',
                              hintStyle: TextStyle(
                                decoration: TextDecoration.none,
                                fontSize: 13.6,
                                color: const Color(0x7f000000),
                                fontFamily: 'SFProDisplay-Regular',
                                fontWeight: FontWeight.normal,
                              ),
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 31,
              right: 29,
              top: 176,
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _showFavorites = !_showFavorites;
                        });
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: _showFavorites ? Colors.black : const Color(0xffffffff),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                offset: Offset(0, 3),
                                blurRadius: 8)
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Favorites',
                            style: TextStyle(
                              decoration: TextDecoration.none,
                              fontSize: 17,
                              color: _showFavorites ? Colors.white : const Color(0xff000000),
                              fontFamily: 'SFProDisplay-Regular',
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                          ),
                          builder: (context) => _buildMuscleGroupPopup(context),
                        );
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: _selectedMuscleGroup != null ? Colors.black : const Color(0xffffffff),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                offset: Offset(0, 3),
                                blurRadius: 8)
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _selectedMuscleGroup ?? 'All muscles',
                            style: TextStyle(
                              fontSize: 17,
                              color: _selectedMuscleGroup != null ? Colors.white : const Color(0xff000000),
                              fontFamily: 'SFProDisplay-Regular',
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_selectedMuscleGroup != null) ...[
                    SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            offset: Offset(0, 3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _selectedMuscleGroup = null;
                            });
                          },
                          child: Center(
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 31,
              width: 73,
              top: 243,
              height: 20,
              child: Text(
                'Exercises',
                textAlign: TextAlign.left,
                style: TextStyle(
                    decoration: TextDecoration.none,
                    fontSize: 17,
                    color: const Color(0x7f000000),
                    fontFamily: 'SFProDisplay-Regular',
                    fontWeight: FontWeight.normal),
                maxLines: 9999,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 270,
              bottom: 0,
              child: ListView.builder(
                padding: EdgeInsets.only(top: 10, bottom: 100),
                itemCount: displayedExercises.length,
                itemBuilder: (context, index) {
                  final ex = displayedExercises[index];
                  final isSelected = _selectedIndices.contains(index);
                  final isFavorite = _favorites.any((fav) =>
                      fav['name'] == ex.name && fav['muscle'] == ex.muscle);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedIndices.contains(index)) {
                          _selectedIndices.remove(index);
                        } else {
                          _selectedIndices.add(index);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 31, vertical: 8),
                      child: Container(
                        width: 331,
                        height: 62,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x14000000),
                                offset: Offset(0, 3),
                                blurRadius: 8),
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
                                color: isSelected
                                    ? Colors.white.withOpacity(0.15)
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Image.asset(
                                  'assets/images/dumbbell.png',
                                  width: 24,
                                  height: 24,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey[700],
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
                                  Row(
                                    children: [
                                      Text(
                                        ex.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.normal,
                                          fontSize: 15,
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.black,
                                          fontFamily: 'SFProDisplay-Regular',
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      if (isFavorite)
                                        Padding(
                                          padding: EdgeInsets.only(left: 4),
                                          child: Image.asset(
                                            'assets/images/bookmarkfilled.png',
                                            width: 16,
                                            height: 16,
                                            color: isSelected ? Colors.white : Color(0xFFFFC300),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    ex.muscle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isSelected
                                          ? Colors.white70
                                          : Color(0x7f000000),
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
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ExerciseInfo(
                                      exerciseName: ex.name,
                                      muscle: ex.muscle,
                                    ),
                                  ),
                                );
                                _loadFavorites();
                              },
                              child: Image.asset(
                                'assets/images/CircleMenu.png',
                                width: 18,
                                height: 18,
                                color: isSelected ? Colors.white : null,
                                fit: BoxFit.cover,
                              ),
                            ),
                            SizedBox(width: 13),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_selectedIndices.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: MediaQuery.of(context).size.height * 0.0689,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: TextButton(
                      onPressed: () {
                        final selectedExercises = _selectedIndices
                            .map((i) => displayedExercises[i])
                            .toList();
                        Navigator.pop(context, selectedExercises);
                      },
                      child: Text(
                        'Add ${_selectedIndices.length} ${_selectedIndices.length == 1 ? 'exercise' : 'exercises'}',
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMuscleGroupPopup(BuildContext context) {
    final muscleGroups = [
      {'name': 'All muscles', 'icon': Icons.grid_view},
      {'name': 'Chest', 'icon': Icons.image},
      {'name': 'Back', 'icon': Icons.image},
      {'name': 'Legs', 'icon': Icons.image},
      {'name': 'Shoulders', 'icon': Icons.image},
      {'name': 'Arms', 'icon': Icons.image},
      {'name': 'Core', 'icon': Icons.image},
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Muscle Group',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            ...muscleGroups.map((group) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    setState(() {
                      _selectedMuscleGroup = group['name'] as String;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 18, right: 18),
                          child: Icon(
                            group['icon'] as IconData,
                            size: 40,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          group['name'] as String,
                          style: TextStyle(
                            fontSize: 17,
                            fontFamily: 'SFProDisplay-Regular',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Add Exercise data model
class Exercise {
  final String name;
  final String muscle;
  final String equipment;
  Exercise({required this.name, required this.muscle, required this.equipment});
}

final List<Exercise> exercises = [
  Exercise(
      name: 'Bench Press (Barbell)', muscle: 'Chest', equipment: 'Barbell'),
  Exercise(
      name: 'Dumbbell Chest Press', muscle: 'Chest', equipment: 'Dumbbell'),
  Exercise(
      name: 'Incline Bench Press (Barbell)',
      muscle: 'Chest',
      equipment: 'Barbell'),
  Exercise(
      name: 'Incline Dumbbell Press', muscle: 'Chest', equipment: 'Dumbbell'),
  Exercise(name: 'Chest Fly', muscle: 'Chest', equipment: 'Machine'),
  Exercise(name: 'Cable Crossover', muscle: 'Chest', equipment: 'Cable'),
  Exercise(name: 'Pec Deck', muscle: 'Chest', equipment: 'Machine'),
  Exercise(name: 'Deadlift', muscle: 'Back', equipment: 'Barbell'),
  Exercise(name: 'Pull-Up', muscle: 'Back', equipment: 'Bodyweight'),
  Exercise(name: 'Lat Pulldown', muscle: 'Back', equipment: 'Cable'),
  Exercise(name: 'Seated Cable Row', muscle: 'Back', equipment: 'Cable'),
  Exercise(name: 'Dumbbell Row', muscle: 'Back', equipment: 'Dumbbell'),
  Exercise(name: 'T-Bar Row', muscle: 'Back', equipment: 'Machine'),
  Exercise(name: 'Straight-Arm Pulldown', muscle: 'Back', equipment: 'Cable'),
  Exercise(name: 'Squat', muscle: 'Legs', equipment: 'Barbell'),
  Exercise(name: 'Leg Press', muscle: 'Legs', equipment: 'Machine'),
  Exercise(name: 'Hack Squat', muscle: 'Legs', equipment: 'Machine'),
  Exercise(name: 'Romanian Deadlift', muscle: 'Legs', equipment: 'Barbell'),
  Exercise(name: 'Leg Curl', muscle: 'Legs', equipment: 'Machine'),
  Exercise(name: 'Leg Extension', muscle: 'Legs', equipment: 'Machine'),
  Exercise(
      name: 'Bulgarian Split Squat', muscle: 'Legs', equipment: 'Dumbbell'),
  Exercise(name: 'Walking Lunges', muscle: 'Legs', equipment: 'Dumbbell'),
  Exercise(name: 'Standing Calf Raise', muscle: 'Legs', equipment: 'Machine'),
  Exercise(name: 'Seated Calf Raise', muscle: 'Legs', equipment: 'Machine'),
  Exercise(name: 'Overhead Press', muscle: 'Shoulders', equipment: 'Barbell'),
  Exercise(
      name: 'Dumbbell Shoulder Press',
      muscle: 'Shoulders',
      equipment: 'Dumbbell'),
  Exercise(name: 'Lateral Raise', muscle: 'Shoulders', equipment: 'Dumbbell'),
  Exercise(name: 'Front Raise', muscle: 'Shoulders', equipment: 'Dumbbell'),
  Exercise(name: 'Rear Delt Fly', muscle: 'Shoulders', equipment: 'Machine'),
  Exercise(name: 'Arnold Press', muscle: 'Shoulders', equipment: 'Dumbbell'),
  Exercise(name: 'Shrug', muscle: 'Shoulders', equipment: 'Dumbbell'),
  Exercise(name: 'Barbell Curl', muscle: 'Arms', equipment: 'Barbell'),
  Exercise(name: 'Dumbbell Curl', muscle: 'Arms', equipment: 'Dumbbell'),
  Exercise(name: 'Preacher Curl', muscle: 'Arms', equipment: 'Machine'),
  Exercise(name: 'Concentration Curl', muscle: 'Arms', equipment: 'Dumbbell'),
  Exercise(name: 'Skullcrusher', muscle: 'Arms', equipment: 'Barbell'),
  Exercise(name: 'Tricep Pushdown', muscle: 'Arms', equipment: 'Cable'),
  Exercise(
      name: 'Overhead Tricep Extension', muscle: 'Arms', equipment: 'Dumbbell'),
  Exercise(
      name: 'Close-Grip Bench Press', muscle: 'Arms', equipment: 'Barbell'),
  Exercise(
      name: 'Rope Overhead Tricep Extension',
      muscle: 'Arms',
      equipment: 'Cable'),
  Exercise(name: 'Hanging Leg Raise', muscle: 'Core', equipment: 'Bodyweight'),
  Exercise(name: 'Cable Crunch', muscle: 'Core', equipment: 'Cable'),
  Exercise(name: 'Plank', muscle: 'Core', equipment: 'Bodyweight'),
  Exercise(name: 'Decline Sit-Up', muscle: 'Core', equipment: 'Bodyweight'),
  Exercise(name: 'Russian Twist', muscle: 'Core', equipment: 'Dumbbell'),
  Exercise(name: 'Back Extension', muscle: 'Core', equipment: 'Machine'),
];
