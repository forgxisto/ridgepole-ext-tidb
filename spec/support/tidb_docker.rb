# frozen_string_literal: true
require "open3"

module TiDBDocker
  module_function

  def ensure_up!
    run!("docker compose up -d tidb")
    wait_until(120, 2) do
      tcp_open?("127.0.0.1", 14000) && docker_mysql_ok?
    end
    puts "[TiDBDocker] ready on 127.0.0.1:14000"
  end

  def docker_mysql_ok?
    system(
      "docker", "run", "--rm", "mysql:8.0",
      "mysql", "-h", "host.docker.internal", "-P14000", "-uroot",
      "-e", "SELECT 1",
      out: File::NULL, err: File::NULL
    )
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
