#!/usr/bin/env bash
# Exercises the two uninstall scripts in Casks/freesnitch.rb without touching
# the real system. Every system path the scripts use (systemextensionsctl,
# launchctl, pfctl, the pf anchor, the Insights folder) is rewritten to a fake
# inside a throwaway folder, so nothing outside that folder can change.
#
# It checks that:
#   - `brew upgrade`, `brew reinstall` and `brew install` skip both scripts,
#     also with a global flag before the command (`brew --debug upgrade`),
#   - `brew uninstall` asks FreeSnitch to remove a still active network
#     extension and goes on once it is gone; it refuses with one short line
#     when that did not work, when the app is too old to be asked, and when the
#     listing itself fails; an extension macOS already stopped ("terminated
#     waiting to uninstall on reboot") does not hold it up,
#   - `brew uninstall` stops the helper, empties the anchor file without
#     deleting it, flushes the anchor and removes Insights,
#   - it refuses while the helper still runs from the bundle, when the anchor
#     is a symlink, and when pfctl fails,
#   - a run whose brew command cannot be found is treated as an uninstall,
#   - a sudo-like layer between brew and the script never decides the brew
#     command (only the Ruby process does),
#   - the cask hands both scripts to `/bin/sh -s` on standard input, so the
#     command Homebrew prints when one fails holds no script text.
#
# Not covered here: the real sudo prompt and the real systemextensionsctl,
# launchctl, pfctl, open and PlistBuddy. Those need a real `brew uninstall`
# on a Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK="$ROOT/Casks/freesnitch.rb"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/freesnitch-cask-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# Pull the two heredocs out of the cask, in order: early_script, then script.
extract() {
  awk -v want="$1" '
    /<<~SH,$/ { n++; inside = (n == want); next }
    inside && /^ *SH$/ { inside = 0; next }
    inside { print }
  ' "$CASK" | sed -E 's/^ {16}//'
}

GUARD_SRC="$TMP/guard.sh"
TEARDOWN_SRC="$TMP/teardown.sh"
extract 1 > "$GUARD_SRC"
extract 2 > "$TEARDOWN_SRC"
[[ -s "$GUARD_SRC" && -s "$TEARDOWN_SRC" ]] || { echo "could not extract both scripts from $CASK"; exit 1; }

# Fresh fake system for one case.
setup() {
  SYS="$TMP/case-$1"
  rm -rf "$SYS"
  mkdir -p "$SYS/bin" "$SYS/etc/pf.anchors" "$SYS/support/Insights"
  : > "$SYS/calls"
  echo "pass out quick on en0 all" > "$SYS/etc/pf.anchors/puresnitch"
  touch "$SYS/support/Insights/day.json"

  cat > "$SYS/bin/systemextensionsctl" <<EOF
#!/bin/sh
echo "systemextensionsctl \$*" >> "$SYS/calls"
[ -f "$SYS/sysext-fails" ] && exit 1
echo "1 extension(s)"
[ -f "$SYS/sysext-present" ] && echo "*	*	BHAF4L4726	io.isaaclins.freesnitch.netext (1.1.0/34)	FreeSnitch	[activated enabled]"
[ -f "$SYS/sysext-validating" ] && echo "*	*	BHAF4L4726	io.isaaclins.freesnitch.netext (1.1.0/34)	FreeSnitch	[validating by category]"
[ -f "$SYS/sysext-stopped" ] && echo "		BHAF4L4726	io.isaaclins.freesnitch.netext (1.1.0/34)	FreeSnitch	[terminated waiting to uninstall on reboot]"
exit 0
EOF
  # The app answers --remove-network-extension only from 1.2.0 on.
  mkdir -p "$SYS/Applications/FreeSnitch.app/Contents"
  echo "plist" > "$SYS/Applications/FreeSnitch.app/Contents/Info.plist"
  cat > "$SYS/bin/PlistBuddy" <<EOF
#!/bin/sh
echo "PlistBuddy \$*" >> "$SYS/calls"
[ -f "$SYS/app-new" ] && [ -f "\$3" ] && exit 0
echo "Print: Entry Does Not Exist" >&2
exit 1
EOF
  cat > "$SYS/bin/open" <<EOF
#!/bin/sh
echo "open \$*" >> "$SYS/calls"
if [ -f "$SYS/app-removes" ]; then rm -f "$SYS/sysext-present"; touch "$SYS/sysext-stopped"; fi
exit 0
EOF
  cat > "$SYS/bin/launchctl" <<EOF
#!/bin/sh
echo "launchctl \$*" >> "$SYS/calls"
if [ "\$1" = print ]; then
  [ -f "$SYS/helper-stuck" ] && echo "program = /Applications/FreeSnitch.app/Contents/MacOS/FreeSnitchHelper"
fi
exit 0
EOF
  cat > "$SYS/bin/pfctl" <<EOF
#!/bin/sh
echo "pfctl \$*" >> "$SYS/calls"
[ -f "$SYS/pfctl-fails" ] && exit 1
exit 0
EOF
  chmod +x "$SYS/bin/"*

  sed -e "s#/usr/bin/systemextensionsctl#$SYS/bin/systemextensionsctl#g" \
      -e "s#/usr/libexec/PlistBuddy#$SYS/bin/PlistBuddy#g" \
      -e "s#/usr/bin/open#$SYS/bin/open#g" \
      -e "s|#{appdir}|$SYS/Applications|g" \
      "$GUARD_SRC" > "$SYS/guard.sh"
  sed -e "s#/bin/launchctl#$SYS/bin/launchctl#g" \
      -e "s#/sbin/pfctl#$SYS/bin/pfctl#g" \
      -e "s#/etc/pf.anchors/puresnitch#$SYS/etc/pf.anchors/puresnitch#g" \
      -e "s#/Library/Application Support/FreeSnitch/Insights#$SYS/support/Insights#g" \
      "$TEARDOWN_SRC" > "$SYS/teardown.sh"
  # The fakes must be the only thing the scripts can reach.
  if grep -Eq '(^|[^A-Za-z/])/(etc/pf|sbin/pfctl|bin/launchctl|usr/bin/systemextensionsctl|usr/bin/open|usr/libexec|Library/Application|Applications/FreeSnitch)' \
       <(sed -e "s#$SYS#FAKE#g" "$SYS/teardown.sh" "$SYS/guard.sh" | grep -v '^ *#' | grep -v 'echo "'); then
    echo "a real system path survived the rewrite"; exit 1
  fi
}

