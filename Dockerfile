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
ARG JOBS=4
LABEL org.opencontainers.image.source="https://github.com/pcayuela/acl2-rtl-centaur-docker" \
      org.opencontainers.image.description="ACL2 (git ${ACL2_COMMIT}) with pre-certified RTL (rtl/rel11) and Centaur (sv, vl, fgl) books + Glucose SAT solver + iverilog/verilator/yosys" \
      org.opencontainers.image.licenses="BSD-3-Clause"
COPY --from=build /opt/acl2 /opt/acl2
# /usr/local comes from the sbcl image and carries acl2/acl2r links: keep acl2, drop acl2r
RUN ln -sf /opt/acl2/saved_acl2 /usr/local/bin/acl2 && rm -f /usr/local/bin/acl2r

# SAT solver for FGL / SATLINK / AIGNET fraig: Glucose, built from the authors' source
# (checked against fixed SHA-256 hashes). Two things are built:
#  - the `glucose` executable (Glucose 4.1), which SATLINK calls as "glucose -model";
#  - libipasirglucose4.so (IPASIR interface), from Glucose 4.0 + Centaur's glue code.
#    Centaur's glue calls setTermCallback / setLearnCallback, which no public Glucose
#    release provides; both are optional in IPASIR, so they are compiled as no-ops
#    (a patched copy of the glue is compiled; the books are not modified).
ARG GLUCOSE41_SHA256=51aa1cf1bed2b14f1543b099e85a56dd1a92be37e6e3eb0c4a1fd883d5cc5029
ARG GLUCOSE40_SHA256=8dba2a417fd9f1170f1b7d14547688ee12c92a980e0b009e85aec1a5a4a0052f
RUN set -eux; mkdir /tmp/glucose && cd /tmp/glucose; \
    curl -fsSL -o g41.tgz https://www.labri.fr/perso/lsimon/downloads/softwares/glucose-syrup-4.1.tgz; \
    curl -fsSL -o g40.tgz https://www.labri.fr/perso/lsimon/downloads/softwares/glucose-syrup.tgz; \
    echo "${GLUCOSE41_SHA256}  g41.tgz" | sha256sum -c -; \
    echo "${GLUCOSE40_SHA256}  g40.tgz" | sha256sum -c -; \
    mkdir g41 g40; tar xzf g41.tgz -C g41; tar xzf g40.tgz -C g40; \
    (cd g41/glucose-syrup-4.1/simp && make r); \
    install -m 755 g41/glucose-syrup-4.1/simp/glucose_release /usr/local/bin/glucose-bin; \
    printf '%s\n' '#!/bin/sh' 'case " $* " in *" -model "*) exec /usr/local/bin/glucose-bin "$@";; esac' 'exec /usr/local/bin/glucose-bin -model "$@"' > /usr/local/bin/glucose; \
    chmod 755 /usr/local/bin/glucose; \
    GL=/opt/acl2/books/centaur/ipasir/solver-glue/glucose4; G=/tmp/glucose/g40/glucose-syrup; \
    cp $GL/ipasirglucoseglue.cc $GL/ipasir.h .; \
    sed -i 's|{ import(s)->setTermCallback(state, callback); }|{ (void)s; (void)state; (void)callback; }|; s|{ import(s)->setLearnCallback(state, max_length, learn); }|{ (void)s; (void)state; (void)max_length; (void)learn; }|' ipasirglucoseglue.cc; \
    ! grep -q "setTermCallback\|setLearnCallback" ipasirglucoseglue.cc; \
    g++ -std=c++11 -O3 -fPIC -DNDEBUG -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS -DVERSION=\"4\" \
        -I$G -I$G/core -I$G/mtl -I$G/utils -I. -shared -o /usr/local/lib/libipasirglucose4.so \
        ipasirglucoseglue.cc $G/core/Solver.cc $G/utils/Options.cc $G/utils/System.cc; \
    cd / && rm -rf /tmp/glucose
ENV IPASIR_SHARED_LIBRARY=/usr/local/lib/libipasirglucose4.so \
    USER=root
# IPASIR backend and the official SV tutorial examples (alu, boothpipe) need the library above.
RUN cd /opt/acl2/books && build/cert.pl --acl2 /opt/acl2/saved_acl2 -j ${JOBS:-4} \
        centaur/ipasir/ipasir-backend centaur/sv/tutorial/alu centaur/sv/tutorial/boothpipe
COPY test.sh /usr/local/bin/acl2-rtl-centaur-test
WORKDIR /work
CMD ["bash"]
