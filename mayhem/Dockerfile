# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for the pybser (pywatchman's C BSER decoder) harness. The harness embeds
# CPython, so this image adds the Python development headers on top of the org base.
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
    apt-get install -yq --no-install-recommends python3-dev; \
    rm -rf /var/lib/apt/lists/*

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.fix="aca9f7e5d10d9e293587f8778a1eda4fdc062627" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
