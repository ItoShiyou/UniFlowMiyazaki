import 'package:flutter/material.dart';
import 'package:uniflow_miyazaki/storage/app_storage.dart'; // 🚨 プロジェクト名に合わせてパスを調整してください
import 'package:uniflow_miyazaki/services/syllabus_service.dart';

import 'dart:convert'; // jsonEncode / jsonDecode 用
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 用

// 🚨 main関数の前に async を付与します
void main() async {
  // SharedPreferencesなどのネイティブ通信のバインドを担保する必須処理
  WidgetsFlutterBinding.ensureInitialized();
  
  // 端末ストレージから保存されていた既存データを完全に復元
  await AppStorage.loadFromStorage();
  
  // 静的シラバスJSONデータのロード（非同期）
  SyllabusService.loadSyllabusJson();
  runApp(const UniFlowMiyazakiApp());
}

class UniFlowMiyazakiApp extends StatelessWidget {
  const UniFlowMiyazakiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniFlow Miyazaki',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BAC),
          primary: const Color(0xFF005BAC),
          secondary: const Color(0xFF00A79D),
          tertiary: const Color(0xFFFFC107),
        ),
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ==========================================
// 💾 【1. データレイヤー】永続化・遅刻欠席ロジック
// ==========================================
class AppStorage {
  // ---------------------------------------------------------------------------
  // 状態データ（メモリ上のキャッシュ）
  // ---------------------------------------------------------------------------
  static double _gpa = 3.24;
  static int _credits = 68;
  static final List<Map<String, dynamic>> _attendanceLog = [];

  /// 各講義の 欠席数(absence) と 遅刻数(lateness)
  static Map<String, Map<String, int>> _attendanceCounts = {
    'M001': {'absence': 0, 'lateness': 0},
    'M002': {'absence': 1, 'lateness': 2}, 
    'M003': {'absence': 0, 'lateness': 0},
  };

  // app_storage.dart に追加
  static List<Map<String, dynamic>> searchLectures(String query) {
    if (query.isEmpty) return [];
    return syllabusMaster.values.where((lecture) {
      return lecture['title'].toString().contains(query) || 
            lecture['professor'].toString().contains(query);
    }).toList();
  }

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

