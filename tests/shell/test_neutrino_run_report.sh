#!/bin/sh
#
# Unit test for the host-run path: scripts/neutrino_run_report.sh, the decoder
# behind the run-direct and run-nspawn targets, and both producers that feed
# it -- the single-instance guard in scripts/run-neutrino.sh and the runtime
# wrapper in scripts/neutrino-wrapper.sh. Exercises the action-file channel,
# the legacy exit-code fallback, the old/new binary compatibility matrix, and
# the codes that mean Neutrino never started.
#
# Every end, because pinning only the decoder proved nothing: with a producer
# reverted to `exit 1` -- the defect this file exists to prevent, a refusal
# decoded as a clean shutdown -- the suite stayed green. That happened twice,
# once per producer.
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

# The wrapper refuses to start a second instance with 75 (EX_TEMPFAIL). It used
# to refuse with 1, which the legacy mapping read as poweroff: `make run` said
# "Neutrino requested shutdown" and exited 0 for a Neutrino that never ran. The
# stale-action-file case matters too -- a previous run's file must not turn the
# refusal back into a shutdown.
run_case "no-file rc=75 (refused to start)" __none__  75 75 "did not start"
run_case "no-file rc=69 (wrapper, no binary)" __none__ 69 69 "did not start"
run_case "stale poweroff file, rc=75"      poweroff  75 75 "did not start"

# The producer end. run-neutrino.sh refuses when another Neutrino is already
# running; the code it refuses with is the whole point, so run it for real
# against a process the guard actually sees.
GUARD="$ROOT_DIR/scripts/run-neutrino.sh"
BASH_BIN="$(command -v bash 2>/dev/null || true)"
if [ ! -x "$GUARD" ] || [ -z "$BASH_BIN" ]; then
	fail=$((fail + 1))
	printf 'FAIL %-46s %s\n' "the single-instance guard refuses with 75" \
		"scripts/run-neutrino.sh or bash is missing"
else
	# A real executable named neutrino.real, not `exec -a`: that only rewrites
	# argv[0] while the kernel keeps `comm` as "sleep", and `pgrep -x` compares
	# comm -- the guard would never see the impostor and the assertion would
	# pass against a guard that does nothing.
	guard_sleep="$(command -v sleep 2>/dev/null || true)"
	rm -rf "$WORK/guardbin"; mkdir -p "$WORK/guardbin"
	guard_helper=""
	if [ -n "$guard_sleep" ] && cp "$guard_sleep" "$WORK/guardbin/neutrino.real" 2>/dev/null; then
		"$WORK/guardbin/neutrino.real" 30 &
		guard_helper=$!
	fi
	guard_seen=""
	guard_wait=0
	while [ "$guard_wait" -lt 50 ]; do
		guard_seen="$(pgrep -x neutrino.real 2>/dev/null | head -1 || true)"
		[ -n "$guard_seen" ] && break
		guard_wait=$((guard_wait + 1))
		sleep 0.1
	done
	if [ -z "$guard_seen" ]; then
		fail=$((fail + 1))
		printf 'FAIL %-46s %s\n' "the single-instance guard refuses with 75" \
			"no process named neutrino.real appeared; the guard was never reached"
	else
		guard_rc=0
		NEUTRINO_BIN=/bin/true "$BASH_BIN" "$GUARD" >/dev/null 2>&1 || guard_rc=$?
		if [ "$guard_rc" = 75 ]; then
			pass=$((pass + 1))
			printf 'ok   %-46s exit=%s\n' "the single-instance guard refuses with 75" "$guard_rc"
		else
			fail=$((fail + 1))
			printf 'FAIL %-46s want(exit=75) got(exit=%s)%s\n' \
				"the single-instance guard refuses with 75" "$guard_rc" \
				"$([ "$guard_rc" -le 3 ] && printf ' -- a shutdown code, decoded as a clean run' || printf '')"
		fi
	fi
	[ -z "$guard_helper" ] || kill "$guard_helper" 2>/dev/null || true
	[ -z "$guard_helper" ] || wait "$guard_helper" 2>/dev/null || true
fi

# The other producer: the wrapper runtime-sync installs in front of the staged
# binary. It refuses before Neutrino ever runs -- no binary, no runtime
# libraries -- and both refusals have to stay clear of 1/2/3 for the same
# reason as the guard above. This is testable at all only because the wrapper
# is a file; while it was printf'd into the runtime-sync recipe, no test could
# reach it and reverting its refusal to `exit 1` left the whole suite green.
WRAPPER="$ROOT_DIR/scripts/neutrino-wrapper.sh"

