# frozen_string_literal: true
module DBHelpers
  module_function

  HOST = "127.0.0.1"
  PORT = 14000
  USER = "root"
  PASS = nil
  DB   = "ridgepole_ext_tidb_test"

  # trilogy をデフォルトに。必要なら AR_ADAPTER=mysql2 で上書き可
  def base_config(overrides = {})
    {
      adapter:  ENV.fetch("AR_ADAPTER", "trilogy"),
      host:     HOST,
      port:     PORT,
      username: USER,
      password: PASS,
      encoding: "utf8mb4",
      prepared_statements: false, # trilogyはこれで安定
    }.merge(overrides)
  end

  def establish!(with_db: true)
    cfg = with_db ? base_config(database: DB) : base_config
    ActiveRecord::Base.establish_connection(cfg)
  end

  def prepare_database!
    # 1) DBなしで接続 → CREATE DATABASE
    establish!(with_db: false)
    conn = ActiveRecord::Base.connection
    conn.execute("CREATE DATABASE IF NOT EXISTS `#{DB}`")
    # 2) DBありで再接続
    establish!(with_db: true)
    ActiveRecord::Base.connection.execute("USE `#{DB}`")
  end

  def drop_all_tables!
    establish!(with_db: true)
    conn = ActiveRecord::Base.connection
    conn.tables.each { |t| conn.execute("DROP TABLE IF EXISTS `#{t}`") }
  rescue ActiveRecord::NoDatabaseError
    # DBが存在しないなら何もしない
  end

  def ridgepole_client
    # Ridgepole::Client は DB 指定が必要なので、prepare_database! 後に呼ぶこと
    Ridgepole::Client.new(base_config(database: DB), enable_foreign_key: false)
  end

  def show_create(table)
    establish!(with_db: true)
    row = ActiveRecord::Base.connection.select_one("SHOW CREATE TABLE `#{table}`")
    row["Create Table"] || row.values[1]
  end
end
