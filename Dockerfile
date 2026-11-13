# syntax=docker/dockerfile:1
#
# ACL2 (recent master) + RTL books (rtl/rel11) + Centaur hardware-verification
# books (SV, VL, FGL) + Verilog tools (iverilog, verilator, yosys).
#
# Plain ACL2 only (no ACL2(r)). SBCL 2.6.5 is taken from the published image of
# pcayuela/acl2-acl2r-docker (it is not recompiled here).
#
# Build:  docker build -t acl2-rtl-centaur .          (use --build-arg JOBS=N)
# Test:   docker run --rm acl2-rtl-centaur acl2-rtl-centaur-test   (see test.sh)
#
# SBCL nursery is 200 MB per process by default (acl2/acl2#2098), which keeps
# parallel certification light. Old behavior: -e ACL2_SBCL_NURSERY_SIZE=1600

ARG SBCL_IMAGE=ghcr.io/pcayuela/acl2-acl2r-docker:8.7
FROM ${SBCL_IMAGE} AS sbcl-src

FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl git m4 perl time \
        libzstd-dev zlib1g-dev python3 \
        iverilog verilator yosys \
    && rm -rf /var/lib/apt/lists/*
COPY --from=sbcl-src /usr/local /usr/local

FROM base AS build
# acl2/acl2 master commit of 9-Nov-2026
ARG ACL2_COMMIT=4dbf21fe2bfc56b1bfa12a85f220726d658c1862
ARG JOBS=4
ARG BOOKS="rtl/rel11/lib/top centaur/sv/top centaur/sv/vl/top centaur/fgl/top"
ENV ACL2_SNAPSHOT_INFO="git commit ${ACL2_COMMIT}"
RUN git clone https://github.com/acl2/acl2.git /opt/acl2 \
    && cd /opt/acl2 && git checkout "${ACL2_COMMIT}" && rm -rf .git
RUN cd /opt/acl2 && make LISP=sbcl || { cat make.log; exit 1; }
RUN cd /opt/acl2/books && make ACL2=/opt/acl2/saved_acl2 build/Makefile-features \
    && build/cert.pl --acl2 /opt/acl2/saved_acl2 -j ${JOBS} ${BOOKS}
# Second step (separate layer so the first one stays cached): the Verilog reader
# of VL (centaur/vl/loader/top) and oslib/ls, which vl-load needs to read files.
ARG BOOKS_VL="centaur/vl/loader/top oslib/ls"
RUN cd /opt/acl2/books && build/cert.pl --acl2 /opt/acl2/saved_acl2 -j ${JOBS} ${BOOKS_VL}

FROM base AS final
ARG ACL2_COMMIT=4dbf21fe2bfc56b1bfa12a85f220726d658c1862
LABEL org.opencontainers.image.source="https://github.com/pcayuela/acl2-rtl-centaur-docker" \
      org.opencontainers.image.description="ACL2 (git ${ACL2_COMMIT}) with pre-certified RTL (rtl/rel11) and Centaur (sv, vl, fgl) books + iverilog/verilator/yosys" \
      org.opencontainers.image.licenses="BSD-3-Clause"
COPY --from=build /opt/acl2 /opt/acl2
# /usr/local comes from the sbcl image and carries acl2/acl2r links: keep acl2, drop acl2r
RUN ln -sf /opt/acl2/saved_acl2 /usr/local/bin/acl2 && rm -f /usr/local/bin/acl2r
COPY test.sh /usr/local/bin/acl2-rtl-centaur-test
WORKDIR /work
CMD ["bash"]
