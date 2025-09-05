FROM ruby:3.1

WORKDIR /app

# Install system dependencies for mysql2
RUN apt-get update -qq && \
    apt-get install -y build-essential default-mysql-client default-libmysqlclient-dev \
                       pkg-config libssl-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY Gemfile Gemfile.lock ridgepole-ext-tidb.gemspec ./
COPY lib/ridgepole/ext/tidb/version.rb lib/ridgepole/ext/tidb/

RUN bundle install

COPY . .

CMD ["bundle", "exec", "rspec"]
