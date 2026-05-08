import 'package:flutter/material.dart';
import 'api_service.dart';

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? user;
  bool isLoading = true;

  Future<void> loadUser() async {
    final token = await ApiService.getToken();
    if (token != null) {
      try {
        final data = await ApiService.get('/users/me');
        user = data;
      } catch (_) {
        await ApiService.clearToken();
      }
    }
    isLoading = false;
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    try {
      final data = await ApiService.post('/auth/login', {'email': email, 'password': password});
      if (data['token'] != null) {
        await ApiService.saveToken(data['token']);
        user = data['user'];
        notifyListeners();
        return null;
      }
      return data['error'] ?? 'Login failed';
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> register(Map<String, dynamic> body) async {
    try {
      final data = await ApiService.post('/auth/register', body);
      if (data['token'] != null) {
        await ApiService.saveToken(data['token']);
        user = data['user'];
        notifyListeners();
        return null;
      }
      return data['error'] ?? 'Registration failed';
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    user = null;
    notifyListeners();
  }
}
