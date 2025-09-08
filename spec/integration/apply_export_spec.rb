# frozen_string_literal: true
require "tempfile"

RSpec.describe "TiDB integration: apply/export roundtrip", :integration do
  let(:client) { DBHelpers.ridgepole_client }

  it "applies AUTO_RANDOM and AUTO_RANDOM_BASE and exports losslessly" do
    schemafile = File.expand_path("../../fixtures/Schemafile.base", __FILE__)
    dsl = File.read(schemafile)

    # 1) 差分生成 → 実適用
    delta = client.diff(dsl)
    expect(delta.script.strip).not_to eq("")  # 何かしらの差分がある
    delta.migrate

    # 2) TiDB 側 DDL を確認
    ddl = DBHelpers.show_create("users")
    expect(ddl).to match(/`id`\s+bigint.*AUTO_RANDOM\(\s*5\s*\)/i)
    expect(ddl).to match(/\bAUTO_RANDOM_BASE=100000\b/i)

    # 3) export（dump）で DSL に書き戻ること
    exported = if client.respond_to?(:dump)
                 client.dump
               else
                 # 念のためのフォールバック（まず使わない想定）
                 Ridgepole::Client.dump(DBHelpers.base_config(database: DBHelpers::DB))
               end
    expect(exported).to include('create_table "users"')
    expect(exported).to include("auto_random: 5")
    expect(exported).to include("auto_random_base: 100000")

    # 4) 再diffが空（往復一致）
    delta2 = client.diff(exported)
    expect(delta2.script.strip).to eq("")
    delta2.migrate # no-opで終了すること（例外なし）
  end

  it "supports column-level auto_random when defining pk manually" do
    dsl = <<~DSL
      require "ridgepole/ext_tidb"
      create_table "events", id: false, options: "DEFAULT CHARSET=utf8mb4" do |t|
        t.bigint :id, primary_key: true, null: false, auto_random: 6
        t.string :title, null: false
      end
    DSL

    delta = client.diff(dsl)
    expect(delta.script.strip).not_to eq("")
    delta.migrate

    ddl = DBHelpers.show_create("events")
    expect(ddl).to match(/`id`\s+bigint.*AUTO_RANDOM\(\s*6\s*\)/i)
  end

  it "remains idempotent across repeated export/apply cycles" do
    schemafile = File.expand_path("../../fixtures/Schemafile.base", __FILE__)
    dsl = File.read(schemafile)

    # 1) 初回適用
    delta = client.diff(dsl)
    expect(delta.script.strip).not_to eq("")
    delta.migrate

    # 2) 1回目のexport → 差分なし → no-op適用
    exported1 = client.respond_to?(:dump) ? client.dump : Ridgepole::Client.dump(DBHelpers.base_config(database: DBHelpers::DB))
    delta1 = client.diff(exported1)
    expect(delta1.script.strip).to eq("")
    delta1.migrate

    # 3) 2回目のexport（重複注入がないこと、値が保持されること）
    exported2 = client.respond_to?(:dump) ? client.dump : Ridgepole::Client.dump(DBHelpers.base_config(database: DBHelpers::DB))
    expect(exported2).to include('create_table "users"')
    expect(exported2).to include('auto_random: 5')
    expect(exported2).to include('auto_random_base: 100000')
    expect(exported2.scan(/auto_random:/).size).to eq(1)
    expect(exported2.scan(/auto_random_base:/).size).to eq(1)

    # 4) 再diffが空（繰り返し往復でも安定）
    delta2 = client.diff(exported2)
    expect(delta2.script.strip).to eq("")
    delta2.migrate

    # 5) SHOW CREATE でも AUTO_RANDOM は維持されている
    ddl = DBHelpers.show_create("users")
    expect(ddl).to match(/`id`\s+bigint.*AUTO_RANDOM\(\s*5\s*\)/i)
    expect(ddl).to match(/\bAUTO_RANDOM_BASE=100000\b/i)
  end
end
