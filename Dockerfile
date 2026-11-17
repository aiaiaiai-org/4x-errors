# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

FROM ruby:4.0.6-slim AS build

WORKDIR /app

ENV BUNDLE_PATH=/usr/local/bundle

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
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock .ruby-version ./
COPY app.rb config.ru ./
COPY lib ./lib
COPY bin ./bin
COPY db ./db

ENV RACK_ENV=production \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=true
# The collector listens on 9292 unless PORT says otherwise. Infra's production
# workload contracts all use 1927 and set PORT to it; the self-host and
# direct-SSH paths keep 9292.
ENV PORT=9292
EXPOSE 9292

CMD ["sh", "-c", "exec bundle exec puma -b tcp://0.0.0.0:${PORT} config.ru"]
