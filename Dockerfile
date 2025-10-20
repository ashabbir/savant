FROM ruby:3.3-alpine

# Add git so the indexer can use `git ls-files` in Docker
RUN apk add --no-cache build-base postgresql-dev git

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' \
 && bundle install --jobs=4 --retry=3 || true

# Default command overridden by docker-compose services
CMD ["sh", "-lc", "tail -f /dev/null"]