      // Map<int, Map<int, String>> を JSON変換可能な型にキャストして保存
      final Map<String, dynamic> timetableToSave = userTimetableCodes.map(
        (key, value) => MapEntry(key.toString(), value.map((pKey, pValue) => MapEntry(pKey.toString(), pValue))),
      );
      await prefs.setString(_keyTimetable, jsonEncode(timetableToSave));
    } catch (e) {
      print("🚨 [AppStorage] データの自動保存に失敗しました: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // ゲッター & セッター (安全ガード + 自動セーブを統合)
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
    if (!syllabusMaster.containsKey(id)) return; // 存在しない講義は何もしない
    syllabusMaster[id]?['latenessRate'] = rate;
    _saveToStorage();
  }

  /// 実質欠席数を計算する（直接の欠席数 + 遅刻数 / 換算レート）
  static int getCalculatedTotalAbsence(String id) {
    int directAbsence = getAbsenceCount(id);
    int lateness = getLatenessCount(id);
    int rate = getLatenessRate(id);
    if (rate <= 0) return directAbsence; // ゼロ除算ディフェンス
    return directAbsence + (lateness ~/ rate);
  }

  /// 警告対象の講義を判定（実質欠席数が3回以上のもの）
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

  /// 指定された曜日の講義リストを時限順に並び替えて取得する（ホーム画面用）
  static List<Map<String, dynamic>> getTodayLectures(int dayIdx) {
    List<Map<String, dynamic>> todayList = [];
    final periodMap = userTimetableCodes[dayIdx];
    if (periodMap == null) return todayList;

    final periodTimes = [
      {'num': '1', 'time': '1限 (08:40~10:10)'},
      {'num': '2', 'time': '2限 (10:30~12:00)'},
      {'num': '3', 'time': '3限 (13:00~14:30)'},
      {'num': '4', 'time': '4限 (14:50~16:20)'},
      {'num': '5', 'time': '5限 (16:40~18:10)'},
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

  /// 【新規追加】新しい講義をマスターデータと時間割コードに登録する
  static void addNewLecture({
    required String title,
    required String room,
    required String professor,
    required String type, // 'major'（専門） 或者 'liberal'（教養）
    required int dayIdx,  // 0=月 ~ 4=金
    required int periodIdx, // 0=1限 ~ 4=5限
  }) {
    // ユニークなIDを一意に生成
    String newId = 'M_${DateTime.now().millisecondsSinceEpoch}';

    // 1. シラバス（マスターデータ）に登録
    syllabusMaster[newId] = {
      'id': newId,
      'title': title,
      'room': room,
      'professor': professor,
      'type': type,
      'evaluation': '未設定（シラバスを確認してください）',
      'latenessRate': 3, // デフォルトは3回遅刻で1欠席
    };

    // 2. 出席・遅刻カウンターの初期化
    _attendanceCounts[newId] = {'absence': 0, 'lateness': 0};

    // 3. 該当する曜日・時限のマップに講義IDを紐付け
    if (userTimetableCodes[dayIdx] == null) {
      userTimetableCodes[dayIdx] = {};
    }
    userTimetableCodes[dayIdx]![periodIdx] = newId;

    // 自動保存
    _saveToStorage();
  }

  /// 【新規追加】指定された曜日・時限の講義登録を解除（削除）する
  static void removeLectureFromTimetable(int dayIdx, int periodIdx) {
    if (userTimetableCodes[dayIdx] != null) {
      String? id = userTimetableCodes[dayIdx]![periodIdx];
      if (id != null) {
        userTimetableCodes[dayIdx]!.remove(periodIdx);
        // メモリリーク防止のため、登録解除された講義に付随する個別データもクリーンアップ
        syllabusMaster.remove(id);
        _attendanceCounts.remove(id);
      }
      // 自動保存
      _saveToStorage();
    }
  }
}
// ==========================================
// 💻 【2. メイン外殻】ナビゲーション基盤
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    int alertCount = AppStorage.getAlertLectures().length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UniFlow Miyazaki',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 1,
        scrolledUnderElevation: 1,
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                onPressed: () => _onTabChanged(3),
              ),
              if (alertCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      '$alertCount',
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            onNavigateToAnalytics: () => _onTabChanged(2),
            onNavigateToTimetable: () => _onTabChanged(1),
          ),
          const TimetableScreen(),
          const AnalyticsScreen(),
          const NotificationSettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 1)],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabChanged,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'ホーム'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_view_week_outlined), activeIcon: Icon(Icons.calendar_view_week), label: '時間割'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: '成績・進捗'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: '設定'),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 📱 【3. タブ1】ホーム画面（動的予定追従）
