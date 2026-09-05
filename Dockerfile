# © 2026 aiaiaiai · aiaiaiai.org

# Keep in step with .ruby-version; CI fails if the two disagree.
ARG RUBY_VERSION=4.0.6

FROM ruby:${RUBY_VERSION}-slim AS build

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

WORKDIR /app

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install \
 && rm -rf "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

FROM ruby:${RUBY_VERSION}-slim

ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    RACK_ENV=production \
    PORT=8080

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y libpq5 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --shell /usr/sbin/nologin collector

WORKDIR /app
COPY --from=build ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --from=build --chown=collector:collector /app /app

USER collector
EXPOSE 8080

# No credentials are baked in: the collector reads DATABASE_URL and
# ERRORS_INGEST_TOKENS from its runtime environment.
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
