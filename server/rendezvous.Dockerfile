FROM rust:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libssl-dev libsodium-dev clang cmake \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY rustdesk-server-src/ .
RUN cargo build --release --bin hbbs --bin hbbr --bin rustdesk-utils

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 libsodium23 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/hbbs /usr/local/bin/hbbs
COPY --from=build /src/target/release/hbbr /usr/local/bin/hbbr
COPY --from=build /src/target/release/rustdesk-utils /usr/local/bin/rustdesk-utils
WORKDIR /data
VOLUME /data
