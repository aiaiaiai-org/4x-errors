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
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock ./
COPY app.rb config.ru ./

ENV RACK_ENV=production
EXPOSE 9292

CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:9292", "config.ru"]
