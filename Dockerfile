# Build stage
FROM --platform=$TARGETPLATFORM rust:1.72-alpine3.18 as cargo-build

RUN apk add --no-cache musl-dev pkgconfig openssl-dev cmake crypto++-dev gcc make g++ libpcap-dev abseil-cpp-dev make

# Compile plugin

WORKDIR /src/websocat
COPY websocat-transform-plugin-chacha chacha
RUN mkdir -p /src/websocat/chacha/build
WORKDIR /src/websocat/chacha/build
RUN cmake ../ -DCMAKE_BUILD_TYPE=Release && make

# Compile raw
WORKDIR /src/websocat
COPY raw-tcp-hole-punching raw
WORKDIR /src/websocat/raw
RUN make

# Compile websocat

WORKDIR /src/websocat
ENV RUSTFLAGS='-Ctarget-feature=-crt-static'

COPY Cargo.toml Cargo.toml
ARG CARGO_OPTS="--features=workaround1,seqpacket,prometheus_peer,prometheus/process,crypto_peer,native_plugins"

RUN mkdir src/ &&\
    echo "fn main() {println!(\"if you see this, the build broke\")}" > src/main.rs && \
    cargo build --release $CARGO_OPTS && \
    rm -f target/release/deps/websocat*

COPY src src
RUN cargo build --release $CARGO_OPTS && \
    strip target/release/websocat


# Final stage
FROM --platform=$TARGETPLATFORM alpine:3.18

RUN apk add --no-cache libgcc crypto++ libpcap abseil-cpp

WORKDIR /
COPY --from=cargo-build /src/websocat/target/release/websocat /usr/local/bin/
COPY --from=cargo-build /src/websocat/chacha/build/libfoo.so /
COPY --from=cargo-build /src/websocat/raw/main /raw
COPY --from=cargo-build /src/websocat/raw/raw.sh /raw.sh

RUN apk add --no-cache bcc-tools python3 py3-psutil py3-pyroute2

ENTRYPOINT ["/usr/local/bin/websocat", "-e", "--native-plugin-a", "enc@/libfoo.so", "--native-plugin-b", "dec@/libfoo.so"]
