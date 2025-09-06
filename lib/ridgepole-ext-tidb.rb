# frozen_string_literal: true

require_relative 'ridgepole/ext/tidb'

# Ridgepoleが使用される前に拡張を適用
Ridgepole::Ext::Tidb.setup!

# ActiveRecordアダプタが利用可能になったときに自動拡張を実行
if defined?(ActiveRecord::Base)
  Ridgepole::Ext::Tidb.extend_activerecord_adapters
else
  # ActiveRecordが後でロードされる場合に備えてフックを設定
  ActiveSupport.on_load(:active_record) do
    Ridgepole::Ext::Tidb.extend_activerecord_adapters
  end
end
