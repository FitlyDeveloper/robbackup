import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _favoritesKey = 'favorite_exercises';

  static Future<List<Map<String, String>>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> rawFavorites = prefs.getStringList(_favoritesKey) ?? [];
    return rawFavorites.map((id) => {'id': id}).toList();
  }

  static Future<void> addFavorite(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];
    if (!favorites.contains(exerciseId)) {
      favorites.add(exerciseId);
      await prefs.setStringList(_favoritesKey, favorites);
    }
  }

  static Future<void> removeFavorite(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];
    favorites.remove(exerciseId);
    await prefs.setStringList(_favoritesKey, favorites);
  }

  static Future<bool> isFavorite(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> favorites = prefs.getStringList(_favoritesKey) ?? [];
    return favorites.contains(exerciseId);
  }
} 