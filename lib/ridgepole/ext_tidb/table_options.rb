# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module TableOptions
      # APPLY: テーブルoptionsにAUTO_RANDOM_BASE、主キーにAUTO_RANDOM伝播（CREATE時に反映）
      def create_table(table_name, **options, &block)
        return super unless tidb?

        # Rails/ActiveRecord の未知キー assertion を避けるため、独自キーを事前に取り出す
        auto_random_value = options.delete(:auto_random) # テーブルレベル指定（id に伝播させる）
        auto_random_base_value = options.delete(:auto_random_base)

        # テーブルレベル auto_random をデフォルト主キーに伝播（id: false は除外）
        if auto_random_value && options[:id] != false
          id_opt = options[:id]
          id_opts = case id_opt
                    when Hash
                      id_opt.dup
                    when Symbol
                      { type: id_opt }
                    when true, nil
                      {}
                    else
                      { type: id_opt }
                    end
          id_opts[:auto_random] = auto_random_value
          id_opts[:auto_increment] = false
          options[:id] = id_opts
        end

        # テーブルオプションにAUTO_RANDOM_BASEを追加
        if auto_random_base_value
          existing_options = options[:options] || ""
          if existing_options.present?
            options[:options] = "#{existing_options} AUTO_RANDOM_BASE=#{auto_random_base_value}"
          else
            options[:options] = "AUTO_RANDOM_BASE=#{auto_random_base_value}"
          end
        end

        # デフォルト主キーの AUTO_RANDOM(n) を SchemaCreation から参照できるよう一時保存
        if auto_random_value && options[:id] != false
          begin
            @tidb_pending_auto_random_pk_bits = auto_random_value
          rescue StandardError
          end
        end

        begin
          super
        ensure
          remove_instance_variable(:@tidb_pending_auto_random_pk_bits) if instance_variable_defined?(:@tidb_pending_auto_random_pk_bits)
        end
      end

      # ALTER TABLEでのAUTO_RANDOM対応
      def change_column(table_name, column_name, type, **options)
        return super unless tidb?

        # auto_randomキーを事前に削除
        auto_random_value = options.delete(:auto_random)

        if auto_random_value
          # AUTO_RANDOMの変更は特別な処理が必要
          execute("ALTER TABLE #{quote_table_name(table_name)} " \
                 "MODIFY COLUMN #{quote_column_name(column_name)} " \
                 "#{type_to_sql(type, **options)} AUTO_RANDOM(#{auto_random_value})")
        else
          super
        end
      end

      private

      def build_create_table_options(options)
        return super unless tidb?

        # AUTO_RANDOM_BASEが含まれている場合の正規化
        sql_options = super

        # オプションの順序を正規化（差分回避）
        if sql_options&.include?('AUTO_RANDOM_BASE')
          parts = sql_options.split(/\s+/)
          auto_random_parts = parts.select { |part| part.start_with?('AUTO_RANDOM_BASE=') }
          other_parts = parts.reject { |part| part.start_with?('AUTO_RANDOM_BASE=') }

          # AUTO_RANDOM_BASEを先頭に配置
          sql_options = (auto_random_parts + other_parts).join(' ')
        end

        sql_options
      end
    end
  end
end
