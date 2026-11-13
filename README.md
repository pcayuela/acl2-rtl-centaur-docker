# acl2-rtl-centaur-docker

A Docker image with a recent **ACL2** (plain, not ACL2(r)) and the hardware-verification
libraries already certified, so nothing has to be recertified before use:

- **RTL** books (`rtl/rel11/lib/top`), the Russinoff floating-point / arithmetic library.
- **Centaur** books: `centaur/sv/top` (SV, SystemVerilog-oriented hardware model),
  `centaur/sv/vl/top` (VL, the Verilog front end), `centaur/vl/loader/top` (the VL
  Verilog reader, used with `oslib/ls`) and `centaur/fgl/top` (FGL, the SAT/AIG-based
  proof framework).
- **iverilog**, **verilator** and **yosys** for co-simulation and synthesis checks.

Companion of [acl2-acl2r-docker](https://github.com/pcayuela/acl2-acl2r-docker), which
provides ACL2 8.7 and ACL2(r) 8.7 with arithmetic books.

## What is in the image

| | |
|---|---|
| ACL2 | `acl2/acl2` master, commit `4dbf21fe2bfc56b1bfa12a85f220726d658c1862` (a snapshot after 8.7) |
| Lisp | SBCL 2.6.5, nursery of 200 MB per process (acl2/acl2#2098) |
| Base | Ubuntu 24.04 |
| Certified | `rtl/rel11/lib/top`, `centaur/sv/top`, `centaur/sv/vl/top`, `centaur/fgl/top`, `centaur/vl/loader/top`, `oslib/ls` (and their dependencies) |

**Not included: an IPASIR SAT solver.** Centaur's `ipasir` books need a shared library
(`IPASIR_SHARED_LIBRARY`, by default `libipasirglucose4.so`) that is not built here, so the
Centaur SV tutorial books (`centaur/sv/tutorial/alu`, `sums`, `boothpipe`) do not certify
in this image. Reading Verilog with VL, SV and FGL books work.

Certificates are tied to this exact ACL2 build, so books certified in another ACL2
(even another snapshot of 8.7) are not reusable here, and vice versa.

## Use it

```bash
docker pull ghcr.io/pcayuela/acl2-rtl-centaur:latest
docker run --rm -it ghcr.io/pcayuela/acl2-rtl-centaur:latest acl2
```

In ACL2:

```lisp
(include-book "centaur/sv/top" :dir :system)
(include-book "centaur/fgl/top" :dir :system)
```

To work on your own files, mount the directory:

```bash
docker run --rm -it -v "$PWD":/work ghcr.io/pcayuela/acl2-rtl-centaur:latest acl2
```

Smoke test (loads the certified books and proves a small theorem):

```bash
docker run --rm ghcr.io/pcayuela/acl2-rtl-centaur:latest acl2-rtl-centaur-test
```

## Build it yourself

```bash
docker build --build-arg JOBS=12 -t acl2-rtl-centaur .
```

Build arguments: `ACL2_COMMIT`, `JOBS` (parallel `cert.pl` jobs), `BOOKS` (space-separated
`cert.pl` targets relative to `books/`), `SBCL_IMAGE`.

Measured on a 16-core machine (Docker on WSL2) with `JOBS=12`:

| What | Wall time |
|---|---|
| Full `docker build` from scratch (compile ACL2, certify RTL and Centaur) | about 25 min |
| Certifying only the Centaur books, on top of an image that already has RTL | about 16 min |

Peak memory while certifying the Centaur books: 3.7 GB.

## Licenses and credits

The files in this repository (Dockerfile, test script, documentation) are under the BSD
3-Clause license (see `LICENSE`). They do not contain code from ACL2 or SBCL: the image
downloads and builds [ACL2](https://github.com/acl2/acl2) (BSD-3-Clause, © the ACL2
authors, including the Centaur and RTL books) and uses
[SBCL](http://www.sbcl.org/) (public domain, with some BSD-licensed parts) at build time.
iverilog, verilator and yosys come from Ubuntu packages under their own licenses.
