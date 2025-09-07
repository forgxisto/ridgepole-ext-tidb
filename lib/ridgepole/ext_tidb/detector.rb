# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module Detector
      # TiDB接続の自動検出
      def tidb?
        return @tidb_detected if defined?(@tidb_detected)

        @tidb_detected = begin
          version_info = select_value('SELECT VERSION()')
          result = version_info&.include?('TiDB') == true
          Rails.logger.debug "TiDB detection: version=#{version_info}, result=#{result}" if defined?(Rails)
          result
        rescue => e
          Rails.logger.debug "TiDB detection failed: #{e.message}" if defined?(Rails)
          false
        end
      end

      # AUTO_RANDOMカラムの検出
      def auto_random_column?(table_name, column_name)
        return false unless tidb?

        # SHOW CREATE TABLEでAUTO_RANDOMを検出
        result = execute("SHOW CREATE TABLE #{quote_table_name(table_name)}")
        create_sql = result.first[1] if result.first

        if create_sql
          # TiDBでのAUTO_RANDOM検出パターン
          patterns = [
            /AUTO_RANDOM\(\d+\)/i,
            /\/\*T!\[auto_rand\] AUTO_RANDOM\(\d+\) \*\//i
          ]

          patterns.any? { |pattern| create_sql.match?(pattern) }
        else
          # フォールバック: INFORMATION_SCHEMA.COLUMNSを確認
          extra = select_value(<<~SQL)
            SELECT EXTRA
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = #{quote(table_name)}
              AND COLUMN_NAME = #{quote(column_name)}
          SQL

          extra&.downcase&.include?('auto_random') == true
        end
      rescue => e
        Rails.logger.debug "AUTO_RANDOM detection failed: #{e.message}" if defined?(Rails)
        false
      end

      # AUTO_RANDOM_BASEテーブルオプションの検出
      def auto_random_base(table_name)
        return nil unless tidb?

        result = execute("SHOW CREATE TABLE #{quote_table_name(table_name)}")
        create_sql = result.first[1] if result.first

        if create_sql&.match(/AUTO_RANDOM_BASE=(\d+)/i)
          $1.to_i
        end
      rescue
        nil
      end
    end
  end
end
