import 'dart:convert';
import 'package:http/http.dart' as http;

class SyllabusService {
  static Map<String, dynamic> _syllabusMap = {};
  static bool _isLoaded = false;

  static bool get isLoaded => _isLoaded;

  /// PWA自身のドメイン配下（GitHub Pages）から静的JSONデータをロードする
  static Future<void> loadSyllabusJson() async {
    if (_isLoaded) return;
    try {
      // 自身の相対パスからフェッチすることでCORSを回避
      final response = await http.get(Uri.parse('./assets/syllabus_master.json'));
      if (response.statusCode == 200) {
        _syllabusMap = jsonDecode(utf8.decode(response.bodyBytes));
        _isLoaded = true;
        print("宮崎大学シラバス読込成功: ${_syllabusMap.length}件");
      }
    } catch (e) {
      print("シラバスJSONのフェッチに失敗: $e");
    }
  }

  /// 時間割コードで検索して登録用の講義データを返す
  static Map<String, dynamic>? findLectureByCode(String code) {
    final target = _syllabusMap[code];
    if (target == null) return null;

    return {
      "id": target['id'],
      "title": target['title'],
      "room": target['room'],
      "professor": target['professor'],
      "type": target['type'],
      "dayIdx": target['dayIdx'],
      "periodIdx": target['periodIdx'],
      "rawSchedule": target['rawSchedule']
    };
  }

  /// 【新規追加】シラバス全件データを検索用に整形して取得する
  static List<Map<String, dynamic>> get allLectures {
    return _syllabusMap.entries.map((entry) {
      final code = entry.key;
      final target = entry.value;
      return {
        "id": target['id'] ?? code, // IDがない場合は時間割コードを代替に
        "title": target['title'] ?? '不明な講義',
        "room": target['room'] ?? '未定',
        "professor": target['professor'] ?? '未定',
        "type": target['type'] ?? 'major',
        "dayIdx": target['dayIdx'],
        "periodIdx": target['periodIdx'],
        "rawSchedule": target['rawSchedule'] ?? '',
      };
    }).toList();
  }
}