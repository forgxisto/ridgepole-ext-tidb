# frozen_string_literal: true

require 'bundler/setup'

# Ruby 3.4+ compatibility - must be loaded BEFORE other gems
require 'logger'
require 'mutex_m'
require 'bigdecimal'
require 'benchmark'

# Load mysql2 and ActiveRecord
require 'mysql2'
require 'active_record'

require 'ridgepole'
require 'ridgepole-ext-tidb'

# Setup TiDB extension
puts "🔧 Setting up TiDB extension in spec_helper..."
Ridgepole::Ext::Tidb.setup!
puts "🔧 TiDB extension setup completed in spec_helper"

# Debug: Check if methods are actually added
if defined?(ActiveRecord::ConnectionAdapters::Mysql2Adapter)
  mysql2_methods = ActiveRecord::ConnectionAdapters::Mysql2Adapter.instance_methods
  puts "🔍 Mysql2Adapter has tidb? method: #{mysql2_methods.include?(:tidb?)}"
  puts "🔍 Mysql2Adapter has auto_random_column? method: #{mysql2_methods.include?(:auto_random_column?)}"
else
  puts "⚠️  Mysql2Adapter not defined"
end

# Test database configuration
TEST_CONFIG = {
  adapter: 'mysql2',
  host: ENV['TIDB_HOST'] || 'localhost',
  port: (ENV['TIDB_PORT'] || 4000).to_i,
  username: ENV['TIDB_USER'] || 'root',
  password: ENV['TIDB_PASSWORD'] || '',
  database: ENV['TIDB_DATABASE'] || 'ridgepole_test'
}.freeze

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Skip TiDB tests if not available
  config.before(:suite) do
    puts 'Skipping TiDB tests (SKIP_TIDB_TESTS is set)' if ENV['SKIP_TIDB_TESTS']
  end

  # Clean up after TiDB tests
  config.after(:each, :tidb) do
    next if ENV['SKIP_TIDB_TESTS']

    begin
      ActiveRecord::Base.establish_connection(TEST_CONFIG)
      connection = ActiveRecord::Base.connection

      test_tables = %w[test_users test_posts test_auto_random]
      test_tables.each do |table|
        connection.execute("DROP TABLE IF EXISTS #{table}")
      rescue StandardError
        # Ignore cleanup errors
      end
    rescue StandardError
      # Ignore connection errors during cleanup
    end
  end
end

# Helper to skip tests if TiDB is not available
def skip_unless_tidb
  skip 'TiDB not available (set SKIP_TIDB_TESTS=1 to skip)' if ENV['SKIP_TIDB_TESTS']

  # Test connection
  begin
    puts "Connecting to TiDB: #{TEST_CONFIG[:host]}:#{TEST_CONFIG[:port]}"
    ActiveRecord::Base.establish_connection(TEST_CONFIG)
    connection = ActiveRecord::Base.connection
    connection.execute('SELECT 1')

    # Check database version for debugging
    version_result = connection.execute('SELECT VERSION()')
    version = version_result.first[0] if version_result.respond_to?(:first)
    puts "Connected to database version: #{version}"

    # Debug: Check if tidb? method exists
    puts "Connection class: #{connection.class}"
    puts "tidb? method available: #{connection.respond_to?(:tidb?)}"

    # 手動でアダプタ拡張を確実に実行
    unless connection.respond_to?(:tidb?)
      puts "🔧 Manually extending adapter at test time..."
      Ridgepole::Ext::Tidb.extend_connection_adapter(connection)
    end

    # Verify it's actually TiDB
    tidb_result = connection.tidb?
    puts "TiDB detection result: #{tidb_result}"

    unless tidb_result
      puts "❌ TiDB detection failed - not recognized as TiDB instance"
      skip 'Not connected to TiDB instance'
    end

    puts "✅ Successfully connected to TiDB"
  rescue StandardError => e
    puts "❌ Database connection failed: #{e.message}"
    puts e.backtrace.first(5).join("\n") if e.backtrace
    skip "Database connection failed: #{e.message}"
  end
end
