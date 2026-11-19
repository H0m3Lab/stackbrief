# Patch layer: the official image, unchanged, plus current Alpine package updates.
ARG BASE
FROM ${BASE}
ARG BASE
ARG RUN_AS=root
USER root
RUN apk upgrade --no-cache
USER ${RUN_AS}
LABEL stackbrief.upstream="${BASE}" stackbrief.patch="apk upgrade"
