import re
import json
import time
import requests
from bs4 import BeautifulSoup

from datetime import datetime

def get_current_academic_year():
    # 現在の日付を取得
    now = datetime.now()
    current_year = now.year
    current_month = now.month

    # 1月〜3月の場合は、前年の年度になるため1を引く
    if current_month in [1, 2, 3]:
        academic_year = current_year - 1
    else:
        academic_year = current_year

    return academic_year


# ==============================================================================
# 設定項目
# ==============================================================================
YEAR = get_current_academic_year()  # クローリング対象の年度（例: 2024）
BASE_URL = "https://syllabus.eden.miyazaki-u.ac.jp/syllabus"
# GitHub Actions実行時（プロジェクトルート）から見た出力先パス
OUTPUT_FILE = "web/assets/syllabus_master.json"

# 曜日文字列をFlutterの曜日インデックス（0=月, 1=火, 2=水, 3=木, 4=金）にマッピング
DAY_MAP = {"月": 0, "火": 1, "水": 2, "木": 3, "金": 4}

def parse_schedule(schedule_str):
    """
    開講日時（例: "前期 火 ３・４時限" や "後期 木 １・２時限"）の文字列から、
    アプリがパースしやすい形式のインデックス（dayIdx, periodIdx）を抽出する関数。
    """
    day_idx = None
    period_idx = None
    
    # 1. 曜日インデックスの特定
    for day_name, idx in DAY_MAP.items():
        if day_name in schedule_str:
            day_idx = idx
            break
            
    # 2. 時限インデックスの特定（全角数字を考慮）
    # 宮崎大学の通常の時間割マトリクス（1限〜5限）に適合させるマッピング
    if "１" in schedule_str:
        period_idx = 0  # 1限（Flutter上のインデックス0）
    elif "３" in schedule_str:
        period_idx = 1  # 2限（Flutter上のインデックス1、※3・4時限連続講義などの場合）
    elif "５" in schedule_str:
        period_idx = 2  # 3限（Flutter上のインデックス2）
    elif "７" in schedule_str:
        period_idx = 3  # 4限（Flutter上のインデックス3）
    elif "９" in schedule_str:
        period_idx = 4  # 5限（Flutter上のインデックス4）
        
    return day_idx, period_idx

def crawl_syllabus(nendo):
    syllabus_data = {}
    page = 1
    
    print(f"--- {nendo}年度 宮崎大学シラバス全件取得を開始します ---")
    
    while True:
        url = f"{BASE_URL}?searchSubmit=1&kaiko_nendo={nendo}&page={page}"
        print(f"処理中: ページ {page} をロードしています...")
        
        try:
            # ページリクエストの送信
            response = requests.get(url, timeout=15)
            response.encoding = 'utf-8'
            
            # 【前提条件の判定】ページが範囲外になった際の404エラー、または特定の不検出テキストを検知したら終了
            if response.status_code == 404 or "was not found on this server" in response.text or "Not Found" in response.text:
                print(f"ページ {page} にてNot Foundを確認しました。クローリングを正常終了します。")
                break
                
            soup = BeautifulSoup(response.text, "html.parser")
            
            # 宮崎大学シラバス検索のPC用結果テーブル（table-bordered）を抽出
            table = soup.find("table", class_="table-bordered")
            if not table:
                print("Error: 結果テーブル(table-bordered)がHTML内に見つかりません。")
                break
                
            tbody = table.find("tbody")
            if not tbody:
                print("Warning: テーブルのtbodyが空です。")
                break
                
            rows = tbody.find_all("tr")
            if not rows:
                print(f"ページ {page} のデータ行(tr)が0件のため終了します。")
                break
                
            # 取得した行をループ処理
            for row in rows:
                cols = row.find_all("td")
                # 必要なカラム数（最低8列以上）が確保されているか検証
                if len(cols) < 8:
                    continue
                
                # 生HTML構造の列インデックスからデータを正確にマッピング
                # cols[0]: 詳細リンク, cols[1]: 開講年度, cols[2]: 時間割コード...
                code = cols[2].text.strip()           # 時間割コード (例: ksf91)
                title = cols[3].text.strip()          # 授業科目名 (例: 教養中国語II)
                professor = cols[4].text.strip()      # 担当教員名 (例: 三好 慎一郎)
                schedule_str = cols[6].text.strip()   # 開講日時 (例: 後期 火 ３・４時限)
                classification = cols[7].text.strip() # 講義分類 (例: 学部共通・共通教育等)
                
                # 科目区分の判定（講義分類の文脈に"教養教育"が含まれていれば教養、それ以外は専門とする）
                course_type = "liberal" if "教養教育" in classification else "major"
                
                # アプリのグリッドに自動マッピングするためのインデックス計算
                day_idx, period_idx = parse_schedule(schedule_str)
                
                # 時間割コード(code)をキーとした検索用Key-Valueオブジェクトを構築
                syllabus_data[code] = {
                    "id": code,
                    "title": title,
                    "room": "未特定（シラバス詳細を参照）", # 教室名は一覧にないため固定
                    "professor": professor,
                    "type": course_type,
                    "evaluation": "シラバスの評価基準を確認してください。",
                    "dayIdx": day_idx,
                    "periodIdx": period_idx,
                    "rawSchedule": schedule_str
                }
                
            # 大学サーバーへの急激な負荷を防ぐため、1ページごとにウェイトを入れる（マナー）
            time.sleep(1.5)
            page += 1
            
        except Exception as e:
            print(f"ページ {page} の処理中に予期せぬエラーが発生しました: {e}")
            break
            
    return syllabus_data

if __name__ == "__main__":
    # クローリングの実行
    master_json_data = crawl_syllabus(YEAR)
    
    # 抽出したデータの存在チェック
    if master_json_data:
        # 指定されたFlutter PWAのアセットディレクトリへJSON形式で保存
        with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
            json.dump(master_json_data, f, ensure_ascii=False, indent=2)
            
        print(f"【処理完了】合計 {len(master_json_data)} 件のシラバスデータを '{OUTPUT_FILE}' に保存しました。")
    else:
        print("エラー: 講義データが1件も取得できなかったため、ファイル書き出しをスキップしました。")