# Run a script the way brew does. brew is a Ruby process whose command line is
# `ruby ... /Library/Homebrew/brew.rb <command> ...`; a shell reached through a
# link named "ruby" stands in for it. Between brew and the script sits a layer
# like `sudo -E --`, and the script reaches `/bin/sh -s` on standard input, the
# way the cask hands it over.
run_as_brew() {
  local script="${@: -1}"
  # A long prefix keeps "brew.rb" far past column 80, where ps would cut a
  # command line it prints without a terminal and without -ww.
  local fake_brew="$TMP/prefix/a-long-folder-name-that-pushes-the-brew-command-past-eighty-columns/Library/Homebrew/brew.rb"
  mkdir -p "$(dirname "$fake_brew")" "$TMP/ruby-bin"
  ln -sf /bin/sh "$TMP/ruby-bin/ruby"
  printf '#!/bin/sh\n"$@"\nexit $?\n' > "$TMP/ruby-bin/sudo-layer"
  chmod +x "$TMP/ruby-bin/sudo-layer"
  printf '#!/bin/sh\n"%s" /bin/sh -s < "$SCRIPT"\nexit $?\n' "$TMP/ruby-bin/sudo-layer" > "$fake_brew"
  SCRIPT="$script" COLUMNS= "$TMP/ruby-bin/ruby" "$fake_brew" "${@:1:$#-1}" --cask freesnitch
}

expect_status() {
  local want="$1" name="$2"; shift 2
  local got=0
  "$@" > "$SYS/out" 2>&1 || got=$?
  if { [[ "$want" == 0 ]] && [[ "$got" == 0 ]]; } || { [[ "$want" != 0 ]] && [[ "$got" != 0 ]]; }; then
    pass "$name"
  else
    fail "$name (exit $got)"; sed 's/^/     /' "$SYS/out"
  fi
}

anchor_untouched() { [[ "$(cat "$SYS/etc/pf.anchors/puresnitch")" == "pass out quick on en0 all" ]]; }

for command in upgrade reinstall install; do
  setup "$command"
  touch "$SYS/sysext-present"
  expect_status 0 "brew $command skips the extension check" run_as_brew "$command" "$SYS/guard.sh"
  expect_status 0 "brew $command skips the teardown" run_as_brew "$command" "$SYS/teardown.sh"
  if [[ ! -s "$SYS/calls" ]] && anchor_untouched && [[ -e "$SYS/support/Insights/day.json" ]]; then
    pass "brew $command touches nothing"
  else
    fail "brew $command touches nothing"; cat "$SYS/calls"
  fi
done

setup flag-first
touch "$SYS/sysext-present"
expect_status 0 "brew --debug upgrade still counts as an upgrade" run_as_brew --debug upgrade "$SYS/guard.sh"
expect_status 1 "brew --verbose uninstall still counts as an uninstall" run_as_brew --verbose uninstall "$SYS/guard.sh"

setup sysext-present
touch "$SYS/sysext-present" "$SYS/app-new" "$SYS/app-removes"
expect_status 0 "uninstall has FreeSnitch remove an active extension, then goes on" run_as_brew uninstall "$SYS/guard.sh"
grep -q "^open -n -W $SYS/Applications/FreeSnitch.app --args --remove-network-extension" "$SYS/calls" \
  && pass "FreeSnitch is asked to remove its extension" || fail "FreeSnitch is asked to remove its extension"

