# Koi Aquarium

A little translucent aquarium for your Mac desktop. Feed the fish, decorate the tank, and turn your friends into fish that deliver tiny messages. The aquarium sits behind your app windows.

## Install on your Mac

1. Download the repository as a ZIP and unzip it.
2. If you need Apple’s Command Line Tools, run `xcode-select --install` in Terminal and finish the installer.
3. In Terminal, type `bash ` with a trailing space. Drag `build.command` from the unzipped folder into Terminal and press Return.
4. The script builds and opens **Koi Aquarium.app**. After that, you can open it directly from Finder.

If the build reports a Swift SDK mismatch, check **System Settings → General → Software Update** for a Command Line Tools update, then rerun `build.command`.

## Make the tank yours

- **Add fish.** A fresh tank starts empty. Double-click and choose **Add Fish**. Pick **Add a common fish** to add a koi, guppy, or pearl minnow without setting up messaging. Once you’ve added your first fish, double-click the glass above the waterline to edit.
- **Manage fish.** Right-click → **Manage Fish** to open a side panel with fish icons and names. Click **Select**, pick any fish, then click **Delete Selected**. Removing a linked fish asks for confirmation.
- **Feed and move the tank.** Click the water to drop food. Each click adds pellets. Drag the tank to move it and watch the water slosh. In edit mode, drag the bottom-right grip to resize it.
- **Decorate.** Drag items from the edit tray into the water. Regular decor snaps to the floor. Snails and starfish can sit higher up and slowly creep from where you place them. Shrimp wander near the floor and hop when clicked. A shrimp click doesn’t drop food.
- **Rearrange or remove items.** Drag the treasure chest along the floor in edit mode. To remove a decoration or creature, drag it out of the water and release it.
- **Change the look.** Right-click to switch water colors, choose a sand or gravel style under **Tank floor**, or toggle **Automatic moonlight**. The fish occasionally blow tiny bubbles.

Your fish, friends, tank position, size, and decor are saved when you quit. Use the fish icon in the Mac menu bar to show, hide, or quit the aquarium.

## Preview a message on your own Mac

Right-click the tank → **Preview a Message…**, type a sample note, and click **Preview**. A fish appears with a glass speech bubble sized to the message. Click the bubble to dismiss it. The preview stays on your Mac and works without a relay.

## Set up friend messaging

One person hosts the relay and everyone uses the same HTTPS address. These steps show how to host it on your Mac with Tailscale Funnel. Your Mac needs to stay awake and online while the relay is in use. Your friends don’t need to install Tailscale.

### 1. Start the relay

You’ll need Python 3.10 or newer with SQLite 3.38 or newer. Open Terminal and go to the unzipped folder containing `relay.py`. For example, if the folder is in Downloads:

```bash
cd ~/Downloads/KoiAquarium
```

Then paste this whole block. It creates a `host` mailbox and a `friend` mailbox the first time, and reuses them when you restart. Both tokens and the message database live outside the project folder.

```bash
(
  umask 077
  mkdir -p "$HOME/.koi-aquarium"
  koi_config="$HOME/.koi-aquarium/mailboxes.json"
  if [ ! -f "$koi_config" ]; then
    python3 -c 'import json, secrets; print(json.dumps({name: secrets.token_urlsafe(32) for name in ("host", "friend")}))' > "$koi_config" || exit 1
  fi
  KOI_FRIEND_MAILBOXES="$(cat "$koi_config")" \
  KOI_DATABASE="$HOME/.koi-aquarium/mail.sqlite3" \
  python3 relay.py
)
```

If Terminal stays open without returning to the prompt, leave that window running. If you already set up a mailbox named `name`, keep using `name` wherever the examples below say `host`.

### 2. Get an HTTPS address

Install and sign in to [Tailscale for Mac](https://tailscale.com/docs/install/mac). In a **second Terminal window**, run:

```bash
tailscale funnel 8765
```

Follow the approval prompt if one appears. Copy the full `https://…ts.net` address that Tailscale prints and leave this window running too. Funnel makes the relay reachable over the internet, and Koi requires a private mailbox token to use it. See the [Tailscale Funnel docs](https://tailscale.com/docs/features/tailscale-funnel) if the command doesn’t start.

### 3. Get your friend code

1. In Koi, right-click → **My Friend Code…**.
2. Paste the HTTPS relay address and enter `host` as your mailbox ID. In a new Terminal tab, run this to copy your token straight to your clipboard:

   ```bash
   python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home() / ".koi-aquarium/mailboxes.json").read_text())["host"], end="")' | pbcopy
   ```

3. Paste it into **Private token**, then click **Save → Copy Code**. The copied code starts with `koi1.`.
4. Give your friend the **same HTTPS address**, mailbox ID `friend`, and their own token privately. To copy their token, change `["host"]` to `["friend"]` in the command above. Your friend follows the same setup in their copy of Koi.
5. Exchange your `koi1.` codes. Each of you chooses **Add Fish**, pastes the other person’s code, enters their name, then clicks **Next** to pick their fish type.

**Share the `koi1.` code when adding someone. Keep mailbox tokens private and out of GitHub and screenshots.** To add more people, add a unique mailbox ID and random token for each person in `~/.koi-aquarium/mailboxes.json`, then restart the relay. You can generate each token with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`.

### 4. Send a test message

Double-click above the waterline → **Send Message**. Pick one friend, check several, or choose **Send to all**. Notes can be up to 72 characters. Incoming notes appear above the sender’s fish, and clicking the bubble dismisses it. You can also right-click → **Send a hello ♥** to send a heart.

Messages are encrypted by the app. The relay queues them while the recipient’s app is closed. If a test note doesn’t arrive, check that both Terminal windows are still running, both Macs use the same HTTPS address, and each person added the other’s code.

## Treasure chest and milestones

Click the chest on the tank floor to open the gift inventory beside the aquarium. You can place received gifts in your tank and send one treasure every seven days. Linking for 7, 30, 90, and 365 days unlocks a pearl, moon coral, lantern, and crystal under **Milestones**.

Gifts and milestones use the separate **Pair with a Friend…** setup for two people. On the relay host, run `python3 relay.py keys` to generate two tokens and a shared message key. Set `KOI_TOKEN_A` and `KOI_TOKEN_B` in the relay’s environment and restart it with your existing mailbox configuration and database. In **Pair with a Friend…**, both people enter the same HTTPS address and shared message key. Use token A on one Mac and token B on the other. The milestone clock starts once both copies check in.
