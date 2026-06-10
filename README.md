# chat-app

リアルタイムチャットアプリ（Flutter + Laravel）

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

## 起動方法

### バックエンド
```bash
docker compose up -d
```

### フロントエンド
```bash
cd frontend
flutter run
```

## 注意
- `docker compose down -v` を実行するとDBデータ（ユーザーアカウント含む）が消えます
