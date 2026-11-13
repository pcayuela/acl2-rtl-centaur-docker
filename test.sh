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
# FGL proof with the SAT solver: an 8-bit adder read from Verilog is correct for all inputs.
cat > "$tmp/f.lisp" <<LEOF
(include-book "centaur/sv/top" :dir :system)
(include-book "centaur/vl/loader/top" :dir :system)
(include-book "oslib/ls" :dir :system)
(include-book "centaur/sv/vl/top" :dir :system)
(include-book "centaur/fgl/top" :dir :system)
(include-book "centaur/fgl/def-fgl-thm" :dir :system)
(include-book "centaur/misc/tshell" :dir :system)
(value-triple (acl2::tshell-ensure))
(in-package "SV")
(defconsts (*add* state)
  (b* (((mv lr state) (vl::vl-load (vl::make-vl-loadconfig :start-files (list "$tmp/t.v"))))
       (design (vl::vl-loadresult->design lr))
       ((mv err sd ?g ?b) (vl::vl-design->svex-design "adder8" design (vl::make-vl-simpconfig))))
    (and err (er hard? 'add "~@0" err))
    (mv sd state)))
(defsvtv\$ add-run :design *add* :phases ((:label c0 :inputs (("a" a) ("b" b)) :outputs (("s" s)))))
(fgl::def-fgl-thm adder8-correct
  :hyp (and (unsigned-byte-p 8 a) (unsigned-byte-p 8 b))
  :concl (equal (cdr (assoc 's (svtv-run (add-run) (list (cons 'a a) (cons 'b b))))) (+ a b)))
(cw "FGL-TEST-OK~%")
LEOF
fout=$("$ACL2_BIN" < "$tmp/f.lisp" 2>&1) || true
echo "$fout" | grep -q 'FGL-TEST-OK' && ! echo "$fout" | grep -qE 'ACL2 Error|HARD ACL2' \
  || { echo "$fout" | tail -30; echo "FAILED: FGL proof"; exit 1; }
echo "OK: FGL proves adder8 correct for all inputs (SAT solver: $(command -v glucose))"
for t in iverilog verilator yosys; do command -v $t >/dev/null && echo "found: $t" || { echo "missing: $t"; exit 1; }; done