// ==========================================
class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToTimetable;
  const HomeScreen({super.key, required this.onNavigateToAnalytics, required this.onNavigateToTimetable});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _attendanceCount = 0;

  @override
  void initState() {
    super.initState();
    _attendanceCount = AppStorage.getAttendanceLog().length;
  }

  
  // 🎯 ホームの出席登録ボタンを押したときの判定ロジック
  void _handleAttendance(BuildContext context) {
    final now = DateTime.now();
    
    // 1. 曜日インデックスを取得 (DateTimeは月曜=1, 金曜=5, 日曜=7)
    // 時間割の月〜金 (0〜4) にマッピング
    int dayIdx = now.weekday - 1; 
    
    if (dayIdx > 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本日は講義開講曜日（月〜金）ではありません。'), backgroundColor: Colors.orange),
      );
      return;
    }

    // 2. 現在時刻（時・分）から、何限目（periodIdx）かを判定
    int? periodIdx;
    final currentTime = now.hour * 60 + now.minute; // 判定しやすいように分単位に換算

    if (currentTime >= 520 && currentTime <= 610) {        // 08:40 - 10:10
      periodIdx = 0; // 1限
    } else if (currentTime >= 630 && currentTime <= 720) {  // 10:30 - 12:00
      periodIdx = 1; // 2限
    } else if (currentTime >= 780 && currentTime <= 870) {  // 13:00 - 14:30
      periodIdx = 2; // 3限
    } else if (currentTime >= 890 && currentTime <= 980) {  // 14:50 - 16:20
      periodIdx = 3; // 4限
    } else if (currentTime >= 1000 && currentTime <= 1090) { // 16:40 - 18:10
      periodIdx = 4; // 5限
    }

    if (periodIdx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在は通常の講義時間（1限〜5限）の外です。'), backgroundColor: Colors.grey),
      );
      return;
    }

    // 3. AppStorage から現在のコマに登録されている時間割コードを取得
    String? code = AppStorage.userTimetableCodes[dayIdx]?[periodIdx];
    
    if (code == null || AppStorage.syllabusMaster[code] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在のコマに登録されている講義が時間割にありません。'), backgroundColor: Colors.blueGrey),
      );
      return;
    }

    final lecture = AppStorage.syllabusMaster[code]!;
    final lectureId = lecture['id'];

    // 4. 自動判定された講義の出席/欠席を管理する確認ダイアログを表示
    showDialog(
      context: context,
      builder: (context) {
        int currentAbsence = AppStorage.getAbsenceCount(lectureId);
        int currentLateness = AppStorage.getLatenessCount(lectureId);
        int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Text('出席・状況確認', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('現在開講中の講義を検出しました：', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('『${lecture['title']}』', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('教室: ${lecture['room']} | 担当: ${lecture['professor']}', style: const TextStyle(fontSize: 12)),
              const Divider(height: 24),
              Text('現在の欠課ステータス:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('・欠席回数: $currentAbsence 回', style: const TextStyle(fontSize: 13)),
              Text('・遅刻回数: $currentLateness 回', style: const TextStyle(fontSize: 13)),
              Text('・実質欠席換算: $totalAbsence 回', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: totalAbsence >= 3 ? Colors.red : Colors.green)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
            // もし「出席した（間違えてついていた欠席を取り消す）」などのクイック処理を入れる場合
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                // 例：もし直前に「欠席」ボタンなどを押してしまっていた場合、ここからカウントを戻すなどのロジックが組めます
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('『${lecture['title']}』の出席確認を行いました。'), backgroundColor: Colors.green),
                );
              },
              child: const Text('出席を確定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int displayAttendanceRate = 92 + _attendanceCount;
    if (displayAttendanceRate > 100) displayAttendanceRate = 100;

    // 現在のシステム時刻から曜日を取得し、今日の予定を動的に抽出
    int weekday = DateTime.now().weekday; // 1=月...5=金, 6=土, 7=日
    int dayIdx = weekday - 1; 

    List<Map<String, dynamic>> todayLectures = [];
    if (dayIdx >= 0 && dayIdx <= 4) {
      todayLectures = AppStorage.getTodayLectures(dayIdx);
    }

    final alertLectures = AppStorage.getAlertLectures();
    final daysJa = ['月', '火', '水', '木', '金', '土', '日'];
    String todayStr = "${DateTime.now().month}/${DateTime.now().day} (${daysJa[weekday - 1]})";

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('現在の出席状況', style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('総出席率: $displayAttendanceRate%', style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _handleAttendance(context),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('出席登録', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.tertiary,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        Text('本日の予定 - $todayStr', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        if (todayLectures.isEmpty)
          Card(
            color: Colors.grey.shade100,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  dayIdx > 4 ? '本日は週末でお休みです。' : '本日の予定（登録講義）はありません。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ),
          )
        else
          ...todayLectures.map((lec) {
            Color cellBg = lec['type'] == 'major' ? Colors.blue.shade50 : Colors.amber.shade50;
            return _buildTimelineCard(context, lec['periodText'], lec['title'], lec['room'], cellBg, lec['id']);
          }),

        const SizedBox(height: 20),
        const Text('要警戒タスク ＆ メッセージ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        
        ...alertLectures.map((alert) {
          int directAbsence = AppStorage.getAbsenceCount(alert['id']);
          int lateness = AppStorage.getLatenessCount(alert['id']);
          return Card(
            color: alert['status'] == '単位不可確定' ? Colors.red.shade50 : Colors.orange.shade50,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: alert['status'] == '単位不可確定' ? Colors.red : Colors.orange),
              borderRadius: BorderRadius.circular(8)
            ),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.gpp_bad, color: Colors.white)),
              title: Text('${alert['title']} (実質欠席: ${alert['totalAbsence']}回)'),
              subtitle: Text('内訳: 欠席 $directAbsence回 / 遅刻 $lateness回\n${alert['status'] == '単位不可確定' ? "今期の単位取得は不可能です。" : "これ以上の遅刻・欠席は一発で不可になります。"}'),
              trailing: TextButton(
                onPressed: widget.onNavigateToTimetable,
                child: const Text('確認', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          );
        }),

        Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.assignment, color: Colors.white)),
            title: const Text('アルゴリズム実装課題'),
            subtitle: const Text('締切: 残り2日（金曜 23:59）'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
              child: const Text('要警戒', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(BuildContext context, String time, String title, String room, Color bgColor, String lectureId) {
    int absence = AppStorage.getAbsenceCount(lectureId);
    int lateness = AppStorage.getLatenessCount(lectureId);
    int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 50,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      if (absence > 0 || lateness > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: totalAbsence >= 3 ? Colors.red : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                          child: Text('欠$absence/遅$lateness (実質:$totalAbsence)', style: TextStyle(fontSize: 9, color: totalAbsence >= 3 ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
              child: Text(room.toString().replaceAll('木花 ', ''), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 🗓️ 【4. タブ2】時間割マトリクス＆詳細・追加設定（修正版）
// ==========================================
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  // シラバスコード入力用のコントローラー
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // 🗓️ 改善版：JSONシラバス全件から複合条件で絞り込みができる講義追加ダイアログ
  void _showAddLectureSearchDialog(BuildContext context, int dayIdx, int periodIdx) {
    // 検索条件用のコントローラーと選択値の初期化
    final TextEditingController titleController = TextEditingController();
    final TextEditingController idController = TextEditingController();
    final TextEditingController professorController = TextEditingController();
    
    // タップされたコマの曜日・時限を初期選択値にする（nullは「指定なし」）
    int? selectedDayIdx = dayIdx;
    int? selectedPeriodIdx = periodIdx;

    List<Map<String, dynamic>> searchResults = [];

    // フィルタリングを行うローカル関数
    void performSearch(StateSetter setModalState) {
      // 🚨 【修正ポイント】JSONから読み込まれたシラバス全件データをサービスから直接取得
      List<Map<String, dynamic>> allLectures = SyllabusService.allLectures; 

      final titleQuery = titleController.text.trim().toLowerCase();
      final idQuery = idController.text.trim().toLowerCase();
      final professorQuery = professorController.text.trim().toLowerCase();

      setModalState(() {
        searchResults = allLectures.where((lecture) {
          // 1. 講義名の部分一致（一部入力でも検索可能）
          if (titleQuery.isNotEmpty && !lecture['title'].toString().toLowerCase().contains(titleQuery)) {
            return false;
          }
          // 2. ID（または時間割コード）の部分・完全一致
          if (idQuery.isNotEmpty && !lecture['id'].toString().toLowerCase().contains(idQuery)) {
            return false;
          }
          // 3. 担当教員名の部分一致（一部入力でも検索可能）
          if (professorQuery.isNotEmpty && !lecture['professor'].toString().toLowerCase().contains(professorQuery)) {
            return false;
          }
          // 4. 実施曜日の完全一致
          if (selectedDayIdx != null && lecture['dayIdx'] != selectedDayIdx) {
            return false;
          }
          // 5. 実施時限の完全一致
          if (selectedPeriodIdx != null && lecture['periodIdx'] != selectedPeriodIdx) {
            return false;
          }
          return true;
        }).toList();
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          // 初回展開時、かつすべての入力欄が空のときに自動で初期検索（タップしたコマの条件）を走らせる
          if (searchResults.isEmpty && 
              titleController.text.isEmpty && 
              idController.text.isEmpty && 
              professorController.text.isEmpty) {
            performSearch(setModalState);
          }

          return Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20, // キーボードを避ける
            ),
            height: MediaQuery.of(context).size.height * 0.85, // 検索エリア確保のため高さを拡張
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '条件を指定して講義を検索',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                // 1. 講義名入力欄
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '講義名（キーワード）', 
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20)
                  ),
                  onChanged: (_) => performSearch(setModalState),
                ),
                const SizedBox(height: 8),
                
                // 2. ID & 教員名入力欄（横並び）
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: idController,
                        decoration: const InputDecoration(labelText: '講義ID / コード', isDense: true),
                        onChanged: (_) => performSearch(setModalState),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: professorController,
                        decoration: const InputDecoration(labelText: '先生の名前', isDense: true),
                        onChanged: (_) => performSearch(setModalState),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // 3. 曜日 & 時限 選択ドロップダウン（横並び）
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: selectedDayIdx,
                        decoration: const InputDecoration(labelText: '実施曜日', isDense: true),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('指定なし')),
                          DropdownMenuItem(value: 0, child: Text('月曜日')),
                          DropdownMenuItem(value: 1, child: Text('火曜日')),
                          DropdownMenuItem(value: 2, child: Text('水曜日')),
                          DropdownMenuItem(value: 3, child: Text('木曜日')),
                          DropdownMenuItem(value: 4, child: Text('金曜日')),
                        ],
                        onChanged: (val) {
                          selectedDayIdx = val;
                          performSearch(setModalState);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: selectedPeriodIdx,
                        decoration: const InputDecoration(labelText: '実施時間（コマ）', isDense: true),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('指定なし')),
                          DropdownMenuItem(value: 0, child: Text('1コマ')),
                          DropdownMenuItem(value: 1, child: Text('2コマ')),
                          DropdownMenuItem(value: 2, child: Text('3コマ')),
                          DropdownMenuItem(value: 3, child: Text('4コマ')),
                          DropdownMenuItem(value: 4, child: Text('5コマ')),
                        ],
                        onChanged: (val) {
                          selectedPeriodIdx = val;
                          performSearch(setModalState);
                        },
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // 4. 検索結果表示エリア
                Expanded(
                  child: searchResults.isEmpty
                      ? const Center(child: Text('条件に一致する講義が見つかりません', style: TextStyle(color: Colors.grey, fontSize: 13)))
                      : ListView.builder(
                          itemCount: searchResults.length,
                          itemBuilder: (context, index) {
                            final lecture = searchResults[index];
                            final days = ['月', '火', '水', '木', '金'];
                            
                            String lDay = lecture['dayIdx'] != null && lecture['dayIdx'] >= 0 && lecture['dayIdx'] < 5 
                                ? days[lecture['dayIdx']] : '未定';
                            String lPeriod = lecture['periodIdx'] != null ? '${lecture['periodIdx'] + 1}限' : '';

                            return ListTile(
                              title: Text(lecture['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                'ID: ${lecture['id']} | 担当: ${lecture['professor']}\n教室: ${lecture['room']} ($lDay$lPeriod)',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                              onTap: () {
                                // 選択された講義を登録（講義自体が曜日情報を持っていればそれを優先、なければタップしたコマに配置）
                                AppStorage.addNewLecture(
                                  title: lecture['title'],
                                  room: lecture['room'],
                                  professor: lecture['professor'],
                                  type: lecture['type'] ?? 'major',
                                  dayIdx: lecture['dayIdx'] ?? dayIdx,
                                  periodIdx: lecture['periodIdx'] ?? periodIdx,
                                );
                                setState(() {});
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
                
                // 5. 手動登録への救済導線
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      icon: const Icon(Icons.edit_note, size: 20),
                      label: const Text('シラバスにない講義を手動で登録する', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(context);
                        _showManualAddDialog(context, dayIdx, periodIdx);
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  /// 既存の講義詳細表示モーダル（削除ボタン統合版）
  /// 講義詳細表示モーダル（レイアウト崩れ対策・削除ボタン統合版）
  void _showLectureDetails(BuildContext context, Map<String, dynamic> lecture, int dayIdx, int periodIdx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            String lectureId = lecture['id'];
            int currentAbsence = AppStorage.getAbsenceCount(lectureId);
            int currentLateness = AppStorage.getLatenessCount(lectureId);
            int currentRate = AppStorage.getLatenessRate(lectureId);
            int totalAbsence = AppStorage.getCalculatedTotalAbsence(lectureId);

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 🚨 長い講義名でも右側のバッジを押し出さずに自動改行させるための Expanded
                      Expanded(
                        child: Text(
                          lecture['title'], 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8), // タイトルとバッジの間の隙間を確保
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalAbsence >= 4 ? Colors.red.shade100 : (totalAbsence == 3 ? Colors.orange.shade100 : Colors.green.shade100),
                          borderRadius: BorderRadius.circular(4)
                        ),
                        child: Text(
                          '実質欠席: $totalAbsence回 (${totalAbsence >= 4 ? "不可確定" : (totalAbsence == 3 ? "要警戒" : "安全")})',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: totalAbsence >= 3 ? Colors.red : Colors.green.shade800),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('教室: ${lecture['room']} | 担当: ${lecture['professor']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('欠席回数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: currentAbsence > 0 ? () {
                              setModalState(() => AppStorage.setAbsenceCount(lectureId, currentAbsence - 1));
                              setState(() {});
                            } : null,
                          ),
                          Text('$currentAbsence', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              setModalState(() => AppStorage.setAbsenceCount(lectureId, currentAbsence + 1));
                              setState(() {});
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('遅刻回数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: currentLateness > 0 ? () {
                              setModalState(() => AppStorage.setLatenessCount(lectureId, currentLateness - 1));
                              setState(() {});
                            } : null,
                          ),
                          Text('$currentLateness', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              setModalState(() => AppStorage.setLatenessCount(lectureId, currentLateness + 1));
                              setState(() {});
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('遅刻の換算ルール設定', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        DropdownButton<int>(
                          value: currentRate,
                          elevation: 2,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 2, child: Text('遅刻 2回 = 欠席1回')),
                            DropdownMenuItem(value: 3, child: Text('遅刻 3回 = 欠席1回')),
                            DropdownMenuItem(value: 4, child: Text('遅刻 4回 = 欠席1回')),
                          ],
                          onChanged: (int? newRate) {
                            if (newRate != null) {
                              setModalState(() => AppStorage.setLatenessRate(lectureId, newRate));
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  const Text('【評価基準】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(lecture['evaluation'] ?? '未設定', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  // 🚨 講義の登録解除（削除）ボタン
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('この講義を時間割から削除する', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('講義の削除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            content: Text('『${lecture['title']}』の登録を解除しますか？\n（これまでの欠席・遅刻データも破棄されます）'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () {
                                  AppStorage.removeLectureFromTimetable(dayIdx, periodIdx);
                                  Navigator.pop(context); // ダイアログを閉じる
                                  Navigator.pop(context); // ボトムシートを閉じる
                                  setState(() {}); // 画面再描画

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('『${lecture['title']}』を削除しました。'), backgroundColor: Colors.grey.shade800),
                                  );
                                },
                                child: const Text('削除する', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  /// 検索で見つからない場合の手入力ダイアログ
  void _showManualAddDialog(BuildContext context, int dayIdx, int periodIdx) {
    final titleController = TextEditingController();
    final roomController = TextEditingController();
    final professorController = TextEditingController();
    String selectedType = 'major';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: '講義名')),
              TextField(controller: roomController, decoration: const InputDecoration(labelText: '教室')),
              TextField(controller: professorController, decoration: const InputDecoration(labelText: '担当教員')),
              Row(
                children: [
                  Radio(value: 'major', groupValue: selectedType, onChanged: (v) => setModalState(() => selectedType = v as String)),
                  const Text('専門'),
                  Radio(value: 'liberal', groupValue: selectedType, onChanged: (v) => setModalState(() => selectedType = v as String)),
                  const Text('教養'),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  AppStorage.addNewLecture(
                    title: titleController.text,
                    room: roomController.text,
                    professor: professorController.text,
                    type: selectedType,
                    dayIdx: dayIdx,
                    periodIdx: periodIdx,
                  );
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('登録'),
              )
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = ['月', '火', '水', '木', '金'];
    final periods = [
      {'num': '1', 'time': '8:40\n10:10'},
      {'num': '2', 'time': '10:30\n12:00'},
      {'num': '3', 'time': '13:00\n14:30'},
      {'num': '4', 'time': '14:50\n16:20'},
      {'num': '5', 'time': '16:40\n18:10'},
    ];

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        children: [
          // 【最上部インテグレーション】宮大シラバス自動連携コード入力欄
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        hintText: '宮大時間割コードを入力 (例: ksf91)',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('シラバス追加', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      String code = _codeController.text.trim();
                      if (code.isEmpty) return;

                      final lecture = SyllabusService.findLectureByCode(code);
                      
                      if (lecture != null) {
                        if (lecture['dayIdx'] == null || lecture['periodIdx'] == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('『${lecture['title']}』は集中講義等のため時間割に自動配置できません。(${lecture['rawSchedule']})'),
                              backgroundColor: Colors.orange.shade800,
                            ),
                          );
                          return;
                        }

                        AppStorage.addNewLecture(
                          title: lecture['title'],
                          room: lecture['room'],
                          professor: lecture['professor'],
                          type: lecture['type'],
                          dayIdx: lecture['dayIdx'],
                          periodIdx: lecture['periodIdx'],
                        );

                        setState(() {});
                        _codeController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('【自動マッピング】『${lecture['title']}』を配置しました。'),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('指定された時間割コードはシラバスデータ内に見つかりません。'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8, thickness: 0.5),

          // 曜日ヘッダー
          Row(
            children: [
              const SizedBox(width: 45), 
              ...days.map((day) => Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Center(child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    ),
                  )),
            ],
          ),
          
          // 時間割マトリクス本体
          Expanded(
            child: Column(
              children: periods.asMap().entries.map((periodEntry) {
                int periodIdx = periodEntry.key;
                var period = periodEntry.value;

                return Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(period['num']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(period['time']!, style: const TextStyle(fontSize: 8, color: Colors.grey), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                      ...List.generate(5, (dayIdx) {
                        String? code = AppStorage.userTimetableCodes[dayIdx]?[periodIdx];
                        Map<String, dynamic>? lecture = code != null ? AppStorage.syllabusMaster[code] : null;

                        Color cellColor = Colors.grey.shade50;
                        Color borderColor = Colors.grey.shade200;
                        
                        int absence = 0;
                        int lateness = 0;
                        int totalAbsence = 0;

                        if (lecture != null) {
                          String lId = lecture['id'];
                          absence = AppStorage.getAbsenceCount(lId);
                          lateness = AppStorage.getLatenessCount(lId);
                          totalAbsence = AppStorage.getCalculatedTotalAbsence(lId);

                          if (totalAbsence >= 4) {
                            cellColor = Colors.red.shade50;
                            borderColor = Colors.red.shade300;
                          } else if (totalAbsence == 3) {
                            cellColor = Colors.orange.shade50;
                            borderColor = Colors.orange.shade300;
                          } else {
                            cellColor = lecture['type'] == 'major' ? const Color(0xFFE3F2FD) : const Color(0xFFFFFDE7);
                            borderColor = lecture['type'] == 'major' ? Colors.blue.shade200 : Colors.amber.shade200;
                          }
                        }

                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (lecture != null) {
                                _showLectureDetails(context, lecture, dayIdx, periodIdx);
                              } else {
                                _showAddLectureSearchDialog(context, dayIdx, periodIdx);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: cellColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: borderColor, width: 1),
                              ),
                              child: lecture != null
                                  ? Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                lecture['title'],
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.1),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                lecture['room'].toString(),
                                                style: TextStyle(fontSize: 8, color: Colors.grey.shade700),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                          if (absence > 0 || lateness > 0)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: totalAbsence >= 3 ? Colors.red : Colors.grey.shade600,
                                                  borderRadius: BorderRadius.circular(6)
                                                ),
                                                constraints: const BoxConstraints(minWidth: 12),
                                                child: Text(
                                                  '欠$absence/遅$lateness', 
                                                  style: const TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.bold), 
                                                  textAlign: TextAlign.center
                                                ),
                                              ),
                                            )
                                        ],
                                      ),
                                    )
                                  : const Center(child: Icon(Icons.add, size: 14, color: Colors.black12)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}


// ==========================================
// 📊 【5. タブ3】成績＆進捗アナリティクス
// ==========================================
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  double _currentGpa = 3.24;
  int _currentCredits = 68;
  int _simulatedAClassesCount = 0;

  @override
  void initState() {
    super.initState();
    _currentGpa = AppStorage.getGpa();
    _currentCredits = AppStorage.getCredits();
  }

  void _runGpaSimulation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            double baseGpa = AppStorage.getGpa();
            int baseCredits = AppStorage.getCredits();

            double baseTotalGp = baseGpa * baseCredits;
            int additionalCredits = _simulatedAClassesCount * 2; 
            double additionalGp = _simulatedAClassesCount * 2 * 4.0; 
            double simulatedGpa = (baseTotalGp + additionalGp) / (baseCredits + additionalCredits);

            return Padding(
              padding: EdgeInsets.only(
                top: 20, left: 20, right: 20, 
                bottom: MediaQuery.of(context).viewInsets.bottom + 20
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('成績シミュレーター', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('未確定の講義がすべて『優 (GP 4.0)』だった場合の総GPAを予測します。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('『優』と仮定する科目数 (各2単位)', style: TextStyle(fontSize: 13)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _simulatedAClassesCount > 0 ? () => setModalState(() => _simulatedAClassesCount--) : null,
                          ),
                          Text('$_simulatedAClassesCount', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => setModalState(() => _simulatedAClassesCount++),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        const Text('シミュレーション結果', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Text('予測通算GPA: ${simulatedGpa.isNaN ? "0.00" : simulatedGpa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                        Text('(取得単位は ${baseCredits + additionalCredits} 単位へ増加)', style: const TextStyle(fontSize: 11, color: Colors.grey))
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        AppStorage.saveGpaAndCredits(simulatedGpa.isNaN ? 0.0 : simulatedGpa, baseCredits + additionalCredits);
                        setState(() {
                          _currentGpa = AppStorage.getGpa();
                          _currentCredits = AppStorage.getCredits();
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('この構成をストレージに保存・反映'),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    int alertCount = AppStorage.getAlertLectures().length;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('通算GPA: ${_currentGpa.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 8),
                      Container(height: 50, color: Colors.grey.shade50, child: const Center(child: Text('[GPA推移バーチャート]', style: TextStyle(fontSize: 11, color: Colors.grey)))),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(value: _currentCredits / 128, strokeWidth: 6, backgroundColor: Colors.grey.shade200, color: alertCount > 0 ? Colors.red : Colors.blue),
                        Text('$_currentCredits/128', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('卒業要件単位', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: alertCount > 0 ? Colors.red.shade50 : Colors.amber.shade50,
          shape: RoundedRectangleBorder(side: BorderSide(color: alertCount > 0 ? Colors.red : Colors.amber.shade300), borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Icon(alertCount > 0 ? Icons.error_outline : Icons.warning_amber_rounded, color: alertCount > 0 ? Colors.red : Colors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alertCount > 0 ? '卒業判定：要注意要請あり' : '現在のペースでの卒業判定：A（安全）', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(alertCount > 0 ? '警告：遅刻・欠席の超過による危険講義が $alertCount 件あります。' : '警告：一般教養の単位が不足するリスクがあります。', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _runGpaSimulation,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('「もしこの科目が優だったら？」成績シミュレーション'),
        )
      ],
    );
  }
}

// ==========================================
// 🔔 【6. サブシステム】通知・アシスト設定
// ==========================================
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text('通知・アシスト設定', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        SwitchListTile(
          title: const Text('講義開始前のリマインド', style: TextStyle(fontSize: 14)),
          value: true, onChanged: (val) {},
        ),
        SwitchListTile(
          title: const Text('出席忘れ防止アラート', style: TextStyle(fontSize: 14)),
          value: true, onChanged: (val) {},
        ),
      ],
    );
  }
}