setup app-could-not
touch "$SYS/sysext-present" "$SYS/app-new"
expect_status 1 "uninstall refuses when FreeSnitch could not remove the extension" run_as_brew uninstall "$SYS/guard.sh"
grep -q "Settings > Uninstall" "$SYS/out" && pass "the refusal says what to do" || fail "the refusal says what to do"
grep -q "systemextensionsctl\|replacing\|esac" "$SYS/out" && fail "the refusal prints script text" || pass "the refusal prints no script text"

setup app-too-old
touch "$SYS/sysext-present"
expect_status 1 "uninstall refuses for a FreeSnitch that cannot be asked" run_as_brew uninstall "$SYS/guard.sh"
grep -q "^open" "$SYS/calls" && fail "an older FreeSnitch was started" || pass "an older FreeSnitch is not started"

setup sysext-validating
touch "$SYS/sysext-validating"
expect_status 1 "an extension in any other state still holds the uninstall up" run_as_brew uninstall "$SYS/guard.sh"

setup sysext-stopped
touch "$SYS/sysext-stopped" "$SYS/app-new"
expect_status 0 "an extension macOS already stopped does not hold the uninstall up" run_as_brew uninstall "$SYS/guard.sh"
grep -q "^open" "$SYS/calls" && fail "FreeSnitch was started for a stopped extension" || pass "FreeSnitch is not started for a stopped extension"

setup sysext-fails
touch "$SYS/sysext-fails"
expect_status 1 "uninstall refuses when the extension list cannot be read" run_as_brew uninstall "$SYS/guard.sh"

setup unknown-command
touch "$SYS/sysext-present"
expect_status 1 "an unknown brew command is treated as an uninstall" /bin/sh "$SYS/guard.sh"

setup clean
expect_status 0 "uninstall passes the extension check once it is gone" run_as_brew uninstall "$SYS/guard.sh"
expect_status 0 "uninstall teardown succeeds" run_as_brew uninstall "$SYS/teardown.sh"
grep -q "launchctl bootout system/io.isaaclins.freesnitch.helper" "$SYS/calls" && pass "the helper is stopped" || fail "the helper is stopped"
grep -q "pfctl -a puresnitch -F all" "$SYS/calls" && grep -q "pfctl -a puresnitch -f /dev/null" "$SYS/calls" \
  && pass "only the puresnitch anchor is flushed" || fail "only the puresnitch anchor is flushed"
grep -Eq "pfctl -(d|f /etc/pf.conf)" "$SYS/calls" && fail "pf itself was touched" || pass "pf itself is left alone"
if [[ -f "$SYS/etc/pf.anchors/puresnitch" ]] && ! grep -qv '^#' "$SYS/etc/pf.anchors/puresnitch"; then
  pass "the anchor file is kept and holds no rules"
else
  fail "the anchor file is kept and holds no rules"
fi
[[ ! -e "$SYS/support/Insights" ]] && pass "Insights is removed" || fail "Insights is removed"

setup helper-stuck
touch "$SYS/helper-stuck"
expect_status 1 "uninstall refuses while the helper still runs from the bundle" run_as_brew uninstall "$SYS/teardown.sh"
anchor_untouched && pass "nothing is flushed after that refusal" || fail "nothing is flushed after that refusal"

setup anchor-symlink
rm "$SYS/etc/pf.anchors/puresnitch"
echo "keep me" > "$SYS/elsewhere"
ln -s "$SYS/elsewhere" "$SYS/etc/pf.anchors/puresnitch"
expect_status 1 "uninstall refuses to write through a symlinked anchor" run_as_brew uninstall "$SYS/teardown.sh"
[[ "$(cat "$SYS/elsewhere")" == "keep me" ]] && pass "the symlink target is untouched" || fail "the symlink target is untouched"

setup pfctl-fails
touch "$SYS/pfctl-fails"
expect_status 1 "uninstall fails when the anchor cannot be flushed" run_as_brew uninstall "$SYS/teardown.sh"

setup no-anchor
rm "$SYS/etc/pf.anchors/puresnitch"
expect_status 0 "uninstall works when the anchor file was never created" run_as_brew uninstall "$SYS/teardown.sh"
[[ ! -e "$SYS/etc/pf.anchors/puresnitch" ]] && pass "no anchor file is created" || fail "no anchor file is created"

# What Homebrew prints on a failure is the command it ran: the executable and
# args, never the input. Read both script directives the way Homebrew does and
# check the script text is only in the input.
if ruby -e '
  src = File.read(ARGV[0])
  blocks = src.scan(/executable: "([^"]+)",\n\s*args:\s*(\[[^\]]*\]),\n\s*input:\s*<<~SH,/)
  exit 1 unless blocks.size == 2
  blocks.each { |exe, args| exit 1 unless exe == "/bin/sh" && eval(args) == ["-s"] }
  exit 1 if src.include?("args:       [\"-c\"")
' "$CASK"; then
  pass "both scripts reach /bin/sh -s on standard input, so a failure prints no script text"
else
  fail "both scripts reach /bin/sh -s on standard input, so a failure prints no script text"
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed.\n' "$failures"
  exit 1
fi
printf '\nAll checks passed.\n'
