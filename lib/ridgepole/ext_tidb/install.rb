# frozen_string_literal: true

module Ridgepole
  module ExtTidb
    module Install
      # Ridgepole起動時にTiDB検出→各パッチをprepend
      def self.apply_patches!
        # Hash#assert_valid_keysを拡張してauto_randomキーを許可
        extend_hash_assert_valid_keys

        # ActiveRecordが読み込まれている場合は即座に適用
        if defined?(ActiveRecord::Base)
          apply_activerecord_patches
        else
          # ActiveRecordが後でロードされる場合に備えてフックを設定
          ActiveSupport.on_load(:active_record) do
            apply_activerecord_patches
          end
        end
      end

      def self.apply_activerecord_patches
        extend_connection_adapters
        # SchemaDumper への直接パッチは不要（dump は DumpPatch が担当）
        # TableDefinition 拡張も不要（Hash#assert_valid_keys 拡張で回避）
        install_connection_hook
        extend_ridgepole_client
      end

      private

      def self.extend_hash_assert_valid_keys
        Hash.class_eval do
          alias_method :assert_valid_keys_without_auto_random, :assert_valid_keys
          def assert_valid_keys(*valid_keys)
            # auto_random, auto_random_baseキーを有効なキーとして追加
            auto_random_keys = [:auto_random, :auto_random_base]
            auto_random_keys.each do |key|
              if keys.include?(key) && !valid_keys.include?(key)
                valid_keys = valid_keys + [key]
              end
            end
            assert_valid_keys_without_auto_random(*valid_keys)
          end
        end
      rescue NameError => e
        Rails.logger.debug "Could not extend Hash#assert_valid_keys: #{e.message}" if defined?(Rails)
      end

      def self.extend_connection_adapters
        return unless defined?(ActiveRecord::ConnectionAdapters)

        # まずは抽象 MySQL アダプタにパッチ（mysql2/trilogy 双方を網羅）
        begin
          abstract_mysql = ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter

          abstract_mysql.prepend(Detector) unless abstract_mysql < Detector
          abstract_mysql.prepend(TableOptions) unless abstract_mysql < TableOptions

          if abstract_mysql.const_defined?(:SchemaCreation)
            sc = abstract_mysql.const_get(:SchemaCreation)
            sc.prepend(SchemaCreation) unless sc < SchemaCreation
          end
        rescue NameError
          # 未ロードの環境もあるので無視（接続確立後にロードされる）
        end

        # 既に具体アダプタがロード済みなら、そちらにも適用（冪等）
        %w[
          ActiveRecord::ConnectionAdapters::Mysql2Adapter
          ActiveRecord::ConnectionAdapters::TrilogyAdapter
        ].each do |adapter_name|
          begin
            adapter_class = Object.const_get(adapter_name)
            adapter_class.prepend(Detector) unless adapter_class < Detector
            adapter_class.prepend(TableOptions) unless adapter_class < TableOptions
            if adapter_class.const_defined?(:SchemaCreation)
              sc = adapter_class.const_get(:SchemaCreation)
              sc.prepend(SchemaCreation) unless sc < SchemaCreation
            end
          rescue NameError
            # 未ロードならスキップ
          end
        end

        # 名前空間の揺れに備え、ConnectionAdapters 配下の SchemaCreation すべてに適用
        begin
          ObjectSpace.each_object(Class) do |klass|
            name = klass.name rescue nil
            next unless name && name.start_with?("ActiveRecord::ConnectionAdapters")
            next unless name.end_with?("::SchemaCreation")
            klass.prepend(SchemaCreation) unless klass < SchemaCreation
          end
        rescue StandardError
          # noop
        end

        # AbstractMysqlAdapter のサブクラスにも Detector/TableOptions を適用（ロード順対策）
        begin
          if defined?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
            ObjectSpace.each_object(Class) do |klass|
              next unless klass < ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter
              klass.prepend(Detector) unless klass < Detector
              klass.prepend(TableOptions) unless klass < TableOptions
            end
          end
        rescue StandardError
          # noop
        end
      end

      # 接続確立後（アダプタ読み込み後）にも確実にパッチを適用するためのフック
      def self.install_connection_hook
        return unless defined?(ActiveRecord::Base)
        return if @establish_hook_installed

        mod = Module.new do
          def establish_connection(*args)
            result = super
            # アダプタが読み込まれた後に再度パッチ適用（冪等）
            Ridgepole::ExtTidb::Install.extend_connection_adapters
            result
          end
        end

        # class << だとローカル変数がスコープ外になるため、singleton_class で prepend
        ActiveRecord::Base.singleton_class.prepend(mod)

        @establish_hook_installed = true
      rescue StandardError => e
        Rails.logger.debug "Could not install establish_connection hook: #{e.message}" if defined?(Rails)
      end

      # extend_schema_dumper: dump は DumpPatch に委譲するため不要
      # extend_table_definition: Hash#assert_valid_keys で未知キーを許すため不要

      def self.extend_ridgepole_client
        return unless defined?(Ridgepole::Client)
        return if Ridgepole::Client < Ridgepole::ExtTidb::DumpPatch
        Ridgepole::Client.prepend(Ridgepole::ExtTidb::DumpPatch)
      rescue StandardError => e
        Rails.logger.debug "Could not extend Ridgepole::Client: #{e.message}" if defined?(Rails)
      end
    end
  end
end
