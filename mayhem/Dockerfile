# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for the watchman BSER harness. The org base has no folly, and watchman's
# headers (w_string, Logging, PubSub) include it, so this image builds folly from a pinned tag
# (contemporary with the code under test) into /opt/folly before build.sh compiles the harness.
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

USER root
RUN set -eux; \
    [ -z "${SOURCE_DATE_EPOCH:-}" ] || repro-sources-list.sh || true; \
    apt-get update; \
    apt-get install -yq --no-install-recommends cmake ninja-build git ca-certificates pkg-config \
      libboost-context-dev libboost-filesystem-dev libboost-program-options-dev \
      libboost-regex-dev libboost-system-dev libboost-thread-dev \
      libdouble-conversion-dev libgflags-dev libgoogle-glog-dev libevent-dev libssl-dev zlib1g-dev \
      libunwind-dev libgtest-dev libgmock-dev; \
    rm -rf /var/lib/apt/lists/*

# fmt 8.1.1 (b6f4ceaed0a0a24ccf575fab6c56dd50ccf6f1a9): watchman's bser.cpp formats a json_type enum
# directly, which fmt >= 9 (Debian's 10) rejects. Folly is built against it too, so there is one fmt.
ARG FMT_REV=b6f4ceaed0a0a24ccf575fab6c56dd50ccf6f1a9
RUN set -eux; \
    git init -q /tmp/fmt-src; cd /tmp/fmt-src; \
    git fetch -q --depth 1 https://github.com/fmtlib/fmt "$FMT_REV"; \
    git checkout -q FETCH_HEAD; \
    cmake -S . -B /tmp/fmt-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DFMT_TEST=OFF -DFMT_DOC=OFF -DCMAKE_INSTALL_PREFIX=/opt/fmt -DCMAKE_CXX_FLAGS="-g0 -include cstdint"; \
    cmake --build /tmp/fmt-build; cmake --install /tmp/fmt-build; \
    rm -rf /tmp/fmt-src /tmp/fmt-build

# folly v2022.09.26.00 (d318b1414b49743e816ebbec429894a4f9a0d9a5), static, no debug info (so the
# first DWARF CU in every binary is the harness's own, DWARF 3). The -include flags paper over
# headers that relied on transitive includes of the 2022-era libstdc++.
ARG FOLLY_REV=d318b1414b49743e816ebbec429894a4f9a0d9a5
RUN set -eux; \
    git init -q /tmp/folly-src; cd /tmp/folly-src; \
    git fetch -q --depth 1 https://github.com/facebook/folly "$FOLLY_REV"; \
    git checkout -q FETCH_HEAD; \
    cmake -S . -B /tmp/folly-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_CXX_STANDARD=17 \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF \
      -DCMAKE_INSTALL_PREFIX=/opt/folly -DCMAKE_PREFIX_PATH=/opt/fmt \
      -DCMAKE_CXX_FLAGS="-g0 -include cstdint -include stdexcept -include system_error -include cstdlib -include limits"; \
    cmake --build /tmp/folly-build -j"$(nproc)"; \
    cmake --install /tmp/folly-build; \
    rm -rf /tmp/folly-src /tmp/folly-build

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.fix="cd1af9355b9e100ef843ed133b952831c4a42bff" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
