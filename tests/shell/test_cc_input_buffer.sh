#!/bin/sh
#
# Unit test for CCInputBuffer, the text model under the cc input dialogs
# (neutrino src/gui/components/cc_input_buffer.cpp).
#
# The buffer decides what a user can type and, when a dialog opens, what
# of the stored value reaches the field. A filter that drops a glyph of
# the stored value changes that value on the first OK without anybody
# having edited it - the old string input would save the timer weekday
# mask "XXXXX--" as "" that way. So the contract under test is: a filter
# rules typing, never the value a dialog is opened with.
#
# The buffer has no dependencies, so it is compiled on the host against a
# small driver; no Neutrino build is needed. Skips when there is no C++
# compiler or no Neutrino source tree.
#
# POSIX sh. Exits 0 on success, 1 on any failure.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_DIR="${NEUTRINO_SRC_DIR:-$ROOT_DIR/sources/neutrino}/src/gui/components"
CXX="${CXX:-c++}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$SRC_DIR/cc_input_buffer.cpp" ]; then
	printf 'skip cc_input_buffer.cpp not found under %s\n' "$SRC_DIR"
	exit 0
fi
if ! command -v "$CXX" >/dev/null 2>&1; then
	printf 'skip no C++ compiler (%s)\n' "$CXX"
	exit 0
fi

cat > "$WORK/driver.cpp" <<'CPP'
#include "cc_input_buffer.h"
#include <cstdio>
#include <string>

static int failures = 0;

static void check(bool cond, const char *what, const std::string &got)
{
	if (cond)
		printf("ok   %s\n", what);
	else
	{
		printf("FAIL %s\n     got \"%s\"\n", what, got.c_str());
		failures++;
	}
}

int main()
{
	/* FILTER_CHARSET takes what the set names, in UTF-8 */
	{
		CCInputBuffer b;
		b.setFilterMode(CCInputBuffer::FILTER_CHARSET);
		b.setCharset("ab\xc2\xa7" "1");
		bool ok = b.insert("a") && b.insert("\xc2\xa7") && b.insert("1");
		check(ok && b.getText() == "a\xc2\xa7" "1", "charset accepts its glyphs, also multi-byte", b.getText());
		check(!b.insert("c") && !b.insert("2"), "charset refuses glyphs outside the set", b.getText());
	}

	/* the value a dialog opens with stays intact */
	{
		CCInputBuffer b;
		b.setFilterMode(CCInputBuffer::FILTER_CHARSET);
		b.setCharset("0123456789");
		b.setText("52.520000");
		check(b.getText() == "52.520000", "setText keeps glyphs outside the set", b.getText());
		b.moveEnd();
		check(b.backspace() && b.insert("1") && b.getText() == "52.520001", "digits still edit such a value", b.getText());
		b.moveHome();
		b.moveRight(); b.moveRight(); b.moveRight();
		check(b.backspace() && b.getText() == "52520001" && b.insert(".") && b.getText() == "52.520001",
			"a kept glyph may be typed again", b.getText());
		b.setText("17");
		check(!b.insert("."), "a new value brings its own kept glyphs, not the old ones", b.getText());
	}

	/* the timer weekday mask of the old string input */
	{
		CCInputBuffer b;
		b.setFilterMode(CCInputBuffer::FILTER_CHARSET);
		b.setCharset("0123456789");
		b.setText("XXXXX--");
		check(b.getText() == "XXXXX--", "weekday mask survives a digits-only set", b.getText());
	}

	/* an empty set takes any glyph */
	{
		CCInputBuffer b;
		b.setFilterMode(CCInputBuffer::FILTER_CHARSET);
		check(b.insert("x") && b.insert("\xc3\xa4"), "empty charset takes any glyph", b.getText());
	}

	/* the other filters keep their behaviour */
	{
		CCInputBuffer b;
		b.setFilterMode(CCInputBuffer::FILTER_NUMERIC);
		b.setText("1a2");
		check(b.getText() == "12", "numeric filter still drops other glyphs in setText", b.getText());
		check(!b.insert("x") && b.insert("3"), "numeric filter still rules typing", b.getText());
	}
	{
		CCInputBuffer b;
		b.setMaxChars(3);
		b.setFilterMode(CCInputBuffer::FILTER_CHARSET);
		b.setCharset("ab");
		b.setText("abab");
		check(b.getText() == "aba", "max chars still applies with a charset", b.getText());
	}

	return failures ? 1 : 0;
}
CPP

if ! "$CXX" -std=c++11 -Wall -I"$SRC_DIR" "$SRC_DIR/cc_input_buffer.cpp" "$WORK/driver.cpp" \
	-o "$WORK/driver" > "$WORK/build.log" 2>&1; then
	printf 'FAIL cc_input_buffer does not build on the host\n'
	sed 's/^/     /' "$WORK/build.log"
	exit 1
fi

"$WORK/driver"
