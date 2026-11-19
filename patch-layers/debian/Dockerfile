# Patch layer: the official image, unchanged, plus current Debian/Ubuntu security updates.
# Build args: BASE = official image ref; RUN_AS = the user the official image runs as (root if it sets none).
ARG BASE
FROM ${BASE}
ARG BASE
ARG RUN_AS=root
USER root
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold upgrade \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
USER ${RUN_AS}
LABEL stackbrief.upstream="${BASE}" stackbrief.patch="apt upgrade"
