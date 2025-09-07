# frozen_string_literal: true
require "logger"
require "debug"
require "bundler/setup"
require "rspec"
require "active_record"
require "trilogy"
require "ridgepole"
require "ridgepole/ext_tidb"

Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    TiDBDocker.ensure_up!
    DBHelpers.prepare_database!
  end

  config.after(:suite) do
    TiDBDocker.down!
  end

  config.after do
    DBHelpers.drop_all_tables!
  end
end
