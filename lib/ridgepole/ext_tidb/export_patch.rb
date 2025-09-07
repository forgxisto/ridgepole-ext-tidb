# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module ExportPatch
      # SchemaDumper 内から TiDB 判定できるように
      def tidb?
        if instance_variable_defined?(:@connection)
          conn = instance_variable_get(:@connection)
          return conn.respond_to?(:tidb?) && conn.tidb?
        end
        false
      end

      # EXPORT: SHOW CREATE TABLEを解析しDSLへ書き戻し
      def prepare_column_options(column)
        spec = super

        return spec unless tidb?

        # AUTO_RANDOMカラムの場合、auto_randomオプションを追加
        if auto_random_column?(@table, column.name)
          # SHOW CREATE TABLEからAUTO_RANDOMの値を抽出
          auto_random_bits = extract_auto_random_bits(@table, column.name)
          if auto_random_bits
            spec[:auto_random] = auto_random_bits
          else
            spec[:auto_random] = true
          end
          if ENV['EXT_TIDB_DEBUG']
            puts "[ext_tidb] prepare_column_options: table=#{@table} column=#{column.name} auto_random=#{spec[:auto_random]}"
          end
        end

        spec
      end

      # create_table のオプション（id/charset/collation/optionsなど）を構築する段階で
      # AUTO_RANDOM / AUTO_RANDOM_BASE を Hash に追加して DSL に出るようにする
      def prepare_table_options(*args)
        spec = super(*args)

        return spec unless tidb?

        table = args[0]
        extras = extract_table_auto_random_options(table)
        if extras[:auto_random]
          spec[:auto_random] = extras[:auto_random]
        end
        if extras[:auto_random_base]
          spec[:auto_random_base] = extras[:auto_random_base]
        end

        if ENV['EXT_TIDB_DEBUG']
          puts "[ext_tidb] prepare_table_options: table=#{table} extras=#{extras.inspect} spec_keys=#{spec.keys.inspect}"
        end

        spec
      end

      def table_options(table)
        options = super

        return options unless tidb?

        # AUTO_RANDOM_BASEオプションの抽出
        auto_random_base_value = auto_random_base(table)
        if auto_random_base_value
          # 既存のoptionsにAUTO_RANDOM_BASEを追加
          if options.present?
            options = "AUTO_RANDOM_BASE=#{auto_random_base_value} #{options}"
          else
            options = "AUTO_RANDOM_BASE=#{auto_random_base_value}"
          end
        end

        options
      end

      # テーブルレベルのauto_randomオプション抽出
      def extract_table_auto_random_options(table_name)
        result = execute("SHOW CREATE TABLE #{quote_table_name(table_name)}")
        create_sql = result.first[1] if result.first

        return {} unless create_sql

        options = {}

        # AUTO_RANDOM_BASEの抽出
        if match = create_sql.match(/AUTO_RANDOM_BASE=(\d+)/i)
          options[:auto_random_base] = match[1].to_i
        end

        # AUTO_RANDOM を含む列定義を検出（TiDB は列側に付くことが多い）
        # 代表的なパターンを広めにカバー
        patterns = [
          /`\w+`[^,]*?AUTO_RANDOM\((\d+)\)/i,                 # 通常の列に AUTO_RANDOM(n)
          /\/\*T!\[auto_rand\] AUTO_RANDOM\((\d+)\) \*\//i   # TiDB の注釈形式
        ]
        patterns.each do |pat|
          if (m = create_sql.match(pat))
            options[:auto_random] = m[1].to_i
            break
          end
        end

        options
      end

      private

      def extract_auto_random_bits(table_name, column_name)
        result = execute("SHOW CREATE TABLE #{quote_table_name(table_name)}")
        create_sql = result.first[1] if result.first

        return nil unless create_sql

        # AUTO_RANDOM(n)パターンの抽出
        patterns = [
          /`#{Regexp.escape(column_name)}`[^,]*?AUTO_RANDOM\((\d+)\)/i,
          /\/\*T!\[auto_rand\] AUTO_RANDOM\((\d+)\) \*\//i
        ]

        patterns.each do |pattern|
          if match = create_sql.match(pattern)
            return match[1].to_i
          end
        end

        nil
      end
    end
  end
end
