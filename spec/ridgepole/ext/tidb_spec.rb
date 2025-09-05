# frozen_string_literal: true

RSpec.describe Ridgepole::Ext::Tidb do
  describe 'module loading and setup' do
    it 'has a version number' do
      expect(Ridgepole::Ext::Tidb::VERSION).not_to be_nil
      expect(Ridgepole::Ext::Tidb::VERSION).to be_a(String)
      expect(Ridgepole::Ext::Tidb::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end

    it 'defines the expected constants' do
      expect(defined?(Ridgepole::Ext::Tidb::Error)).to be_truthy
      expect(defined?(Ridgepole::Ext::Tidb::SchemaDumper)).to be_truthy
      expect(defined?(Ridgepole::Ext::Tidb::ConnectionAdapters)).to be_truthy
    end

    it 'can call setup! without error' do
      expect { described_class.setup! }.not_to raise_error
    end

    it 'loads trilogy adapter when available' do
      # This test verifies that the setup doesn't fail even if trilogy is not available
      expect { described_class.setup! }.not_to raise_error
    end
  end

  describe 'TiDB connection detection' do
    let(:mock_connection) { double('connection') }

    context 'when @@tidb_version query succeeds' do
      it 'detects TiDB correctly' do
        allow(mock_connection).to receive(:select_value).with('SELECT @@tidb_version').and_return('5.0.0')

        connection_class = Class.new do
          include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          def self.select_value(sql); end
        end

        allow(connection_class).to receive(:select_value).with('SELECT @@tidb_version').and_return('5.0.0')
        expect(connection_class.tidb?).to be true
      end
    end

    context 'when VERSION() query contains TiDB' do
      it 'detects TiDB correctly' do
        connection_class = Class.new do
          include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          def self.select_value(sql); end
        end

        allow(connection_class).to receive(:select_value).with('SELECT @@tidb_version').and_raise(StandardError)
        allow(connection_class).to receive(:select_value).with('SELECT VERSION()').and_return('5.7.25-TiDB-v5.0.0')

        expect(connection_class.tidb?).to be true
      end
    end

    context 'when no TiDB indicators found' do
      it 'returns false' do
        connection_class = Class.new do
          include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          def self.select_value(sql); end
        end

        allow(connection_class).to receive(:select_value).with('SELECT @@tidb_version').and_raise(StandardError)
        allow(connection_class).to receive(:select_value).with('SELECT VERSION()').and_return('5.7.25-MySQL')
        allow(connection_class).to receive(:select_value).with("SHOW VARIABLES LIKE 'version_comment'").and_return('MySQL')

        expect(connection_class.tidb?).to be false
      end
    end

    context 'when queries fail' do
      it 'returns false gracefully' do
        connection_class = Class.new do
          include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          def self.select_value(sql); end
        end

        allow(connection_class).to receive(:select_value).and_raise(StandardError, 'Connection failed')

        expect(connection_class.tidb?).to be false
      end
    end
  end

  describe 'AUTO_RANDOM column detection' do
    let(:mock_connection) do
      double('connection').tap do |conn|
        allow(conn).to receive(:tidb?).and_return(true)
        allow(conn).to receive(:quote).and_return('"test_table"', '"id"')
      end
    end

    let(:adapter_instance) do
      Class.new do
        include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
        def connection; end
        def select_value(sql); end
        def quote(value); end
      end.new
    end

    before do
      allow(adapter_instance).to receive(:tidb?).and_return(true)
      allow(adapter_instance).to receive(:quote).and_return('"test_table"', '"id"')
    end

    context 'when column has AUTO_RANDOM attribute' do
      it 'detects AUTO_RANDOM correctly' do
        allow(adapter_instance).to receive(:select_value).and_return('auto_random')
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be true
      end

      it 'handles case insensitive detection' do
        allow(adapter_instance).to receive(:select_value).and_return('AUTO_RANDOM')
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be true
      end
    end

    context 'when column does not have AUTO_RANDOM attribute' do
      it 'returns false' do
        allow(adapter_instance).to receive(:select_value).and_return('auto_increment')
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be false
      end

      it 'returns false for nil result' do
        allow(adapter_instance).to receive(:select_value).and_return(nil)
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be false
      end
    end

    context 'when not connected to TiDB' do
      it 'returns false' do
        allow(adapter_instance).to receive(:tidb?).and_return(false)
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be false
      end
    end

    context 'when query fails' do
      it 'returns false gracefully' do
        allow(adapter_instance).to receive(:select_value).and_raise(StandardError, 'Query failed')
        expect(adapter_instance.auto_random_column?('test_table', 'id')).to be false
      end
    end
  end

  describe 'AUTO_RANDOM constraint validation' do
    let(:adapter_instance) do
      Class.new do
        include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
        def table_exists?(_name)
          false
        end

        def primary_keys(_name)
          []
        end
      end.new
    end

    context 'with valid constraints' do
      it 'accepts bigint type' do
        expect do
          adapter_instance.send(:validate_auto_random_constraints!, 'test_table', 'id', :bigint, {})
        end.not_to raise_error
      end

      it 'accepts integer type' do
        expect do
          adapter_instance.send(:validate_auto_random_constraints!, 'test_table', 'id', :integer, {})
        end.not_to raise_error
      end
    end

    context 'with invalid constraints' do
      it 'rejects unsupported column types' do
        expect do
          adapter_instance.send(:validate_auto_random_constraints!, 'test_table', 'id', :string, {})
        end.to raise_error(Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                           /AUTO_RANDOM requires :bigint or :integer column type/)
      end

      it 'rejects non-primary key columns' do
        expect do
          adapter_instance.send(:validate_auto_random_constraints!, 'test_table', 'id', :bigint, { primary_key: false })
        end.to raise_error(Ridgepole::Ext::Tidb::AutoRandomConstraintError, /AUTO_RANDOM column must be a primary key/)
      end

      it 'rejects tables with existing primary keys' do
        allow(adapter_instance).to receive(:table_exists?).and_return(true)
        allow(adapter_instance).to receive(:primary_keys).and_return(['existing_pk'])

        # First mock should fail
        adapter_instance_with_pk = Class.new do
          include Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          def table_exists?(_name)
            true
          end

          def primary_keys(_name)
            ['existing_pk']
          end
        end.new

        expect do
          adapter_instance_with_pk.send(:validate_auto_random_constraints!, 'test_table', 'id', :bigint, {})
        end.to raise_error(Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                           /Cannot add AUTO_RANDOM column to table with existing primary key/)
      end
    end
  end

  describe 'Schema dumper integration' do
    let(:mock_connection) do
      double('connection').tap do |conn|
        allow(conn).to receive(:tidb?).and_return(true)
        allow(conn).to receive(:auto_random_column?).and_return(false)
        allow(conn).to receive(:quote).and_return('"test_table"', '"id"')
      end
    end

    let(:mock_column) do
      double('column').tap do |col|
        allow(col).to receive(:name).and_return('id')
      end
    end

    let(:dumper_instance) do
      Class.new do
        include Ridgepole::Ext::Tidb::SchemaDumper
        def connection; end

        def prepare_column_options(_column)
          {}
        end
      end.new
    end

    before do
      allow(dumper_instance).to receive(:connection).and_return(mock_connection)
      # Mock the super method to return empty hash
      allow(dumper_instance).to receive(:prepare_column_options).and_call_original
      dumper_instance.instance_variable_set(:@table, 'test_table')
    end

    context 'when column has AUTO_RANDOM attribute' do
      it 'includes auto_random in column options' do
        # Create a base class that implements prepare_column_options
        base_class = Class.new do
          def prepare_column_options(_column)
            {}
          end

          def connection; end
        end

        # Create dumper class that inherits from base and includes our module
        dumper_class = Class.new(base_class) do
          include Ridgepole::Ext::Tidb::SchemaDumper
        end

        dumper = dumper_class.new
        allow(dumper).to receive(:connection).and_return(mock_connection)
        dumper.instance_variable_set(:@table, 'test_table')

        # Mock connection methods properly
        allow(mock_connection).to receive(:respond_to?).with(:tidb?).and_return(true)
        allow(mock_connection).to receive(:tidb?).and_return(true)
        allow(mock_connection).to receive(:respond_to?).with(:auto_random_column?).and_return(true)
        allow(mock_connection).to receive(:auto_random_column?).with('test_table', 'id').and_return(true)

        result = dumper.prepare_column_options(mock_column)
        expect(result[:auto_random]).to be true
      end
    end

    context 'when column does not have AUTO_RANDOM attribute' do
      it 'does not include auto_random in column options' do
        base_class = Class.new do
          def prepare_column_options(_column)
            {}
          end

          def connection; end
        end
        dumper_class = Class.new(base_class) do
          include Ridgepole::Ext::Tidb::SchemaDumper
        end
        dumper = dumper_class.new
        allow(dumper).to receive(:connection).and_return(mock_connection)
        dumper.instance_variable_set(:@table, 'test_table')

        allow(mock_connection).to receive(:respond_to?).with(:tidb?).and_return(true)
        allow(mock_connection).to receive(:tidb?).and_return(true)
        allow(mock_connection).to receive(:respond_to?).with(:auto_random_column?).and_return(true)
        allow(mock_connection).to receive(:auto_random_column?).with('test_table', 'id').and_return(false)

        result = dumper.prepare_column_options(mock_column)
        expect(result[:auto_random]).to be_nil
      end
    end

    context 'when not connected to TiDB' do
      it 'does not include auto_random in column options' do
        base_class = Class.new do
          def prepare_column_options(_column)
            {}
          end

          def connection; end
        end
        dumper_class = Class.new(base_class) do
          include Ridgepole::Ext::Tidb::SchemaDumper
        end
        dumper = dumper_class.new
        allow(dumper).to receive(:connection).and_return(mock_connection)
        dumper.instance_variable_set(:@table, 'test_table')

        allow(mock_connection).to receive(:respond_to?).with(:tidb?).and_return(true)
        allow(mock_connection).to receive(:tidb?).and_return(false)

        result = dumper.prepare_column_options(mock_column)
        expect(result[:auto_random]).to be_nil
      end
    end
  end

  # Integration tests that require actual TiDB connection
  describe 'TiDB integration', :tidb do
    let(:client) { Ridgepole::Client.new(TEST_CONFIG) }
    let(:connection) { ActiveRecord::Base.connection }

    before do
      skip_unless_tidb
      ActiveRecord::Base.establish_connection(TEST_CONFIG)
    end

    after do
      # Clean up test tables
      %w[test_users test_posts test_auto_random].each do |table|
        connection.execute("DROP TABLE IF EXISTS #{table}")
      rescue StandardError
        # Ignore cleanup errors
      end
    end

    it 'detects TiDB connection correctly' do
      expect(connection.tidb?).to be true
    end

    describe 'AUTO_RANDOM table creation' do
      let(:schema_with_auto_random) do
        <<~RUBY
          create_table "test_users", force: :cascade, id: false do |t|
            t.bigint "id", auto_random: true, primary_key: true
            t.string "name", null: false
            t.timestamps
          end
        RUBY
      end

      it 'creates table with AUTO_RANDOM successfully' do
        expect { client.apply(schema_with_auto_random) }.not_to raise_error
        expect(connection.table_exists?(:test_users)).to be true

        # Verify AUTO_RANDOM attribute
        expect(connection.auto_random_column?('test_users', 'id')).to be true
      end

      it 'generates non-sequential IDs' do
        client.apply(schema_with_auto_random)

        # Insert test records
        3.times { |i| connection.execute("INSERT INTO test_users (name) VALUES ('user#{i}')") }

        ids = connection.select_values('SELECT id FROM test_users ORDER BY id')
        expect(ids.length).to eq(3)

        # AUTO_RANDOM IDs should not be sequential (probability test)
        expect(ids[1] - ids[0]).not_to eq(1)
      end
    end

    describe 'Schema dumping with AUTO_RANDOM' do
      let(:schema_with_auto_random) do
        <<~RUBY
          create_table "test_posts", force: :cascade, id: false do |t|
            t.bigint "id", auto_random: true, primary_key: true
            t.string "title", null: false
            t.text "content"
            t.timestamps
          end
        RUBY
      end

      it 'includes auto_random in dumped schema' do
        client.apply(schema_with_auto_random)

        dumped_schema = client.dump
        expect(dumped_schema).to include('auto_random')
        expect(dumped_schema).to include('test_posts')
      end

      it 'maintains idempotency' do
        # First apply
        client.apply(schema_with_auto_random)

        # Second apply should produce no changes
        delta = client.diff(schema_with_auto_random)
        expect(delta).to be_empty
      end
    end

    describe 'Error handling' do
      it 'raises appropriate error for unsupported column type' do
        invalid_schema = <<~RUBY
          create_table "test_invalid", force: :cascade, id: false do |t|
            t.string "id", auto_random: true, primary_key: true
          end
        RUBY

        expect { client.apply(invalid_schema) }.to raise_error(/AUTO_RANDOM requires/)
      end

      it 'handles existing primary key constraints' do
        # Create table with existing primary key
        connection.execute(<<~SQL)
          CREATE TABLE test_existing_pk (
            existing_id INT PRIMARY KEY,
            name VARCHAR(255)
          )
        SQL

        expect do
          connection.add_column('test_existing_pk', 'new_id', :bigint, auto_random: true)
        end.to raise_error(/Cannot add AUTO_RANDOM column/)
      end
    end
  end
end
