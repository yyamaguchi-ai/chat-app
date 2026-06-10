# chat-app

リアルタイムチャットアプリ（Flutter + Laravel）

---

## 開発環境

### バックエンド
| 項目 | バージョン |
|------|-----------|
| PHP | 8.2 |
| Laravel | 12.0 |
| Laravel Sanctum（認証） | 4.0 |
| Pusher PHP Server（リアルタイム） | 7.0 |
| Web サーバー | Nginx (alpine) |
| DB | MySQL 8.0 |

### フロントエンド（Flutter）
| 項目 | バージョン |
|------|-----------|
| Dart SDK | >=3.2.0 <4.0.0 |
| flutter_riverpod（状態管理） | 2.5.0 |
| dio（HTTP通信） | 5.4.0 |
| go_router（画面遷移） | 13.2.0 |
| pusher_channels_flutter（リアルタイム） | 2.0.0 |
| flutter_secure_storage（トークン保存） | 9.0.0 |

### インフラ
- Docker Compose（nginx + php-fpm + mysql）
- データ永続化：Docker 名前付きボリューム（`chat-app_mysql_data`）
- バックエンド API：`localhost:8000`
- DB ポート：`3306`

---

## 環境構築手順（初回）

### 事前に必要なツール

| ツール | 用途 |
|--------|------|
| [Git](https://git-scm.com/) | リポジトリ管理 |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | バックエンド起動 |
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | フロントエンド起動 |
| [Android Studio](https://developer.android.com/studio) | エミュレーターで確認する場合のみ |

### 1. リポジトリをクローン

```bash
git clone <リポジトリURL>
cd chat-app
```

### 2. バックエンドの `.env` を作成

```bash
# Mac / Linux
cp backend/.env.example backend/.env

# Windows（PowerShell）
Copy-Item backend/.env.example backend/.env
```

作成した `backend/.env` を開き、以下の箇所を書き換える：

```env
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=chat_app
DB_USERNAME=chat_user
DB_PASSWORD=secret

BROADCAST_CONNECTION=pusher
PUSHER_APP_ID=（担当者に確認）
PUSHER_APP_KEY=（担当者に確認）
PUSHER_APP_SECRET=（担当者に確認）
PUSHER_APP_CLUSTER=ap3
```

### 3. フロントエンドに Pusher キーを設定

`frontend/lib/core/services/pusher_service.dart` を開き、以下の箇所を書き換える：

```dart
static const _appKey  = '（担当者に確認）';
static const _cluster = 'ap3';
```

### 4. Docker を起動

```bash
docker compose up -d
```

### 5. アプリキー生成とマイグレーション

```bash
docker compose exec php php artisan key:generate
docker compose exec php php artisan migrate
```

### 6. フロントエンドを起動

```bash
cd frontend
flutter run
```

---

## 通常の起動方法

### バックエンド
```bash
docker compose up -d
```

### フロントエンド
```bash
cd frontend
flutter run
```

---

## 動作確認の方法

### 方法 1：ブラウザ（Chrome）で確認する

Docker を起動した状態で以下を実行：

```bash
cd frontend
flutter run -d chrome
```

- Flutter・Docker があれば Android Studio 不要
- スマホ向けレイアウトのためデザインが崩れる場合があります

---

### 方法 2：GitHub Codespaces で確認する

> **注意**：Codespaces は**この PC に**Git・Docker・Flutter をインストールしなくて済む方法です。ただし Codespaces の環境（クラウド上の Linux）に Flutter などを毎回セットアップする必要があります。起動のたびに手順が必要なため、手軽さでは方法1（ローカルの Chrome）の方が上です。

1. GitHub のリポジトリページを開く
2. 「Code」→「Codespaces」→「Create codespace on main」
3. ブラウザ上で VS Code が起動したら以下を順番に実行：

**バックエンドのセットアップ**
```bash
docker compose up -d
docker compose exec php composer install
docker compose exec php php artisan key:generate
docker compose exec php php artisan migrate
```

**Flutter のインストール（Codespaces 環境内に毎回必要）**
```bash
git clone https://github.com/flutter/flutter.git -b stable ~/.flutter
export PATH="$PATH:$HOME/.flutter/bin"
flutter precache --web
```

**アプリの起動**
```bash
cd frontend
flutter run -d chrome
```

- エミュレーターは使用できないため Chrome のみになります
- `.env` と `pusher_service.dart` のキー設定は別途必要です

---

### 方法 3：APK をスマホにインストールして確認する

**事前準備：接続先 IP アドレスの確認**

`frontend/lib/core/services/api_service.dart` の `_baseUrl` がこの PC の IP アドレスになっているか確認する：

```dart
static const _baseUrl = 'http://<このPCのIPアドレス>:8000/api';
```

PC の IP アドレスは以下で確認できます：
```bash
# Windows
ipconfig
```

**APK のビルドと転送**

```bash
cd frontend
flutter build apk --debug
```

ビルドが完了すると `frontend/build/app/outputs/flutter-apk/app-debug.apk` にファイルが生成されます。このファイルをスマホに転送してインストールします。

**スマホ側の設定**

1. 設定 →「セキュリティ」→「提供元不明のアプリのインストール」を許可
2. APK ファイルを開いてインストール

**注意：バックエンドの起動とネットワーク**

- アプリ使用中はこの PC で `docker compose up -d` が起動している必要があります
- スマホとこの PC が**同じ Wi-Fi** に接続している必要があります

---

## 注意

- `docker compose down -v` を実行するとDBデータ（ユーザーアカウント含む）が**すべて消えます**。通常の停止は `docker compose down` を使ってください。
- Pusher のキーは `.env.example` に含まれていないため、担当者に確認してください。
- DBデータはこの PC 内の Docker ボリューム（`chat-app_mysql_data`）に保存されています。PC を初期化すると消えます。
