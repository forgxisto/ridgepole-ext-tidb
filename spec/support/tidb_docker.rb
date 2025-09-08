# frozen_string_literal: true
require "open3"

module TiDBDocker
  module_function

  def ensure_up!
    run!("docker compose up -d tidb")
    # ポートが開いても MySQL ハンドシェイク前だと失敗するため、
    # Ruby 側（trilogy または mysql2）で実クエリが通ることを確認して待機する。
    wait_until(180, 2) { ruby_mysql_ok? }
    puts "[TiDBDocker] ready on 127.0.0.1:14000"
  end

  # Ruby（ホスト側）から TiDB へ接続できるかを確認
  def ruby_mysql_ok?
    # trilogy のみを使用（CI/ローカルともに mysql2 へフォールバックしない）
    begin
      require 'trilogy'
      c = Trilogy.new(host: '127.0.0.1', port: 14000, username: 'root')
      c.query('SELECT 1')
      c.close
      true
    rescue Exception
      false
    end
  end

  def down!
    run!("docker compose down -v")
  rescue StandardError
  end

  # ---- ここから下は補助関数 ----

  def run!(cmd)
    puts "[TiDBDocker] #{cmd}"
    system(cmd) || raise("failed: #{cmd}")
  end

  def wait_until(timeout_sec, interval_sec)
    start = Time.now
    until yield
      raise "timeout after #{timeout_sec}s" if Time.now - start > timeout_sec
      sleep interval_sec
      print "." # 進捗が分かるように
    end
    puts
  end

  def tcp_open?(host, port)
    require "socket"
    Socket.tcp(host, port, connect_timeout: 1) { true }
  rescue
    false
  end

  def can_connect_mysql2?
    require "mysql2"
    Mysql2::Client.new(host: "127.0.0.1", port: 14000, username: "root").close
    true
  rescue
    false
  end
end
