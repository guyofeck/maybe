# Dev runtime image for Base44 preview. Contains only system packages;
# app source is bind-mounted and gems are installed into a volume at startup.
ARG RUBY_VERSION=3.4.4
FROM ruby:${RUBY_VERSION}-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential curl git libpq-dev libvips libyaml-dev pkg-config postgresql-client && \
    rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/bundle
WORKDIR /workspace
