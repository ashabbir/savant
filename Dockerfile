FROM ruby:3.3-alpine

RUN apk add --no-cache build-base postgresql-dev

WORKDIR /app
COPY Gemfile Gemfile.lock* ./
RUN bundle config set without 'development test' \
 && bundle install --jobs=4 --retry=3 || true

# Default command overridden by docker-compose services
CMD ["sh", "-lc", "tail -f /dev/null"]

