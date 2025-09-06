# frozen_string_literal: true

require_relative 'tidb/version'

module Ridgepole
  module Ext
    module Tidb
      def self.setup!
        # SchemaDumperにもAUTO_RANDOM対応を追加
        extend_schema_dumper
      end      # 手動で接続アダプタを拡張するメソッド（外部から呼び出し可能）
      def self.ensure_connection_extended!
        return unless ActiveRecord::Base.connected?

        connection = ActiveRecord::Base.connection
        extend_connection_adapter(connection)
      end

      def self.extend_connection_adapter(connection)
        return unless connection

        adapter_class = connection.class

        # 既に拡張済みかチェック
        return if adapter_class.method_defined?(:tidb?)

        adapter_class.class_eval do
          # AUTO_RANDOMカラムの検出
          def auto_random_column?(table_name, column_name)
            return false unless tidb?

            # TiDB 7.5.0でのAUTO_RANDOM検出
            # SHOW CREATE TABLEでCREATE TABLE文を確認
            result = execute("SHOW CREATE TABLE #{quote_table_name(table_name)}")
            create_sql = result.first[1] if result.first

            if create_sql
              # TiDB 7.5.0では AUTO_RANDOM がコメント形式で表示される
              # 例: /*T![auto_rand] AUTO_RANDOM(5) */
              if create_sql.include?('AUTO_RANDOM') || create_sql.include?('auto_rand')
                return true
              end

              # テーブルオプションにAUTO_RANDOM_BASEが含まれているかチェック
              if create_sql.include?('AUTO_RANDOM_BASE')
                return true
              end
            end

            # INFORMATION_SCHEMA.COLUMNS の EXTRA を確認（フォールバック）
            extra = select_value(<<~SQL)
              SELECT EXTRA
              FROM INFORMATION_SCHEMA.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = #{quote(table_name)}
                AND COLUMN_NAME = #{quote(column_name)}
            SQL

            if extra&.downcase&.include?('auto_random')
              return true
            end

            false
          rescue => e
            puts "AUTO_RANDOM detection failed: #{e.message}"
            false
          end          # TiDBかどうかの判定
          def tidb?
            # VERSION()関数でTiDBを検出（キャッシュなし）
            version_info = select_value('SELECT VERSION()')
            result = version_info&.include?('TiDB') == true
            Rails.logger.debug "TiDB detection: version=#{version_info}, result=#{result}" if defined?(Rails)
            result
          rescue => e
            Rails.logger.debug "TiDB detection failed: #{e.message}" if defined?(Rails)
            false
          end

          # CREATE TABLE時のAUTO_RANDOM対応
          alias_method :create_table_without_auto_random, :create_table
          def create_table(table_name, **options, &block)
            if options.dig(:id, :auto_random) && tidb?
              # AUTO_RANDOMを含むテーブル作成
              sql = build_create_table_sql_with_auto_random(table_name, **options, &block)
              execute(sql)
            else
              create_table_without_auto_random(table_name, **options, &block)
            end
          end

          private

          def build_create_table_sql_with_auto_random(table_name, **options, &block)
            # 簡単な実装 - 実際にはより複雑になる
            sql = "CREATE TABLE #{quote_table_name(table_name)} ("

            if options[:id] && options[:id][:auto_random]
              sql += "id BIGINT AUTO_RANDOM PRIMARY KEY"
            end

            sql += ") DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
            sql
          end
        end

        puts "✅ Methods added to #{adapter_class}"
      end

      def self.extend_activerecord_adapters
        puts "📦 Extending ActiveRecord adapters..."
        # MySQL系アダプタにAUTO_RANDOMサポートを追加
        extend_adapter('ActiveRecord::ConnectionAdapters::Mysql2Adapter')
        extend_adapter('ActiveRecord::ConnectionAdapters::TrilogyAdapter')

        # SchemaDumperにもAUTO_RANDOM対応を追加
        extend_schema_dumper
        puts "📦 Adapter extension complete"
      end

      def self.extend_adapter(adapter_name)
        return unless defined?(ActiveRecord::ConnectionAdapters)

        begin
          adapter_class = Object.const_get(adapter_name)
          puts "🔧 Extending #{adapter_name}..."
        rescue NameError => e
          # アダプタが利用できない場合はスキップ
          puts "⚠️  Skipping #{adapter_name}: #{e.message}"
          return
        end

        # 一時的にputsを外して動作確認
        adapter_class.class_eval do
          # AUTO_RANDOMカラムの検出
          def auto_random_column?(table_name, column_name)
            return false unless tidb?

            extra = select_value(<<~SQL)
              SELECT EXTRA
              FROM INFORMATION_SCHEMA.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE()
                AND TABLE_NAME = #{quote(table_name)}
                AND COLUMN_NAME = #{quote(column_name)}
            SQL

            extra&.downcase&.include?('auto_random') == true
          rescue
            false
          end

          # TiDBかどうかの判定
          def tidb?
            # VERSION()関数でTiDBを検出（キャッシュなし）
            version_info = select_value('SELECT VERSION()')
            result = version_info&.include?('TiDB') == true
            Rails.logger.debug "TiDB detection: version=#{version_info}, result=#{result}" if defined?(Rails)
            result
          rescue => e
            Rails.logger.debug "TiDB detection failed: #{e.message}" if defined?(Rails)
            false
          end

          # CREATE TABLE時のAUTO_RANDOM対応
          alias_method :create_table_without_auto_random, :create_table
          def create_table(table_name, **options, &block)
            if options.dig(:id, :auto_random) && tidb?
              # AUTO_RANDOMを含むテーブル作成
              sql = build_create_table_sql_with_auto_random(table_name, **options, &block)
              execute(sql)
            else
              create_table_without_auto_random(table_name, **options, &block)
            end
          end

          private

          def build_create_table_sql_with_auto_random(table_name, **options, &block)
            # 簡単な実装 - 実際にはより複雑になる
            sql = "CREATE TABLE #{quote_table_name(table_name)} ("

            if options[:id] && options[:id][:auto_random]
              sql += "id BIGINT AUTO_RANDOM PRIMARY KEY"
            end

            sql += ") DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci"
            sql
          end
        end

        puts "✅ Methods added to #{adapter_name}"
      end

      def self.extend_schema_dumper
        return unless defined?(ActiveRecord::SchemaDumper)

        ActiveRecord::SchemaDumper.class_eval do
          alias_method :prepare_column_options_without_auto_random, :prepare_column_options
          def prepare_column_options(column)
            spec = prepare_column_options_without_auto_random(column)

            # TiDB接続でAUTO_RANDOMカラムの場合、auto_randomオプションを追加
            if @connection.respond_to?(:tidb?) && @connection.tidb? &&
               @connection.respond_to?(:auto_random_column?) &&
               @connection.auto_random_column?(@table, column.name)
              spec[:auto_random] = true
            end

            spec
          end
        end
      rescue NameError
        # SchemaDumperが利用できない場合はスキップ
      end
    end
  end
end
