cask "freesnitch" do
  version "1.3.0"
  sha256 "5130597b3b1f289c672e1168d522d79c7414b7fb53f5458f7c3bd0e4b8a09ad3"

  url "https://github.com/isaaclins/freesnitch/releases/download/v#{version}/FreeSnitch-#{version}.dmg"
  name "FreeSnitch"
  desc "Per-app network firewall"
  homepage "https://github.com/isaaclins/freesnitch"

  livecheck do
    url "https://isaaclins.com/freesnitch/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :ventura

  app "FreeSnitch.app"

  # Both scripts mirror Scripts/uninstall_freesnitch.sh in the FreeSnitch repository.
  # Their text goes to /bin/sh on standard input: when a script fails, Homebrew
  # prints the command it ran, and that is then `/bin/sh -s`, not the script.
  #
  # Homebrew runs these uninstall steps on `brew upgrade` and `brew reinstall`
  # too. Those replace the app in place, the way FreeSnitch's own updater does,
  # so the firewall keeps running and nothing is torn down (Homebrew still quits
  # the app for the swap and opens it again afterwards). Homebrew does not
  # tell an uninstall script which command it is part of, so each script reads
  # the running `brew` command from its parent processes. If it cannot tell,
  # it refuses and changes nothing: guessing "uninstall" during an upgrade
  # would tear the firewall down.
  uninstall early_script: {
              executable: "/bin/sh",
              args:       ["-s"],
              input:      <<~SH,
                replacing() {
                  set -f
                  pid=$PPID
                  while [ "${pid:-0}" -gt 1 ]; do
                    # Only Homebrew's own Ruby process counts, never a sudo or
                    # sh in between.
                    executable=$(/bin/ps -ww -o comm= -p "$pid") || return 2
                    case "${executable##*/}" in
                      ruby*)
                        command=$(/bin/ps -ww -o args= -p "$pid") || return 2
                        case "$command" in
                          *"/Library/Homebrew/brew.rb "*)
                            # The first word after brew.rb that is not a flag
                            # (`brew --debug upgrade`) is the brew command.
                            for word in ${command#*/Library/Homebrew/brew.rb }; do
                              case "$word" in
                                -*) ;;
                                upgrade | reinstall | install) return 0 ;;
                                *) return 1 ;;
                              esac
                            done
                            return 2
                            ;;
                        esac
                        ;;
                    esac
                    pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d " ")
                  done
                  return 2
                }
                # 0: upgrade or reinstall, 1: uninstall, 2: cannot tell.
                replacing
                how=$?
                [ "$how" -eq 0 ] && exit 0
                if [ "$how" -ne 1 ]; then
                  echo "Could not tell whether Homebrew is upgrading or removing FreeSnitch, so nothing was changed." >&2
                  exit 1
                fi

                # Only FreeSnitch itself can remove its network extension:
                # systemextensionsctl refuses while System Integrity Protection
                # is on, and removing the app leaves the extension behind. Once
                # removed, macOS lists it as "terminated waiting to uninstall on
                # reboot" until the next restart. It no longer runs and filters
                # nothing then. The same rule as the app: an entry still runs
                # unless it is being uninstalled or not enabled (an empty first
                # column; enabled ones are marked "*"). Any other state, known
                # or not, counts. A listing that fails is not proof it is gone.
                extension_active() {
                  listing=$(/usr/bin/systemextensionsctl list 2>/dev/null) || return 2
                  echo "$listing" | /usr/bin/grep -F "io.isaaclins.freesnitch.netext" |
                    /usr/bin/grep -v "uninstall" | /usr/bin/grep -v "^[[:blank:]]" | /usr/bin/grep -q .
                }
                check() {
                  extension_active
                  state=$?
                  if [ "$state" -eq 2 ]; then
                    echo "Could not check FreeSnitch's network filter, so nothing was removed. Try again." >&2
                    exit 1
                  fi
                  [ "$state" -eq 1 ] && exit 0
                }
                check

                # Ask FreeSnitch to remove it. It quits by itself when macOS
                # has answered. Builds before 1.2.0 cannot do this and would
                # open as usual, so they are not started.
                app="#{appdir}/FreeSnitch.app"
                marker=FreeSnitchRemovesNetworkExtensionOnRequest
                if /usr/libexec/PlistBuddy -c "Print :$marker" "$app/Contents/Info.plist" >/dev/null 2>&1; then
                  # A FreeSnitch that is still running could have a rule save or
                  # an extension activation in flight and undo the removal, so
                  # it quits first. Homebrew's own quit step comes only after
                  # this script. FreeSnitch fails open when it quits.
                  /usr/bin/pkill -x FreeSnitch >/dev/null 2>&1
                  waited=0
                  while /usr/bin/pgrep -x FreeSnitch >/dev/null 2>&1; do
                    if [ "$waited" -ge 20 ]; then
                      echo "FreeSnitch is still running. Quit it from its menu bar icon, then run this again." >&2
                      exit 1
                    fi
                    /bin/sleep 0.5
                    waited=$((waited + 1))
                  done
                  echo "Removing FreeSnitch's network filter. macOS may ask you to allow it."
                  /usr/bin/open -n -W "$app" --args --remove-network-extension
                  check
                fi
                echo "FreeSnitch's network filter is still on. Open FreeSnitch, choose Settings > Uninstall, then run this again." >&2
                exit 1
              SH
            },
            quit:         "io.isaaclins.freesnitch",
            script:       {
              executable: "/bin/sh",
              args:       ["-s"],
              input:      <<~SH,
                replacing() {
                  set -f
                  pid=$PPID
                  while [ "${pid:-0}" -gt 1 ]; do
                    # Only Homebrew's own Ruby process counts, never a sudo or
                    # sh in between.
                    executable=$(/bin/ps -ww -o comm= -p "$pid") || return 2
                    case "${executable##*/}" in
                      ruby*)
                        command=$(/bin/ps -ww -o args= -p "$pid") || return 2
                        case "$command" in
                          *"/Library/Homebrew/brew.rb "*)
                            # The first word after brew.rb that is not a flag
                            # (`brew --debug upgrade`) is the brew command.
                            for word in ${command#*/Library/Homebrew/brew.rb }; do
                              case "$word" in
                                -*) ;;
                                upgrade | reinstall | install) return 0 ;;
                                *) return 1 ;;
                              esac
                            done
                            return 2
                            ;;
                        esac
                        ;;
                    esac
                    pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d " ")
                  done
                  return 2
                }
                # 0: upgrade or reinstall, 1: uninstall, 2: cannot tell.
                replacing
                how=$?
                [ "$how" -eq 0 ] && exit 0
                if [ "$how" -ne 1 ]; then
                  echo "Could not tell whether Homebrew is upgrading or removing FreeSnitch, so nothing was changed." >&2
                  exit 1
                fi

                # Stop the privileged helper. It runs from inside the app
                # bundle, so the bundle must not be removed underneath it.
                helper=system/io.isaaclins.freesnitch.helper
                /bin/launchctl bootout "$helper" >/dev/null 2>&1 || true
                if /bin/launchctl print "$helper" 2>/dev/null | /usr/bin/grep -q "/FreeSnitch.app/"; then
                  echo "FreeSnitch's helper is still running. Switch FreeSnitch off in System Settings > General > Login Items & Extensions, then run this command again." >&2
                  exit 1
                fi

                # Empty and flush FreeSnitch's pf anchor. The file stays, empty,
                # because /etc/pf.conf still loads it at boot. pf.conf itself is
                # never touched and pf is never turned off.
                anchor=/etc/pf.anchors/puresnitch
                if [ -L "$anchor" ] || { [ -e "$anchor" ] && [ ! -f "$anchor" ]; }; then
                  echo "Refusing to write $anchor: it is not a regular file." >&2
                  exit 1
                fi
                if [ -f "$anchor" ]; then
                  echo "# FreeSnitch pf anchor - FreeSnitch was uninstalled, so it holds no rules." > "$anchor" || exit 1
                fi
                if ! /sbin/pfctl -a puresnitch -F all >/dev/null 2>&1 ||
                   ! /sbin/pfctl -a puresnitch -f /dev/null >/dev/null 2>&1; then
                  echo "Could not flush FreeSnitch's pf anchor. Run 'sudo pfctl -a puresnitch -F all', then run this command again." >&2
                  exit 1
                fi

                insights="/Library/Application Support/FreeSnitch/Insights"
                if [ -d "$insights" ] && [ ! -L "$insights" ]; then
                  /bin/rm -rf -- "$insights"
                fi
              SH
              # Homebrew's own sudo, which prompts in the terminal. A sudo
              # started inside the script would run in a background process
              # group and could not ask for the password.
              sudo:       true,
            }

  # Your rules live in /Library/Application Support/FreeSnitch/freesnitch.sqlite.
  # A plain uninstall keeps them for a reinstall; --zap removes them too.
  zap trash: [
    "/Library/Application Support/FreeSnitch",
    "~/Library/Application Support/FreeSnitch",
    "~/Library/Caches/io.isaaclins.freesnitch",
    "~/Library/Group Containers/BHAF4L4726.io.isaaclins.freesnitch",
    "~/Library/HTTPStorages/io.isaaclins.freesnitch",
    "~/Library/Preferences/io.isaaclins.freesnitch.plist",
  ]

  caveats <<~EOS
    `brew uninstall --cask freesnitch` asks FreeSnitch to remove its network
    filter first; macOS may ask you to allow that. You can also uninstall from
    the app: FreeSnitch > Settings > Uninstall.
  EOS
end
