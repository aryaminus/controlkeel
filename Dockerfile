# ControlKeel Dockerfile — assemble-only release for Docker / Glama / mcp-proxy
#
# Build:  docker build -t controlkeel .
# Run:    docker run -it --rm controlkeel
# MCP:    docker run -i --rm controlkeel  (stdio mode via CK_MCP_MODE=1)
#
# This uses kerl to build OTP 27 and installs Elixir 1.19.5 — matching CI
# (release-smoke.yml uses erlef/setup-beam with otp-version: "27.3.4.3"
# and elixir-version: "1.19.5").  hexpm images no longer carry OTP 27 stable.
#
FROM debian:trixie-slim AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git wget unzip \
      libssl-dev libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Erlang/OTP 27.3.4.3 via kerl (matches CI).
ENV OTP_VERSION=27.3.4.3
RUN curl -fsSL https://raw.githubusercontent.com/kerl/kerl/master/kerl -o /usr/local/bin/kerl \
    && chmod +x /usr/local/bin/kerl \
    && kerl update releases \
    && kerl build ${OTP_VERSION} ${OTP_VERSION} \
    && kerl install ${OTP_VERSION} /usr/local/erlang-${OTP_VERSION} \
    && ln -sf /usr/local/erlang-${OTP_VERSION}/bin/erl /usr/local/bin/erl \
    && ln -sf /usr/local/erlang-${OTP_VERSION}/bin/erlc /usr/local/bin/erlc \
    && ln -sf /usr/local/erlang-${OTP_VERSION}/bin/mix /usr/local/bin/mix \
    && erl -version

# Install Elixir 1.19.5 (matches CI) - OTP 27 build.
ENV ELIXIR_VERSION=1.19.5
RUN curl -fsSL -o /tmp/elixir.zip https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-27.zip \
    && mkdir -p /usr/local/elixir-${ELIXIR_VERSION} \
    && unzip -q /tmp/elixir.zip -d /usr/local/elixir-${ELIXIR_VERSION} \
    && ln -sf /usr/local/elixir-${ELIXIR_VERSION}/bin/elixir /usr/local/bin/elixir \
    && ln -sf /usr/local/elixir-${ELIXIR_VERSION}/bin/mix /usr/local/bin/mix \
    && ln -sf /usr/local/elixir-${ELIXIR_VERSION}/bin/iex /usr/local/bin/iex \
    && ln -sf /usr/local/elixir-${ELIXIR_VERSION}/bin/elixirc /usr/local/bin/elixirc \
    && rm -f /tmp/elixir.zip

ENV LANG=C.UTF-8

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY lib lib
COPY priv priv
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

# ---- Runtime Stage ----
FROM debian:trixie-slim AS app

RUN apt-get update && apt-get install -y --no-install-recommends \
      libstdc++6 libssl3t64 ca-certificates libncurses6 git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV=prod

COPY --from=build --chown=nobody:root /app/_build/prod/rel/controlkeel ./

USER nobody

# For stdio MCP mode (Glama, mcp-proxy, etc.)
ENV CK_MCP_MODE=1
ENV LANG=C.UTF-8

CMD ["/app/bin/controlkeel", "start"]
