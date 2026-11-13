#!/usr/bin/env bash
# Smoke test: loads the certified books (no recertification), proves a theorem,
# reads a small Verilog file with VL, and checks the Verilog tools are present.
set -euo pipefail
ACL2_BIN="${ACL2:-acl2}"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/t.v" <<'VEOF'
module adder8 (input [7:0] a, input [7:0] b, output [8:0] s);
  assign s = a + b;
endmodule
VEOF
cat > "$tmp/t.lisp" <<LEOF
(include-book "rtl/rel11/lib/top" :dir :system)
(include-book "centaur/sv/top" :dir :system)
(include-book "centaur/sv/vl/top" :dir :system)
(include-book "centaur/fgl/top" :dir :system)
(include-book "centaur/vl/loader/top" :dir :system)
(include-book "oslib/ls" :dir :system)
(defthm test-app-assoc (equal (append (append a b) c) (append a (append b c))))
(make-event
 (b* (((mv loadres state)
       (vl::vl-load (vl::make-vl-loadconfig :start-files (list "$tmp/t.v")))))
   (mv nil \`(defconst *design* ',(vl::vl-loadresult->design loadres)) state)))
(cw "MODULES: ~x0~%" (vl::vl-modulelist->names (vl::vl-design->mods *design*)))
(cw "TEST-OK~%")
LEOF
out=$("$ACL2_BIN" < "$tmp/t.lisp" 2>&1) || true
echo "$out" | grep -q 'TEST-OK' || { echo "$out" | tail -30; echo "FAILED"; exit 1; }
echo "$out" | grep -q '\*\*\*\*\*\*\*\* FAILED' && { echo "$out" | tail -30; echo "FAILED"; exit 1; }
echo "$out" | grep -q 'MODULES: ("adder8")' || { echo "$out" | tail -30; echo "FAILED: VL did not read the module"; exit 1; }
echo "OK: RTL + Centaur (sv, vl, fgl) books load, ACL2 proves a theorem, VL reads Verilog (module adder8)"
for t in iverilog verilator yosys; do command -v $t >/dev/null && echo "found: $t" || { echo "missing: $t"; exit 1; }; done
