#!/bin/bash

# 🚨 【設定】あなたのGitHubユーザー名とリポジトリ名に書き換えてください
GITHUB_USER="itoshiyou"
REPO_NAME="uniflow_miyazaki"

echo "🚀 [1/4] 古いキャッシュをクリーンアップ中..."
flutter clean

echo "📦 [2/4] パッケージをインポート中..."
flutter pub get

echo "🏗️ [3/4] GitHub Pages用にWebビルド中..."
flutter build web --base-href "/$REPO_NAME/"

echo "🌐 [4/4] build/web の中身を GitHub (gh-pages ブランチ) へ直接デプロイ中..."
# build/web フォルダへ移動
cd build/web

# 臨時のgitリポジトリを作って強引に gh-pages ブランチへ上書きプッシュします
git init
git add .
git commit -m "Deploy: 自動一括ビルドデプロイ"
git branch -M gh-pages
git remote add origin https://github.com/$GITHUB_USER/$REPO_NAME.git

# 強制上書きプッシュ
git push -u origin gh-pages -f

echo "✨ 完了しました！数分後に以下のURLでアプリが更新されます："
echo "👉 https://$GITHUB_USER.github.io/$REPO_NAME/"