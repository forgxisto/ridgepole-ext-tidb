# Ridgepole::Ext::Tidb

![Tests](https://github.com/forgxisto/ridgepole-ext-tidb/actions/workflows/test.yml/badge.svg)
![Ruby Version](https://img.shields.io/badge/ruby-3.1%2B-red)
![TiDB Compatibility](https://img.shields.io/badge/TiDB-v7.5.0%2B-blue)

TiDBの`AUTO_RANDOM`カラム属性をサポートするRidgepole拡張機能です。この拡張により、TiDBの分散IDジェネレーション機能をSchemafile管理に統合できます。

## 主な機能

- **AUTO_RANDOM適用**: CREATE時に`AUTO_RANDOM(n)`を列定義へ付与し、`AUTO_INCREMENT`を抑止
- **AUTO_RANDOM_BASE**: テーブルオプションに`AUTO_RANDOM_BASE=<n>`を付与
- **スキーマダンプ対応**: `create_table`のオプションへ`auto_random:`/`auto_random_base:`を出力（往復一致）
- **冪等性**: apply→export→diff→applyの繰り返しでも差分ゼロを維持（ALTERは不使用）
- **TiDB判定**: 接続先がTiDBかどうかを自動判定
- **MySQL互換**: mysql2 / trilogy アダプターの両方に対応
- **Ruby 3.1+ 対応**

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
require 'ridgepole/ext_tidb'

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
require "ridgepole/ext_tidb"

# 1) テーブルレベルでAUTO_RANDOMとAUTO_RANDOM_BASEを指定
create_table "users",
  id: :bigint,
  auto_random: 5,
  auto_random_base: 100_000,
  options: "DEFAULT CHARSET=utf8mb4" do |t|
  t.string :name, null: false
end

# 2) 手動PK（カラム側でAUTO_RANDOMを指定）
create_table "events", id: false, options: "DEFAULT CHARSET=utf8mb4" do |t|
  t.bigint :id, primary_key: true, null: false, auto_random: 6
  t.string :title, null: false
end
```

出力（export）は`create_table`のオプションに`auto_random:`/`auto_random_base:`を含めて往復一致となります（ALTERは使用しません）。

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

- TiDB: v7.5.0 以降
- ActiveRecord: 7 / 8 系
- Ridgepole: 3.0.4 以降
- アダプター: mysql2 / trilogy

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

既存テーブルからのダンプ時、SHOW CREATE を解析して `create_table` のオプションに
`auto_random:` と `auto_random_base:` を出力します。apply→export→diff→apply の繰り返しでも差分は発生しません。

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

このリポジトリのRSpecは、実行時に自動で TiDB コンテナ（docker compose）を起動・停止します。事前の手動起動は不要です。

前提: Docker と docker compose が使用可能で、ポート `14000` が空いていること。

```bash
# 統合テスト（TiDBを自動起動）
$ bundle exec rspec --format documentation

# アダプタを切り替えたい場合（デフォルトは trilogy）
# ※ mysql2 を使う場合は、別途 mysql2 をインストールしてください
$ AR_ADAPTER=mysql2 bundle exec rspec --format documentation
```

ヒント: コンテナを手動で起動しておきたい場合は `docker compose up -d tidb` を先に実行しても構いません（テストはそのまま動作します）。

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
