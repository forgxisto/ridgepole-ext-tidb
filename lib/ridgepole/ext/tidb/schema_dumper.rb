# frozen_string_literal: true

module Ridgepole
  module Ext
    module Tidb
      module SchemaDumper
        # Override prepare_column_options to include auto_random
        def prepare_column_options(column)
          spec = super(column)

          # Add auto_random if this column has the attribute
          spec[:auto_random] = true if tidb_connection? && auto_random_column?(current_table_name, column.name)

          spec
        end

        private

        def tidb_connection?
          connection.respond_to?(:tidb?) && connection.tidb?
        rescue StandardError
          false
        end

        def current_table_name
          # Get the current table name being processed
          # In ActiveRecord schema dumper context, @table holds the current table name
          return @table.to_s if instance_variable_defined?(:@table) && @table

          # Fallback: try to extract from the column if it has table information
          nil
        end

        def auto_random_column?(table_name, column_name)
          return false unless table_name && column_name
          return false unless tidb_connection?

          # Use the connection's auto_random_column? method if available
          return connection.auto_random_column?(table_name, column_name) if connection.respond_to?(:auto_random_column?)

          # Fallback: direct query
          check_auto_random_attribute(table_name, column_name)
        end

        def check_auto_random_attribute(table_name, column_name)
          sql = <<~SQL
            SELECT EXTRA
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = #{connection.quote(table_name.to_s)}
              AND COLUMN_NAME = #{connection.quote(column_name.to_s)}
          SQL

          result = connection.select_value(sql)
          return false unless result

          result.downcase.include?('auto_random')
        rescue StandardError => e
          # Log warning if possible
          if defined?(Rails) && Rails.logger
            warn "Failed to check AUTO_RANDOM attribute for #{table_name}.#{column_name}: #{e.message}"
          end
          false
        end

        # Override table method to track current table name
        def table(table_name, stream)
          @table = table_name
          super(table_name, stream)
        ensure
          @table = nil
        end
      end
    end
  end
end
