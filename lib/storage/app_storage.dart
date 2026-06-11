import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  // ---------------------------------------------------------------------------
  // 状態データ（メモリ上のキャッシュ）
  // ---------------------------------------------------------------------------
  static double _gpa = 3.24;
  static int _credits = 68;
  static final List<Map<String, dynamic>> _attendanceLog = [];

  // app_storage.dart に追加
  static List<Map<String, dynamic>> filterLectures({
    String? title,
    String? id,
    String? professor,
    int? dayIdx,
    int? periodIdx,
  }) {
    return syllabusMaster.values.where((lecture) {
      // 各条件がnullの場合は無視、入力がある場合のみチェックする
      bool matchTitle = title == null || title.isEmpty || 
                        lecture['title'].toString().contains(title);
      bool matchId = id == null || id.isEmpty || 
                    lecture['id'].toString() == id;
      bool matchProf = professor == null || professor.isEmpty || 
                      lecture['professor'].toString().contains(professor);
      
      // 曜日・時限のチェック（マスターデータにこれらの情報が必要）
      bool matchDay = dayIdx == null || lecture['dayIdx'] == dayIdx;
      bool matchPeriod = periodIdx == null || lecture['periodIdx'] == periodIdx;

      return matchTitle && matchId && matchProf && matchDay && matchPeriod;
    }).toList();
  }

  /// 各講義の 欠席数(absence) と 遅刻数(lateness)
  static Map<String, Map<String, int>> _attendanceCounts = {
    'M001': {'absence': 0, 'lateness': 0},
    'M002': {'absence': 1, 'lateness': 2}, 
    'M003': {'absence': 0, 'lateness': 0},
  };

  /// シラバス情報（個別遅刻換算レート: latenessRate を含む）
  static Map<String, Map<String, dynamic>> syllabusMaster = {
    'M001': {
      'id': 'M001',
      'title': '情報社会論',
      'room': '木花 A202',
      'professor': '宮大 太郎 教授',
      'type': 'liberal',
      'evaluation': '試験: 50%, レポート: 50%',
      'latenessRate': 3,
    },
    'M002': {
      'id': 'M002',
      'title': 'データ構造とアルゴリズム',
      'room': '木花 D101',
      'professor': '清武 次郎 准教授',
      'type': 'major',
      'evaluation': '中間課題: 40%, 期末試験: 60%',
      'latenessRate': 3,
    },
    'M003': {
      'id': 'M003',
      'title': 'オペレーティングシステム',
      'room': '木花 A301',
      'professor': '橘 一郎 講師',
      'type': 'major',
      'evaluation': '期末レポート: 100%',
      'latenessRate': 2,
    },
  };

  /// 時間割配置データ {曜日インデックス: {時限インデックス: 講義ID}}
  static Map<int, Map<int, String>> userTimetableCodes = {
    0: {1: 'M001'}, // 月曜2限
    2: {2: 'M002'}, // 水曜3限
    4: {0: 'M003'}, // 金曜1限
  };

  // ストレージ保存用の固定キー名
  static const String _keyGpa = 'uniflow_gpa';
  static const String _keyCredits = 'uniflow_credits';
  static const String _keyLog = 'uniflow_attendance_log';
  static const String _keyCounts = 'uniflow_attendance_counts';
  static const String _keySyllabus = 'uniflow_syllabus_master';
  static const String _keyTimetable = 'uniflow_user_timetable';

  // ---------------------------------------------------------------------------
  // 🔄 永続化ストレージ制御 (Save & Load)
  // ---------------------------------------------------------------------------

  /// アプリ起動時にローカルストレージからユーザーデータを復元するメソッド
  static Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 1. GPAと単位数
      _gpa = prefs.getDouble(_keyGpa) ?? 3.24;
      _credits = prefs.getInt(_keyCredits) ?? 68;

      // 2. 出席ログ
      final String? logJson = prefs.getString(_keyLog);
      if (logJson != null) {
        _attendanceLog.clear();
        _attendanceLog.addAll(List<Map<String, dynamic>>.from(jsonDecode(logJson)));
      }

      // 3. 出席カウンター
      final String? countsJson = prefs.getString(_keyCounts);
      if (countsJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(countsJson);
        _attendanceCounts = decoded.map((key, value) {
          final map = value as Map<String, dynamic>;
          return MapEntry(key, {'absence': map['absence'] as int, 'lateness': map['lateness'] as int});
        });
      }

      // 4. シラバスマスター
      final String? syllabusJson = prefs.getString(_keySyllabus);
      if (syllabusJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(syllabusJson);
        syllabusMaster = decoded.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
      }

      // 5. 時間割配置
      final String? timetableJson = prefs.getString(_keyTimetable);
      if (timetableJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(timetableJson);
        userTimetableCodes = decoded.map((key, value) {
          final Map<int, String> innerMap = {};
          (value as Map<String, dynamic>).forEach((pKey, pValue) {
            innerMap[int.parse(pKey)] = pValue.toString();
          });
          return MapEntry(int.parse(key), innerMap);
        });
      }
      print("📦 [AppStorage] ユーザーデータを正常にローカルから復元しました。");
    } catch (e) {
      print("🚨 [AppStorage] データ復元中にエラーが発生しました(初期値で稼働します): $e");
    }
  }

  /// 現在のメモリ状態をローカルストレージに非同期保存する内部関数
  static Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setDouble(_keyGpa, _gpa);
      await prefs.setInt(_keyCredits, _credits);
      await prefs.setString(_keyLog, jsonEncode(_attendanceLog));
      await prefs.setString(_keyCounts, jsonEncode(_attendanceCounts));
      await prefs.setString(_keySyllabus, jsonEncode(syllabusMaster));

      final Map<String, dynamic> timetableToSave = userTimetableCodes.map(
        (key, value) => MapEntry(key.toString(), value.map((pKey, pValue) => MapEntry(pKey.toString(), pValue))),
      );
      await prefs.setString(_keyTimetable, jsonEncode(timetableToSave));
    } catch (e) {
      print("🚨 [AppStorage] データの自動保存に失敗しました: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // ゲッター & セッター
  // ---------------------------------------------------------------------------
  static double getGpa() => _gpa;
  static int getCredits() => _credits;
  static List<Map<String, dynamic>> getAttendanceLog() => _attendanceLog;

  static int getAbsenceCount(String id) => _attendanceCounts[id]?['absence'] ?? 0;
  static int getLatenessCount(String id) => _attendanceCounts[id]?['lateness'] ?? 0;
  static int getLatenessRate(String id) => syllabusMaster[id]?['latenessRate'] ?? 3;

  static void setAbsenceCount(String id, int count) {
    if (!_attendanceCounts.containsKey(id)) {
      _attendanceCounts[id] = {'absence': 0, 'lateness': 0};
    }
    _attendanceCounts[id]?['absence'] = count;
    _saveToStorage();
  }

  static void setLatenessCount(String id, int count) {
    if (!_attendanceCounts.containsKey(id)) {
      _attendanceCounts[id] = {'absence': 0, 'lateness': 0};
    }
    _attendanceCounts[id]?['lateness'] = count;
    _saveToStorage();
  }

  static void setLatenessRate(String id, int rate) {
    if (!syllabusMaster.containsKey(id)) return;
    syllabusMaster[id]?['latenessRate'] = rate;
    _saveToStorage();
  }

  static int getCalculatedTotalAbsence(String id) {
    int directAbsence = getAbsenceCount(id);
    int lateness = getLatenessCount(id);
    int rate = getLatenessRate(id);
    if (rate <= 0) return directAbsence;
    return directAbsence + (lateness ~/ rate);
  }

  static List<Map<String, dynamic>> getAlertLectures() {
    List<Map<String, dynamic>> alerts = [];
    _attendanceCounts.forEach((id, _) {
      int totalAbsence = getCalculatedTotalAbsence(id);
      if (totalAbsence >= 3) {
        var lecture = syllabusMaster[id];
        if (lecture != null) {
          alerts.add({
            'id': id,
            'title': lecture['title'],
            'totalAbsence': totalAbsence,
            'status': totalAbsence >= 4 ? '単位不可確定' : '次で一発アウト',
          });
        }
      }
    });
    return alerts;
  }

  static List<Map<String, dynamic>> getTodayLectures(int dayIdx) {
    List<Map<String, dynamic>> todayList = [];
    final periodMap = userTimetableCodes[dayIdx];
    if (periodMap == null) return todayList;

    final periodTimes = [
      {'num': '1', 'time': '1限 (08:40~10:10)'},
      {'num': '2', 'time': '2限 (10:20~11:50)'},
      {'num': '3', 'time': '3限 (12:50~14:20)'},
      {'num': '4', 'time': '4限 (14:30~16:00)'},
      {'num': '5', 'time': '5限 (16:10~17:55)'},
    ];

    for (int i = 0; i < 5; i++) {
      String? code = periodMap[i];
      if (code != null) {
        var master = syllabusMaster[code];
        if (master != null) {
          todayList.add({
            'id': master['id'],
            'periodText': periodTimes[i]['time']!,
            'title': master['title'],
            'room': master['room'],
            'type': master['type'],
          });
        }
      }
    }
    return todayList;
  }

  static void saveGpaAndCredits(double gpa, int credits) {
    _gpa = gpa;
    _credits = credits;
    _saveToStorage();
  }

  static void saveAttendance(String lecture, DateTime time, bool isOffline) {
    _attendanceLog.add({
      'lecture': lecture,
      'time': time.toIso8601String(),
      'status': isOffline ? '仮受付(オフライン)' : '完了',
    });
    _saveToStorage();
  }

  static void addNewLecture({
    required String title,
    required String room,
    required String professor,
    required String type,
    required int dayIdx,
    required int periodIdx,
  }) {
    String newId = 'M_${DateTime.now().millisecondsSinceEpoch}';

    syllabusMaster[newId] = {
      'id': newId,
      'title': title,
      'room': room,
      'professor': professor,
      'type': type,
      'evaluation': '未設定（シラバスを確認してください）',
      'latenessRate': 3,
    };

    _attendanceCounts[newId] = {'absence': 0, 'lateness': 0};

    if (userTimetableCodes[dayIdx] == null) {
      userTimetableCodes[dayIdx] = {};
    }
    userTimetableCodes[dayIdx]![periodIdx] = newId;

    _saveToStorage();
  }

  static void removeLectureFromTimetable(int dayIdx, int periodIdx) {
    if (userTimetableCodes[dayIdx] != null) {
      String? id = userTimetableCodes[dayIdx]![periodIdx];
      if (id != null) {
        userTimetableCodes[dayIdx]!.remove(periodIdx);
        syllabusMaster.remove(id);
        _attendanceCounts.remove(id);
      }
      _saveToStorage();
    }
  }
}