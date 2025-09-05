# frozen_string_literal: true

require_relative 'tidb/version'

module Ridgepole
  module Ext
    module Tidb
      class Error < StandardError; end
      class TidbConnectionError < Error; end
      class AutoRandomConstraintError < Error; end
      class UnsupportedFeatureError < Error; end

      # Initialize the TiDB extension for Ridgepole
      def self.setup!
        # Ensure trilogy adapter is loaded
        load_trilogy_adapter

        # Load the extension modules when setup is called
        require_relative 'tidb/schema_dumper'
        require_relative 'tidb/connection_adapters'

        # Only extend if ActiveRecord is already loaded
        if defined?(::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
          ::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter.include(
            Ridgepole::Ext::Tidb::ConnectionAdapters::TrilogyAdapter
          )
        end

        return unless defined?(::ActiveRecord::SchemaDumper)

        ::ActiveRecord::SchemaDumper.prepend(
          Ridgepole::Ext::Tidb::SchemaDumper
        )
      end

      def self.load_trilogy_adapter
        require 'trilogy'
        require 'activerecord-trilogy-adapter'
        require 'active_record/connection_adapters/trilogy_adapter'
      rescue LoadError => e
        warn "Warning: Failed to load trilogy adapter: #{e.message}"
      end
    end
  end
end
