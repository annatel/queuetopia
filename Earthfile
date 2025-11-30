VERSION 0.6

elixir-base:
    FROM --platform=$BUILDPLATFORM elixir:1.18.4-otp-27-alpine
    WORKDIR /app
    RUN apk add --no-progress --update openssh-client git build-base
    RUN mix local.rebar --force && mix local.hex --force

deps:
    ARG MIX_ENV
    FROM +elixir-base
    ENV MIX_ENV="$MIX_ENV"
    COPY mix.exs .
    COPY mix.lock .
    RUN mix deps.get --only "$MIX_ENV"
    RUN mix deps.compile

lint:
    FROM --build-arg MIX_ENV="dev" +deps
    COPY --dir lib README.md .
    COPY .formatter.exs .
    RUN mix deps.unlock --check-unused
    RUN mix format --check-formatted
    RUN mix compile --force-compile --warnings-as-errors

test:
    FROM earthly/dind:alpine
    WORKDIR /test

    RUN apk add --no-progress --update mysql-client postgresql-client

    COPY --dir config lib priv test .
    COPY README.md .

    ARG PG_IMG="postgres:11.11"
    ARG MYSQL_IMG="mysql:8.0"

    WITH DOCKER --pull "$PG_IMG" --pull "$MYSQL_IMG" --load elixir:latest=+deps --build-arg MIX_ENV="test"
        RUN set -e; \
            timeout=$(expr $(date +%s) + 60); \

        docker run --name pg --network=host -d -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=queuetopia "$PG_IMG"; \
        docker run --name mysql --network=host -d -e MYSQL_ROOT_PASSWORD=root "$MYSQL_IMG"; \

        # wait for postgres to start
        while ! pg_isready --host=127.0.0.1 --port=5432 --quiet; do \
            test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for postgres"; exit 1); \
            echo "waiting for postgres"; \
            sleep 1; \
        done; \

        # wait for mysql to start
        while ! mysqladmin ping --host=127.0.0.1 --port=3306 --protocol=TCP --silent; do \
            test "$(date +%s)" -le "$timeout" || (echo "timed out waiting for mysql"; exit 1); \
            echo "waiting for mysql"; \
            sleep 1; \
        done;  \

        # run test

        docker run \
            --rm \
            -e MIX_ENV=test \
            -e EX_LOG_LEVEL=warning \
            -e QUEUETOPIA__DATABASE_TEST_URL="ecto://root:root@localhost:3306/queuetopia" \
            -e QUEUETOPIA__DATABASE_TEST_REPO_ADAPTER=myxql \
            --network host \
            -v "$PWD/config:/app/config" \
            -v "$PWD/lib:/app/lib" \
            -v "$PWD/priv:/app/priv" \
            -v "$PWD/test:/app/test" \
            -v "$PWD/README.md:/app/README.md" \
            -w /app \
            --name queuetopia \
            elixir:latest mix test;
    END

check-tag:
    ARG TAG
    FROM +elixir-base
    COPY mix.exs .
    ARG APP_VERSION=$(mix app.version)
    IF [ ! -z $TAG ] && [ ! $TAG == $APP_VERSION ]
        RUN echo "TAG '$TAG' has to be equal to APP_VERSION '$APP_VERSION'" && false
    END
