import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _base = 'https://mathkraft.onrender.com/api';
const _storage = FlutterSecureStorage();

class ApiService {
  static Future<String?> getToken() => _storage.read(key: 'token');
  static Future<void> saveToken(String token) => _storage.write(key: 'token', value: token);
  static Future<void> clearToken() => _storage.delete(key: 'token');

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> post(String path, Map body) async {
    final res = await http.post(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return jsonDecode(res.body);
  }

  static Future<dynamic> get(String path) async {
    final res = await http.get(Uri.parse('$_base$path'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> patch(String path, Map body) async {
    final res = await http.patch(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> put(String path, Map body) async {
    final res = await http.put(
      Uri.parse('$_base$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final res = await http.delete(Uri.parse('$_base$path'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> uploadFile(String path, File file, Map<String, String> fields) async {
    final token = await getToken();
    final req = http.MultipartRequest('POST', Uri.parse('$_base$path'));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath('proof_photo', file.path));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    return jsonDecode(res.body);
  }
}
