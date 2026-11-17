# isaaclins/homebrew-tap

My Homebrew tap. For now it holds one cask, [FreeSnitch](https://github.com/isaaclins/freesnitch), my per-app firewall for macOS.

## FreeSnitch

```sh
brew install --cask isaaclins/tap/freesnitch
```

Then open FreeSnitch and approve the two prompts it shows on first launch (the network extension and the background helper).

### Updates

FreeSnitch updates itself, so a plain `brew upgrade` leaves it alone, like every other self-updating app. `brew upgrade --greedy` moves the Homebrew copy to the newest release too. An upgrade replaces the app in place and keeps the firewall running; Homebrew quits FreeSnitch for the swap and opens it again afterwards. Homebrew asks for your password once during it, because the cask's uninstall step needs administrator rights on a real uninstall and Homebrew can't tell the two apart before it asks.

### Already installed from the disk image

Let Homebrew take over the copy you have:

```sh
brew install --cask --adopt isaaclins/tap/freesnitch
```

### Uninstalling

Start in the app: **FreeSnitch > Settings > Uninstall**, then restart your Mac. Only FreeSnitch itself can remove its network extension, so Homebrew refuses to uninstall it while macOS still lists the extension. After the restart:

```sh
brew uninstall --cask freesnitch          # keeps your rules for a later reinstall
brew uninstall --cask --zap freesnitch    # also deletes your rules and settings
```

The uninstall stops FreeSnitch's helper and empties its `pf` anchor, the same way FreeSnitch's own uninstaller does. It never turns `pf` off and never edits `/etc/pf.conf`, so your Mac's network keeps working afterwards.

## How the cask is kept current

FreeSnitch's release script bumps the version and checksum here after each release. `tests/freesnitch_uninstall_test.sh` checks the uninstall steps against a fake system, and CI runs it together with `brew style` and `brew audit` on every push.

## License

[MIT](LICENSE)
