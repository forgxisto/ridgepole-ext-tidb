# frozen_string_literal: true

require_relative 'lib/ridgepole/ext_tidb/version'

Gem::Specification.new do |spec|
  spec.name = 'ridgepole-ext-tidb'
  spec.version = Ridgepole::ExtTidb::VERSION
  spec.authors = ['ikad']
  spec.email = ['info@forgxisto.com']

  spec.summary = 'TiDB AUTO_RANDOM support extension for Ridgepole'
  spec.description = "Extends Ridgepole to support TiDB's AUTO_RANDOM column attribute for seamless schema management"
  spec.homepage = 'https://github.com/forgxisto/ridgepole-ext-tidb'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/forgxisto/ridgepole-ext-tidb'
  spec.metadata['changelog_uri'] = 'https://github.com/forgxisto/ridgepole-ext-tidb/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile]) ||
        f.end_with?('.gem')
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'ridgepole', ">= 3.0"

  # Development dependencies
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'trilogy'
  spec.add_development_dependency 'activerecord', '>= 8.0'
  spec.add_development_dependency 'debug'

  # Ruby 3.4+ compatibility
  spec.add_development_dependency 'benchmark'
  spec.add_development_dependency 'bigdecimal'
  spec.add_development_dependency 'logger'
  spec.add_development_dependency 'mutex_m'
end
