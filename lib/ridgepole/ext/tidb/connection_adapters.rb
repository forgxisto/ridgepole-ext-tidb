# frozen_string_literal: true

module Ridgepole
  module Ext
    module Tidb
      module ConnectionAdapters
        module TrilogyAdapter
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            # Check if this is a TiDB connection (class method)
            def tidb?
              @tidb ||= detect_tidb_connection
            end

            private

            def detect_tidb_connection
              # Try TiDB-specific query first
              begin
                result = select_value('SELECT @@tidb_version')
                return true if result && !result.empty?
              rescue StandardError
                # Not a TiDB or query failed, continue
              end

              # Try version string detection
              begin
                result = select_value('SELECT VERSION()')
                return true if result&.include?('TiDB')
              rescue StandardError
                # Version query failed, continue
              end

              # Try variables detection
              begin
                result = select_value("SHOW VARIABLES LIKE 'version_comment'")
                return true if result&.include?('TiDB')
              rescue StandardError
                # Variables query failed
              end

              false
            rescue StandardError => e
              # Log error if logger available
              warn "TiDB detection failed: #{e.message}" if defined?(Rails) && Rails.logger
              false
            end
          end

          # Check if this is a TiDB connection (instance method)
          def tidb?
            @tidb ||= self.class.tidb?
          end

          # Override create_table to support auto_random option in column definitions
          def create_table(table_name, id: :default, primary_key: nil, force: nil, **options, &block)
            # Extract id column options to check for auto_random
            if id.is_a?(Hash) && id[:auto_random] && tidb?
              # Convert id options for TiDB AUTO_RANDOM
              id = convert_id_options_for_tidb(id)
            end

            super(table_name, id: id, primary_key: primary_key, force: force, **options, &block)
          end

          # Override add_column to support auto_random option
          def add_column(table_name, column_name, type, **options)
            auto_random = options.delete(:auto_random)

            if auto_random && tidb?
              # Validate AUTO_RANDOM constraints
              validate_auto_random_constraints!(table_name, column_name, type, options)

              # Call super first to create the basic column
              super(table_name, column_name, type, **options)

              # Then modify it to add AUTO_RANDOM
              modify_column_for_auto_random(table_name, column_name, type, options)
            else
              super(table_name, column_name, type, **options)
            end
          end

          # Check if a column has AUTO_RANDOM attribute
          def auto_random_column?(table_name, column_name)
            return false unless tidb?

            sql = <<~SQL
              SELECT EXTRA
              FROM INFORMATION_SCHEMA.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = #{quote(table_name.to_s)}
                AND COLUMN_NAME = #{quote(column_name.to_s)}
            SQL

            result = select_value(sql)
            return false unless result

            result.downcase.include?('auto_random')
          rescue StandardError => e
            warn "Failed to check AUTO_RANDOM attribute: #{e.message}" if defined?(Rails) && Rails.logger
            false
          end

          private

          def convert_id_options_for_tidb(id_options)
            # Ensure proper type for AUTO_RANDOM
            id_options = id_options.dup
            id_options[:type] ||= :bigint

            # AUTO_RANDOM requires bigint type
            unless %i[bigint integer].include?(id_options[:type])
              raise Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                    "AUTO_RANDOM requires :bigint or :integer type, got #{id_options[:type]}"
            end

            id_options
          end

          def modify_column_for_auto_random(table_name, column_name, type, _options)
            # Build the SQL type string
            sql_type = case type
                       when :bigint then 'BIGINT'
                       when :integer then 'INT'
                       else
                         raise Ridgepole::Ext::Tidb::UnsupportedFeatureError,
                               "Unsupported type for AUTO_RANDOM: #{type}"
                       end

            # Add AUTO_RANDOM and PRIMARY KEY
            alter_sql = "ALTER TABLE #{quote_table_name(table_name)} " \
                       "MODIFY COLUMN #{quote_column_name(column_name)} " \
                       "#{sql_type} AUTO_RANDOM PRIMARY KEY"

            begin
              execute(alter_sql)
            rescue StandardError => e
              # Re-raise with more context
              raise Ridgepole::Ext::Tidb::Error,
                    "Failed to add AUTO_RANDOM attribute to #{table_name}.#{column_name}: #{e.message}"
            end
          end

          def validate_auto_random_constraints!(table_name, _column_name, type, options)
            # AUTO_RANDOM must be on a bigint or int column
            unless %i[bigint integer].include?(type)
              raise Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                    "AUTO_RANDOM requires :bigint or :integer column type, got #{type}"
            end

            # AUTO_RANDOM must be primary key
            if options[:primary_key] == false
              raise Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                    'AUTO_RANDOM column must be a primary key'
            end

            # Check if table already has a primary key (only if table exists)
            return unless table_exists?(table_name)

            begin
              existing_pk = primary_keys(table_name)
              unless existing_pk.empty?
                raise Ridgepole::Ext::Tidb::AutoRandomConstraintError,
                      "Cannot add AUTO_RANDOM column to table with existing primary key: #{existing_pk.join(', ')}"
              end
            rescue NoMethodError
              # primary_keys method doesn't exist - skip check
            rescue StandardError => e
              # Only log database-related errors, re-raise validation errors
              raise if e.is_a?(Ridgepole::Ext::Tidb::AutoRandomConstraintError)

              warn "Warning: Could not verify primary key constraints: #{e.message}" if defined?(Rails) && Rails.logger
            end
          end
        end
      end
    end
  end
end
