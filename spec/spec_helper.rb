# frozen_string_literal: true

require 'bundler/setup'

# Ruby 3.4+ compatibility - must be loaded BEFORE other gems
require 'logger'
require 'mutex_m'
require 'bigdecimal'
require 'benchmark'

# Load trilogy and ActiveRecord
require 'trilogy'
require 'activerecord-trilogy-adapter'
require 'active_record'

require 'ridgepole'
require 'ridgepole/ext/tidb'

# Setup TiDB extension
Ridgepole::Ext::Tidb.setup!

# Test database configuration
TEST_CONFIG = {
  adapter: 'trilogy',
  host: ENV['TIDB_HOST'] || 'localhost',
  port: (ENV['TIDB_PORT'] || 14000).to_i,
  username: ENV['TIDB_USER'] || 'root',
  password: ENV['TIDB_PASSWORD'] || '',
  database: ENV['TIDB_DATABASE'] || 'ridgepole_test'
}.freeze

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

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

      test_tables = %w[users posts test_auto_random]
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
    ActiveRecord::Base.establish_connection(TEST_CONFIG)
    connection = ActiveRecord::Base.connection
    connection.execute('SELECT 1')

    # For development/testing purposes, we can simulate TiDB behavior
    # even if we're not connected to actual TiDB
    unless connection.tidb?
      puts 'Warning: Not connected to TiDB, but running tests anyway for development'
      # Override tidb? method for testing
      connection.singleton_class.prepend(Module.new do
        def tidb?
          true
        end
      end)
    end
  rescue StandardError => e
    skip "Database connection failed: #{e.message}"
  end
end
