# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    # TiDB 向け create_table 拡張（CREATE 時に完結）
    # - テーブルレベル auto_random を id 定義へ伝播
    # - AUTO_RANDOM_BASE をテーブル options に付与
    module TableOptions
      # CREATE 時に auto_random / auto_random_base を正しく反映
      def create_table(table_name, **options, &block)
        return super unless tidb?

        # 独自キーを取り出す（AR の未知キー検証を回避）
        auto_random_value = options.delete(:auto_random)
        auto_random_base_value = options.delete(:auto_random_base)

        # id: false でなければ、テーブルレベル auto_random を id に伝播
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

        # AUTO_RANDOM_BASE を options に付与
        if auto_random_base_value
          existing_options = options[:options] || ""
          if existing_options.present?
            options[:options] = "#{existing_options} AUTO_RANDOM_BASE=#{auto_random_base_value}"
          else
            options[:options] = "AUTO_RANDOM_BASE=#{auto_random_base_value}"
          end
        end

        # 主キー経路でビット数が落ちる環境向けのフォールバック用に一時保存
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


      private

      def build_create_table_options(options)
        return super unless tidb?

        # AUTO_RANDOM_BASE を options 文字列の先頭に寄せ、ノイズ差分を避ける
        sql_options = super
        if sql_options&.include?('AUTO_RANDOM_BASE')
          parts = sql_options.split(/\s+/)
          auto_random_parts = parts.select { |part| part.start_with?('AUTO_RANDOM_BASE=') }
          other_parts = parts.reject { |part| part.start_with?('AUTO_RANDOM_BASE=') }
          sql_options = (auto_random_parts + other_parts).join(' ')
        end

        sql_options
      end
    end
  end
end
