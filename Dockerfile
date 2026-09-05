# © 2026 aiaiaiai · aiaiaiai.org
# Repository license is not selected yet; no SPDX identifier is asserted here.

FROM ruby:4.0.6-slim AS build

WORKDIR /app

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle config set deployment 'true' \
    && bundle config set without 'development test' \
    && bundle install

FROM ruby:4.0.6-slim

WORKDIR /app

RUN apt-get update \
    && apt-get install --yes --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /usr/sbin/nologin collector

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock .ruby-version config.ru ./
COPY config config
COPY db db
COPY lib lib
COPY protocol protocol

# The runtime carries no development or test gems, so bundler must be told not
# to look for them.
ENV RACK_ENV=production \
    BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT=development:test \
    PORT=9292

# No credentials are baked in: DATABASE_URL and ERRORS_INGEST_TOKENS are read
# from the runtime environment.
USER collector
EXPOSE 9292

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
