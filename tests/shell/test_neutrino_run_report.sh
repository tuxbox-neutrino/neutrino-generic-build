#!/bin/sh
#
# Unit test for scripts/neutrino_run_report.sh - the shared decoder behind the
# run-direct and run-nspawn targets. Exercises the action-file channel, the
# legacy exit-code fallback, and the old/new binary compatibility matrix.
#
# POSIX sh, no external deps. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$ROOT_DIR/scripts/neutrino_run_report.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

AF="$WORK/exit-action"
pass=0
fail=0

# run_case <desc> <file-content|__none__> <rc> <want-exit> <want-substr>
run_case() {
	desc="$1"; content="$2"; rc="$3"; want_exit="$4"; want_out="$5"
	rm -f "$AF"
	if [ "$content" != "__none__" ]; then
		printf '%s\n' "$content" > "$AF"
	fi
	out="$("$HELPER" run-test "$rc" "$AF" 2>&1)"; got_exit=$?
	ok=1
	[ "$got_exit" = "$want_exit" ] || ok=0
	case "$out" in
		*"$want_out"*) : ;;
		*) [ -z "$want_out" ] || ok=0 ;;
	esac
	# The helper must always consume the action file.
	[ -e "$AF" ] && ok=0
	if [ "$ok" = 1 ]; then
		pass=$((pass + 1)); printf 'ok   %-46s exit=%s\n' "$desc" "$got_exit"
	else
		fail=$((fail + 1)); printf 'FAIL %-46s want(exit=%s,~[%s]) got(exit=%s,[%s]) file=%s\n' \
			"$desc" "$want_exit" "$want_out" "$got_exit" "$out" "$([ -e "$AF" ] && echo present || echo gone)"
	fi
}

# --- action file present, posix binary (rc 0) ---
run_case "action=poweroff rc=0"            poweroff   0 0 "requested shutdown"
run_case "action=reboot rc=0"              reboot     0 0 "requested reboot"
run_case "action=restart rc=0"             restart    0 0 "requested restart"
run_case "action=none rc=0 (normal exit)"  none       0 0 ""

# --- action file wins over a legacy exit status (new binary, NEUTRINO_EXIT_CODES=legacy) ---
run_case "action=poweroff rc=1 (file wins)" poweroff  1 0 "requested shutdown"
run_case "action=reboot rc=2 (file wins)"   reboot    2 0 "requested reboot"

# --- no action file: legacy exit-code fallback (old binary) ---
run_case "no-file rc=1 (legacy poweroff)"  __none__   1 0 "requested shutdown"
run_case "no-file rc=2 (legacy reboot)"    __none__   2 0 "requested reboot"
run_case "no-file rc=3 (legacy restart)"   __none__   3 0 "requested restart"
run_case "no-file rc=0 (clean normal)"     __none__   0 0 ""

# --- genuine errors must surface ---
run_case "no-file rc=255 (error)"          __none__ 255 255 "exited with code 255"
run_case "no-file rc=137 (SIGKILL)"        __none__ 137 137 "exited with code 137"

# --- edge cases ---
run_case "empty action file, rc=2 fallback" ""       2 0 "requested reboot"
run_case "unknown token, rc=0 -> clean"    frobnicate 0 0 ""
run_case "unknown token, rc=255 -> error"  frobnicate 255 255 "exited with code 255"

echo "----"
echo "[test-shell] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
