FROM hexpm/elixir:1.20.5-erlang-29.1.2-alpine-3.24.3 AS build

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force 2.6.0 && \
    mix local.rebar rebar3 https://github.com/erlang/rebar3/releases/download/3.28.0/rebar3 --force --sha512 33bbd38c624f179a507ea0db611217aa3e9d99b6e65a96cdaebd933224e73af271c4d348171698f69c907dcf4f246757c8ea925a4153048bfdb6c7c5ca0835cf

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel
RUN mix do compile, assets.deploy, release

FROM alpine:3.22 AS app

RUN apk upgrade --no-cache && \
    apk add --no-cache bash ca-certificates openssl libssl3 libcrypto3 libgcc libstdc++ ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    HOME=/app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/calex ./
COPY --from=build --chown=nobody:nobody /app/priv /app/priv
RUN chmod +x /app/priv/random.sh /app/priv/cloak_key.sh

CMD ["bin/calex", "start"]