# wrapper_case <desc> <real:yes|no> <lib:yes|no> <real-rc> <want-exit> <want-substr>
wrapper_case() {
	desc="$1"; mk_real="$2"; mk_lib="$3"; real_rc="$4"; want_exit="$5"; want_out="$6"
	rm -rf "$WORK/wrap"
	mkdir -p "$WORK/wrap/usr/bin"
	if [ "$mk_lib" = yes ]; then
		mkdir -p "$WORK/wrap/usr/lib"
	fi
	cp "$WRAPPER" "$WORK/wrap/usr/bin/neutrino"
	chmod +x "$WORK/wrap/usr/bin/neutrino"
	if [ "$mk_real" = yes ]; then
		printf '#!/bin/sh\nexit %s\n' "$real_rc" > "$WORK/wrap/usr/bin/neutrino.real"
		chmod +x "$WORK/wrap/usr/bin/neutrino.real"
	fi
	out="$("$BASH_BIN" "$WORK/wrap/usr/bin/neutrino" 2>&1)"; got_exit=$?
	ok=1
	[ "$got_exit" = "$want_exit" ] || ok=0
	case "$out" in
		*"$want_out"*) : ;;
		*) [ -z "$want_out" ] || ok=0 ;;
	esac
	if [ "$ok" = 1 ]; then
		pass=$((pass + 1)); printf 'ok   %-46s exit=%s\n' "$desc" "$got_exit"
	else
		fail=$((fail + 1)); printf 'FAIL %-46s want(exit=%s,~[%s]) got(exit=%s,[%s])%s\n' \
			"$desc" "$want_exit" "$want_out" "$got_exit" "$out" \
			"$([ "$got_exit" -ge 1 ] && [ "$got_exit" -le 3 ] && printf ' -- a shutdown code, decoded as a clean run' || printf '')"
	fi
}

if [ ! -f "$WRAPPER" ] || [ -z "$BASH_BIN" ]; then
	fail=$((fail + 1))
	printf 'FAIL %-46s %s\n' "the runtime wrapper refuses with 69" \
		"scripts/neutrino-wrapper.sh or bash is missing"
else
	wrapper_case "wrapper: no neutrino.real -> 69"      no  yes 0 69 "Missing binary"
	wrapper_case "wrapper: no runtime lib dir -> 69"    yes no  0 69 "Missing runtime libraries"
	wrapper_case "wrapper: clean exit passes through"   yes yes 0 0  ""
	# set -e aborts on the real binary's status, so handle_exit_code never runs
	# and Neutrino's legacy 1 reaches the decoder intact. Were it swallowed
	# here, run-direct would report a normal exit instead of a poweroff.
	wrapper_case "wrapper: legacy shutdown 1 survives"  yes yes 1 1  ""

	# End to end: the refusal the decoder has to recognise, produced for real.
	rm -rf "$WORK/wrap"; mkdir -p "$WORK/wrap/usr/bin"
	cp "$WRAPPER" "$WORK/wrap/usr/bin/neutrino"; chmod +x "$WORK/wrap/usr/bin/neutrino"
	wrap_rc=0
	"$BASH_BIN" "$WORK/wrap/usr/bin/neutrino" >/dev/null 2>&1 || wrap_rc=$?
	rm -f "$AF"
	e2e_out="$("$HELPER" run-direct "$wrap_rc" "$AF" 2>&1)"; e2e_rc=$?
	if [ "$e2e_rc" != 0 ] && [ "${e2e_out#*did not start}" != "$e2e_out" ]; then
		pass=$((pass + 1))
		printf 'ok   %-46s exit=%s\n' "wrapper refusal -> run-direct fails" "$e2e_rc"
	else
		fail=$((fail + 1))
		printf 'FAIL %-46s want(exit!=0,~[did not start]) got(exit=%s,[%s])\n' \
			"wrapper refusal -> run-direct fails" "$e2e_rc" "$e2e_out"
	fi
fi

# --- edge cases ---
run_case "empty action file, rc=2 fallback" ""       2 0 "requested reboot"
run_case "unknown token, rc=0 -> clean"    frobnicate 0 0 ""
run_case "unknown token, rc=255 -> error"  frobnicate 255 255 "exited with code 255"

echo "----"
echo "[test-shell] pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
