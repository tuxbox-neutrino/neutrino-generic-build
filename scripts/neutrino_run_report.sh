#!/bin/sh
#
# neutrino_run_report.sh - decode Neutrino's shutdown action after a host run.
#
# Neutrino hands its follow-up action (poweroff/reboot/restart) to the caller via
# an action file; older binaries only encode it in the exit status (1=poweroff,
# 2=reboot, 3=restart). This helper reads the action file, falls back to the
# legacy exit-code mapping when it is missing, prints a human-readable line, and
# exits 0 for any clean shutdown or <rc> for a genuine error. It is the shared
# implementation behind the run-direct and run-nspawn targets and is unit-tested
# by tests/shell/test_neutrino_run_report.sh.
#
# Usage: neutrino_run_report.sh <label> <rc> <action_file>

label="${1:?label required}"
rc="${2:?rc required}"
action_file="${3:?action file required}"

action=""
if [ -r "$action_file" ]; then
	read -r action < "$action_file" || action=""
	rm -f "$action_file"
fi

# Legacy fallback: a binary that predates the action file only sets the exit
# status. Codes 1/2/3 always mean a shutdown action (a real error is 255 or a
# signal), so mapping them here is safe and keeps the dev UX clean.
if [ -z "$action" ]; then
	case "$rc" in
		1) action=poweroff ;;
		2) action=reboot ;;
		3) action=restart ;;
	esac
fi

case "$action" in
	poweroff) echo "[$label] Neutrino requested shutdown"; exit 0 ;;
	reboot)   echo "[$label] Neutrino requested reboot"; exit 0 ;;
	restart)  echo "[$label] Neutrino requested restart"; exit 0 ;;
esac

# No shutdown action: a clean normal exit (rc 0) is fine, anything else is a real
# error that must surface to make.
if [ "$rc" -ne 0 ]; then
	echo "[$label] Neutrino exited with code $rc"
	exit "$rc"
fi
