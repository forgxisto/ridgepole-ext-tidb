# frozen_string_literal: true

require_relative 'ext_tidb/version'
require_relative 'ext_tidb/detector'
require_relative 'ext_tidb/schema_creation'
require_relative 'ext_tidb/table_options'
require_relative 'ext_tidb/export_patch'
require_relative 'ext_tidb/dump_patch'
require_relative 'ext_tidb/install'

module Ridgepole
  module ExtTidb
    # エントリポイント - requireで自動的にインストール
    def self.setup!
      Install.apply_patches!
    end
  end
end

# 自動インストール
Ridgepole::ExtTidb.setup!
