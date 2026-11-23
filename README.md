# Koi Aquarium

A little translucent desktop aquarium for macOS. It runs as a borderless app at desktop level so fish can swim continuously. App windows cover the tank where they overlap it.

## Run it on your Mac

1. Unzip the download.
2. If you haven't installed Apple's Command Line Tools, run `xcode-select --install` in Terminal and wait for the installer to finish.
3. In Terminal, type `bash ` with a trailing space, drag `build.command` into the Terminal window, and press Return. This builds and opens **Koi Aquarium.app**. Afterward, you can open the app directly from Finder.

## Use the tank

- Click the water to drop food immediately. Quick repeated clicks add more pellets.
- Drag to move the aquarium. Quicker changes in direction make the water slosh more and briefly startle the fish.
- Double-click the glass above the waterline to edit, or right-click and choose **Edit Aquarium**. Drag the bottom-right grip to change width and height independently.
- In edit mode, drag algae, coral, kelp, stones, a shell, or driftwood from the tray into the water. It snaps to the floor where you drop it. Drag placed decor to move it horizontally. Right-click in edit mode to remove all decorations.
- Click Done or double-click above the waterline again to return to feeding.
- Right-click to set the count of koi, guppies, and pearl minnows independently (0–8 each) or switch the water color.
- Use the fish icon in the Mac menu bar to show, hide, or quit the aquarium.
- Counts, water color, tank position, dimensions, and decorations are saved automatically.
 
Sea Glass is mint and muted teal, Jade Lagoon is sage and deep green, and Moonwater is pale lilac and slate blue.

## If Swift reports an SDK mismatch

The build script checks the selected toolchain and Xcode installations in Applications for a compiler and macOS SDK that can load AppKit together. It does this without changing your Mac’s selected developer tools. If none work, check System Settings → General → Software Update for a Command Line Tools update, or install a matching Xcode release. Then run the same build command again.

## Send notes between two Macs

- Double-click above the waterline and choose **Send Message**. Notes can be up to 72 characters.
- On your friend's Mac, your fish appears below the glass speech bubble and bobs until they click the bubble. Queued notes appear one at a time. Both apps must be running to send and receive live. Notes wait on the relay while the recipient is offline.

### Preview on one Mac

Right-click the tank, choose **Preview a Message…**, and type a sample note. Click **Preview** to see the bubble and your chosen fish bobbing below it. Click the bubble to dismiss it. This local preview works without pairing or a relay and sends nothing.

### Pair the two copies

The ZIP includes an unhosted two-person relay. You need one Python 3.10+ host with SQLite 3.38+ and a public HTTPS domain both Macs can reach. The relay only listens on loopback. One way to expose it is to point a domain at that host and use Caddy with this Caddyfile:

```caddyfile
koi.example.com {
    reverse_proxy 127.0.0.1:8765
}
```

1. On your own machine, run `python3 relay.py keys`. Keep the two tokens separate and share the message key privately with your friend.
2. On the relay host, set the printed `KOI_TOKEN_A` and `KOI_TOKEN_B` as environment variables and run `python3 relay.py`. Keep it running with a persistent working directory or set `KOI_DATABASE` to a path on a persistent volume.
3. On each Mac, right-click the tank and choose **Pair with a Friend…**. Enter the same HTTPS relay URL and message key on both Macs. Enter token A on one and B on the other.
4. Send a test note in each direction. If a note never appears, verify both copies use the same message key and different mailbox tokens.

The app encrypts the message text and fish type with the shared key before sending. The relay can see mailbox activity and stores encrypted notes until dismissal. The Mac app saves its pairing details in local app preferences. Anyone with both mailbox tokens and the shared key can access the pair, so keep those details private.

## Keepsakes and tank life

- Right-click → **Send a hello ♥** sends a heart bubble through the existing connection.
- Click the chest on the tank floor to browse gifts and place them in your tank. **Send a gift…** sends one encrypted treasure per person every rolling seven days.
- Linked time starts when both Macs first check in to the updated relay. At 7, 30, 90, and 365 days, **Creatures & milestones** unlocks a pearl, moon coral, lantern, and crystal, respectively. The relay keeps this date across app restarts. If you already paired with an older relay, replace its `relay.py` and restart it using the same database and mailbox tokens. Earlier versions did not record link dates.
- **Automatic moonlight** follows local time.
- Use **Tank floor** to pick ivory, rose, basalt, gravel, or bare glass.
- **Creatures & milestones** adds snails, starfish, and tiny shrimp. Move them along the floor in edit mode. Click shrimp in normal mode to make them bounce.

## Add more friends

A fresh tank starts empty. Double-click, choose **Add Fish**, enter a friend's code and name, then pick their species. Each person adds the other's code. Right-click **My Friend Code…** to configure your own mailbox and copy the code to share. **Send Message** offers a checklist and **Send to all**.

The relay host sets `KOI_FRIEND_MAILBOXES` to a JSON object mapping each person's mailbox ID to a distinct random private token of at least 32 characters. Generate each token with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`. Give each person the relay's HTTPS address, their mailbox ID, and only their own token. Friend codes include a mailbox ID and public encryption key. Each Mac keeps its private encryption key in local preferences. Use the same relay for everyone in your tank. Existing two-person chest gifts and milestones still use the original **Pair with a Friend…** setup.

In edit mode, drag the chest along the floor. Right-click a decoration, creature, or friend fish to remove it individually.
