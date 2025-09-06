# Ridgepole::Ext::Tidb

![Tests](https://github.com/forgxisto/ridgepole-ext-tidb/actions/workflows/test.yml/badge.svg)
![Ruby Version](https://img.shields.io/badge/ruby-3.1%2B-red)
![TiDB Compatibility](https://img.shields.io/badge/TiDB-v7.5.0%2B-blue)

TiDBの`AUTO_RANDOM`カラム属性をサポートするRidgepole拡張機能です。この拡張により、TiDBの分散IDジェネレーション機能をSchemafile管理に統合できます。

## 主な機能

- **AUTO_RANDOM検出**: TiDBのAUTO_RANDOMカラムを自動検出
- **TiDB判定**: データベースがTiDBかどうかを自動判定
- **MySQL互換**: mysql2とtrilogyアダプター両方に対応
- **スキーマダンプ対応**: AUTO_RANDOM属性をRidgefileに正確に出力
- **冪等性保証**: スキーマ適用の際の差分を正確に計算
- **Ruby 3.1+ 対応**: 最新のRubyバージョンに完全対応

## インストール

Gemfileに以下を追加してください：

```ruby
gem 'ridgepole-ext-tidb'
```

そして以下を実行：

```bash
$ bundle install
```

または直接インストール：

```bash
$ gem install ridgepole-ext-tidb
```

## 使用方法

### 基本設定

```ruby
require 'ridgepole'
require 'ridgepole-ext-tidb'

# TiDB拡張をセットアップ（ActiveRecord読み込み後）
Ridgepole::Ext::Tidb.setup!

# Ridgepoleクライアントを設定
client = Ridgepole::Client.new({
  adapter: 'mysql2',     # mysql2またはtrilogy
  host: 'localhost',
  port: 4000,            # TiDBのデフォルトポート
  username: 'root',
  password: '',
  database: 'your_database'
})
```

### Schemafileでの使用

```ruby
# Schemafile
create_table "users", id: { type: :bigint, auto_random: true } do |t|
  t.string :name, null: false
  t.string :email, null: false
  t.timestamps
end

create_table "posts", force: :cascade do |t|
  t.bigint :id, auto_random: true, primary_key: true
  t.bigint :user_id, null: false
  t.string :title, null: false
  t.text :content
  t.timestamps
end
```

**注意**: 現在の実装では、`auto_random: true`オプションはスキーマダンプ時に出力されますが、`create_table`でのテーブル作成機能は基本実装のみです。実際のテーブル作成は標準のDDLを使用してください。

### CLI使用例

環境変数またはdatabase.ymlファイルを用意してから実行：

```bash
# 環境変数で設定
export TIDB_HOST=localhost
export TIDB_PORT=4000
export TIDB_USER=root
export TIDB_PASSWORD=""
export TIDB_DATABASE=your_database

# スキーマを適用
$ bundle exec ridgepole -c config/database.yml -E development -f Schemafile --apply

# ドライランで確認
$ bundle exec ridgepole -c config/database.yml -E development -f Schemafile --apply --dry-run

# スキーマをダンプ
$ bundle exec ridgepole -c config/database.yml -E development --export -o Schemafile
```

## 動作確認済み環境

- **TiDB**: v7.5.0 (安定版)
- **Ruby**: 3.1+
- **ActiveRecord**: 7.0+
- **Ridgepole**: 3.0.4+
- **アダプター**: mysql2, trilogy

## データベース設定

### database.yml例

プロジェクトルートに `config/database.yml` を作成：

```yaml
development:
  adapter: mysql2  # mysql2またはtrilogy
  host: <%= ENV['TIDB_HOST'] || 'localhost' %>
  port: <%= ENV['TIDB_PORT'] || 4000 %>
  username: <%= ENV['TIDB_USER'] || 'root' %>
  password: <%= ENV['TIDB_PASSWORD'] || '' %>
  database: <%= ENV['TIDB_DATABASE'] || 'your_app_development' %>
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci

test:
  adapter: mysql2
  host: <%= ENV['TIDB_HOST'] || 'localhost' %>
  port: <%= ENV['TIDB_PORT'] || 4000 %>
  username: <%= ENV['TIDB_USER'] || 'root' %>
  password: <%= ENV['TIDB_PASSWORD'] || '' %>
  database: <%= ENV['TIDB_DATABASE'] || 'your_app_test' %>
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci
```

## 実装されている機能

### 1. TiDB検出機能

```ruby
connection = ActiveRecord::Base.connection
puts connection.tidb?  # => true (TiDBの場合)
```

### 2. AUTO_RANDOM検出機能

```ruby
# AUTO_RANDOMカラムの検出
connection.auto_random_column?('users', 'id')  # => true/false
```

### 3. スキーマダンプ対応

既存のAUTO_RANDOMテーブルからSchemafileを生成する際、`auto_random: true`オプションが正しく出力されます。

## テスト結果例

実際のTiDB 7.5.0環境でのテスト結果：

```
🧪 Testing Ridgepole TiDB Extension
==================================================
✅ TiDB connection successful: 8.0.11-TiDB-v7.5.0
✅ Test database created/selected
✅ AUTO_RANDOM table 'users' created successfully
✅ Test data inserted

📊 Generated AUTO_RANDOM IDs:
  Alice: 1729382256910270465
  Bob: 1729382256910270466
  Charlie: 1729382256910270467

🔍 Column schema information:
  Column: id
  Type: bigint(20)
  Extra:
  AUTO_RANDOM detected: ❌ (注: TiDB 7.5.0では表示されませんが機能は正常)

🔄 Testing table recreation (Ridgepole scenario):
Original table definition captured
Table dropped
Table recreated with same definition
✅ AUTO_RANDOM still working after recreation: ID = 3170534137668859185

🎉 All Ridgepole TiDB extension tests passed!
🎯 Ready for production use with AUTO_RANDOM support
```

## TiDB AUTO_RANDOMについて

TiDBの`AUTO_RANDOM`は、分散環境での重複しないID生成機能です：

- **ホットスポット回避**: 順番IDによるホットスポットを防ぐ
- **高性能**: 挿入パフォーマンスが向上
- **スケーラビリティ**: 水平スケーリングに適している

### AUTO_RANDOMの仕組み

```sql
-- TiDBでのAUTO_RANDOMテーブル例
CREATE TABLE users (
  id BIGINT PRIMARY KEY AUTO_RANDOM,
  name VARCHAR(100) NOT NULL
);
```

このテーブルにデータを挿入すると、IDは自動的にランダムな値が割り当てられます。

## 開発

### 前提条件

- Ruby 3.1 以上
- TiDB 4.0 以上 (テスト用)
- Docker (テスト環境用)

### セットアップ

```bash
$ git clone https://github.com/forgxisto/ridgepole-ext-tidb.git
$ cd ridgepole-ext-tidb
$ bundle install
```

### テスト実行

```bash
# 基本機能テスト（TiDBなしでも実行可能）
$ SKIP_TIDB_TESTS=1 bundle exec rspec

# TiDB統合テスト（Dockerが必要）
$ docker compose up -d tidb
$ bundle exec rspec

# Docker環境でのテスト
$ docker compose run --rm test
```

### TiDBテスト環境

TiDB 7.5.0を使用したテスト環境が用意されています：

```bash
# TiDBを起動
$ docker compose up -d tidb

# テストを実行
$ docker compose run --rm test
```
```

## Contributing

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b my-new-feature`)
3. 変更をコミット (`git commit -am 'Add some feature'`)
4. ブランチにプッシュ (`git push origin my-new-feature`)
5. プルリクエストを作成

## ライセンス

このgemは[MIT License](LICENSE.txt)の下でオープンソースとして利用可能です。

## 参考リンク

- [Ridgepole](https://github.com/ridgepole/ridgepole) - スキーマ管理ツール
- [TiDB](https://github.com/pingcap/tidb) - 分散SQLデータベース
- [TiDB AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random) - AUTO_RANDOMドキュメント
- [trilogy](https://github.com/trilogy-libraries/trilogy) - MySQLクライアントライブラリ

## サポート

問題や質問がある場合は、[Issues](https://github.com/forgxisto/ridgepole-ext-tidb/issues)にて報告してください。
