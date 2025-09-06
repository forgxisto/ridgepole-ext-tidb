# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ridgepole-ext-tidb is a Ruby gem that extends Ridgepole to support TiDB's AUTO_RANDOM column attribute for distributed ID generation. It integrates with the trilogy adapter and extends ActiveRecord's schema management.

## Development Commands

### Setup
```bash
bundle install
```

### Testing
```bash
# Basic tests without TiDB
SKIP_TIDB_TESTS=1 bundle exec rspec

# Full integration tests (requires Docker)
docker compose up -d
bundle exec rspec

# Docker-based testing
docker compose run --rm test

# Run single test file
bundle exec rspec spec/ridgepole/ext/tidb_spec.rb
```

### Code Quality
```bash
bundle exec rubocop
bundle exec rake  # runs spec + rubocop
```

### TiDB Environment
```bash
docker compose up -d tidb
docker compose exec tidb mysql -u root -h 127.0.0.1 -P 4000 -e "CREATE DATABASE IF NOT EXISTS ridgepole_test"
```

## Architecture

### Extension Pattern
The gem uses module prepending/including to extend existing ActiveRecord functionality:
- `setup!` method loads trilogy adapter and injects modules
- `SchemaDumper` module prepended to ActiveRecord::SchemaDumper
- `TrilogyAdapter` module included in AbstractMysqlAdapter

### Core Components
- **Main Extension** (`lib/ridgepole/ext/tidb.rb`): Entry point and setup
- **Schema Dumper** (`lib/ridgepole/ext/tidb/schema_dumper.rb`): Detects and dumps AUTO_RANDOM attributes by querying INFORMATION_SCHEMA.COLUMNS
- **Connection Adapters** (`lib/ridgepole/ext/tidb/connection_adapters.rb`): Adds TiDB detection and AUTO_RANDOM column support

### TiDB Integration
- Detects TiDB by querying `@@tidb_version` or version strings
- AUTO_RANDOM columns identified via INFORMATION_SCHEMA queries
- Modifies column creation to add AUTO_RANDOM attribute (requires BIGINT PRIMARY KEY)

### Test Configuration
Uses trilogy adapter connecting to TiDB on port 4000. Supports mock TiDB behavior for development and automatic test cleanup.
