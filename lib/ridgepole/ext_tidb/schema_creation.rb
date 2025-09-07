# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module SchemaCreation
      # この SchemaCreation インスタンスから接続の tidb? を参照できるように
      def tidb?
        if instance_variable_defined?(:@conn)
          conn = instance_variable_get(:@conn)
          return conn.respond_to?(:tidb?) && conn.tidb?
        end
        false
      end
      # デフォルト主キーの生成経路でも AUTO_RANDOM を反映
      def visit_PrimaryKeyDefinition(o)
        return super unless tidb?

        auto_random_value = o.options.delete(:auto_random)
        sql = super

        if auto_random_value
          sql.sub!(/\sAUTO_INCREMENT\b/i, "")
          bits = (auto_random_value == true ? nil : Integer(auto_random_value) rescue nil)
          sql << (bits ? " AUTO_RANDOM(#{bits})" : " AUTO_RANDOM")
        end

        sql
      end
      # APPLY: カラムに AUTO_RANDOM(n) を追加（PRIMARY KEY の有無に関わらず列側に付与）
      def visit_ColumnDefinition(o)
        return super unless tidb?

        # AUTO_RANDOM を取り出し（未知キーassertは Hash 拡張で回避済み）
        auto_random_value = o.options.delete(:auto_random)

        sql = super

        # テーブルレベル指定のフォールバック（id の自動生成経路で失われた場合に備える）
        if !auto_random_value && o.respond_to?(:primary_key?) && o.primary_key?
          if instance_variable_defined?(:@conn)
            conn = instance_variable_get(:@conn)
            if conn.instance_variable_defined?(:@tidb_pending_auto_random_pk_bits)
              auto_random_value = conn.instance_variable_get(:@tidb_pending_auto_random_pk_bits)
              # 一度使ったら破棄
              begin
                conn.remove_instance_variable(:@tidb_pending_auto_random_pk_bits)
              rescue StandardError
              end
            end
          end
        end

        if auto_random_value
          # 念のため AUTO_INCREMENT を除去
          sql.sub!(/\sAUTO_INCREMENT\b/i, "")

          bits = (auto_random_value == true ? nil : Integer(auto_random_value) rescue nil)
          sql << (bits ? " AUTO_RANDOM(#{bits})" : " AUTO_RANDOM")
        end

        sql
      end

      private

      def add_column_options!(sql, options)
        # 独自キーを先に取り出し
        bits = options.delete(:auto_random)

        # AUTO_RANDOM を付けるなら AUTO_INCREMENT を抑止
        options[:auto_increment] = false if bits

        super(sql, options)

        if bits
          unless sql.match?(/\bAUTO_RANDOM\b/i)
            sql.sub!(/\sAUTO_INCREMENT\b/i, "")
            sql << " AUTO_RANDOM(#{Integer(bits)})"
          end
        end

        sql
      end

      # 一部の AR バージョンはこちらを呼ぶ場合があるため両方用意
      def add_column_options(sql, options)
        add_column_options!(sql, options)
      end
    end
  end
end
