cask "freesnitch" do
  version "1.1.0"
  sha256 "f15857e6e328936b1623cfe309c1d7a357d1150f77fbe2e24a8ed7c1650382cd"

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
  #
  # Homebrew runs these uninstall steps on `brew upgrade` and `brew reinstall`
  # too. Those replace the app in place, the way FreeSnitch's own updater does,
  # so the firewall keeps running and nothing is torn down (Homebrew still quits
  # the app for the swap and opens it again afterwards). Homebrew does not
  # tell an uninstall script which command it is part of, so each script reads
  # the running `brew` command from its parent processes. If it cannot tell, it
  # treats the run as an uninstall, which at worst refuses to remove the app.
  uninstall early_script: {
              executable: "/bin/sh",
              args:       ["-c", <<~SH],
                replacing() {
                  set -f
                  pid=$PPID
                  while [ "${pid:-0}" -gt 1 ]; do
                    # Only Homebrew's own Ruby process counts. sudo and sh
                    # carry this script's text, brew.rb path included, in
                    # their arguments.
                    executable=$(/bin/ps -ww -o comm= -p "$pid") || return 1
                    case "${executable##*/}" in
                      ruby*)
                        command=$(/bin/ps -ww -o args= -p "$pid") || return 1
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
                            return 1
                            ;;
                        esac
                        ;;
                    esac
                    pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d " ")
                  done
                  return 1
                }
                replacing && exit 0

                # Only FreeSnitch itself can deactivate its network extension:
                # systemextensionsctl refuses while System Integrity Protection
                # is on. Removing the app first would leave the extension
                # behind. A listing that fails is not proof that it is gone.
                if ! listing=$(/usr/bin/systemextensionsctl list 2>/dev/null); then
                  echo "Cannot check whether FreeSnitch's network extension is still registered, so FreeSnitch was left in place." >&2
                  exit 1
                fi
                case "$listing" in
                  *io.isaaclins.freesnitch.netext*)
                    echo "FreeSnitch's network extension is still registered with macOS, and only FreeSnitch can remove it." >&2
                    echo "Open FreeSnitch, go to Settings > Uninstall, restart your Mac, then run this command again." >&2
                    exit 1
                    ;;
                esac
              SH
            },
            quit:         "io.isaaclins.freesnitch",
            script:       {
              executable: "/bin/sh",
              args:       ["-c", <<~SH],
                replacing() {
                  set -f
                  pid=$PPID
                  while [ "${pid:-0}" -gt 1 ]; do
                    # Only Homebrew's own Ruby process counts. sudo and sh
                    # carry this script's text, brew.rb path included, in
                    # their arguments.
                    executable=$(/bin/ps -ww -o comm= -p "$pid") || return 1
                    case "${executable##*/}" in
                      ruby*)
                        command=$(/bin/ps -ww -o args= -p "$pid") || return 1
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
                            return 1
                            ;;
                        esac
                        ;;
                    esac
                    pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d " ")
                  done
                  return 1
                }
                replacing && exit 0

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
    To uninstall, start in the app: FreeSnitch > Settings > Uninstall, then
    restart your Mac. Only FreeSnitch can remove its network extension, so
    `brew uninstall --cask freesnitch` refuses to run until that is done.
  EOS
end
