FROM ruby:3.1

WORKDIR /app

# Install system dependencies for mysql2 and trilogy
RUN apt-get update -qq && \
    apt-get install -y build-essential \
    default-mysql-client \
    default-libmysqlclient-dev \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    netcat-traditional && \
    rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY Gemfile Gemfile.lock ridgepole-ext-tidb.gemspec ./
COPY lib/ridgepole/ext/tidb/version.rb lib/ridgepole/ext/tidb/

# Add logger require to fix NameError
RUN echo "require 'logger'" > /tmp/fix_logger.rb

RUN bundle install

COPY . .

# Wait for TiDB to be ready
RUN echo '#!/bin/bash\n\
    echo "Waiting for TiDB to be ready..."\n\
    while ! nc -z $TIDB_HOST $TIDB_PORT; do\n\
    echo "TiDB is not ready - sleeping"\n\
    sleep 1\n\
    done\n\
    echo "TiDB is ready!"\n\
    mysql -h $TIDB_HOST -P $TIDB_PORT -u $TIDB_USER -e "CREATE DATABASE IF NOT EXISTS $TIDB_DATABASE"\n\
    exec "$@"' > /wait-for-tidb.sh && chmod +x /wait-for-tidb.sh

ENTRYPOINT ["/wait-for-tidb.sh"]
CMD ["bundle", "exec", "rspec"]
