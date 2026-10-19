# Pixel: connect a device

Status: proposed, for review (October 2026). Redesign of how the Pixel
connects an iPhone or Mac and lists the devices that send to it, following
`constitution.md` § Redesign before refinement. It replaces the legacy pairing
sheets (`PairingUI`), the legacy device list (`DevicePanels.showPeers`) and the
first-run code step's own copy of the code screen.

## 1. The user's question

On the Pixel the user wants one thing: **"Show the code my iPhone should scan,
and tell me when it worked."** A Mac works the other way round: the Mac shows
the code and the Pixel scans it. Later, rarely: **"Which devices send photos
here, and can I stop one?"**

They never need: a choice sheet before the code, a refresh button for the code,
receiver start-up states, certificate or token words, network addresses, or
the words pairing, receiver or credential.

## 2. References

| Product | What it does for the same question |
| --- | --- |
| BackupDuck iPhone (`IOSConnect.swift`) | One scanner shared by first run, the hub and the device page; the same success screen ("Connected to Pixel 8 Pro") everywhere. |

The Pixel shows a code for the other device to scan, as a desktop app does
when a phone links it, and lists connected devices with their last activity.

What BackupDuck takes:

- **One connect screen** for first run, the hub's "Connect a device" and the
  device page. The code is the subject; two short steps say what to do on the
  iPhone; it continues by itself when a new device appears.
- **Getting ready is a state of the code area**, not a sheet of its own. If the
  code cannot be made ready, the screen says why and offers Try again.
- **The Mac direction is one quiet link** on the code screen, leading to an
  explanation, then the camera.
- **The device list is a settings page**: a sentence, one Connect button, then
  the devices that send here and the ones the user stopped.

## 3. Structure

**Connect screen** (full screen; FLAG_SECURE while a code is shown):

| State | What it shows | Actions |
| --- | --- | --- |
| Getting ready | Title and steps; a progress indicator in place of the code | Connect a Mac instead |
| Code | The code (black on white in every theme), "Connects by itself once scanned", "Only let your own devices scan this code" | Connect a Mac instead |
| Could not get ready | The cause (the receive problem when known, otherwise Wi‑Fi); the code returns by itself once receiving is ready | Try again |
| Connected | The connecting duck, "Connected to Lin's iPhone", one sentence | Done (first run: Next) |

Opening the screen turns receiving on if it was off, as the legacy flow did.
Receiving stays on afterwards.

**Mac** (same screen, other direction): title, one sentence on where the Mac
shows its code, one sentence on the camera, then **Scan**. Scanning, then
"Connecting to your Mac…", then Connected ("Your Mac is connected"). An
unreadable code or a failed connection says so and offers Scan again; camera
access off offers Open Settings. "Connect an iPhone instead" returns to the
code.

**Connected devices** (settings page):

1. One sentence: another iPhone or Mac connects by scanning this Pixel's code.
2. **Connect a device** (opens the connect screen).
3. **Sending to this Pixel**: each device with its kind (phone or computer
   mark), name and "Last connected today 10:42".
4. **Stopped**: devices whose new photos are not received.
5. A device opens a sheet: name, kind and last connection, then one action:
   Stop receiving from this device, or Receive from it again. Photos already
   received stay; the change is undone with the opposite action.

No device yet: "No devices yet" and the Connect button.

## 4. Copy

The zh-Hans copy lives in the strings files (`connect_*`).

| Place | en |
| --- | --- |
| Code title | Scan this code with your iPhone |
| Step 1 | Open BackupDuck on your iPhone |
| Step 2 | Point it at this code when it asks |
| Under the code | Connects by itself once scanned |
| Note | Only let your own devices scan this code. |
| Mac link | Connect a Mac instead |
| Mac title | Scan your Mac's code |
| Connected | Connected to %@ |
| Devices sentence | Another iPhone or Mac connects by scanning this Pixel's code. |
| Last connected | Last connected %@ |
| Stop | Stop receiving from this device |

The zh-Hans word for the code follows the iPhone strings
(`connect_code_unreadable`); `copy-glossary.zh.md` still lists the older
pairing word and should follow.

## 5. Decisions

- **A new device is the success signal.** The core records a device the same
  way when it pairs and when it sends, so the Pixel confirms a device it has
  not seen before. A known device that reconnects is confirmed on the iPhone
  only; the Pixel's screen keeps waiting until closed. Confirming reconnects
  needs a pairing event from the core.
- **Stopping is not removing.** The core can stop receiving from a device and
  resume it; it cannot forget one. The list never offers Remove.
- **The Mac's name is unknown at connect time.** Mac pairing returns no name,
  so the success screen says "Your Mac is connected"; the Mac appears in the
  list once it sends.
- **No network address** in the device sheet; it belongs in diagnostics.
- **The code box turns white only with the code.** While getting ready it
  uses the surface color, so dark mode has no white flash.
- **The screen survives recreation.** A theme change or rotation reopens the
  connect screen (in the same direction) or the device page.

## 6. Open

- Where the redesigned Mac shows its code (the Mac has no redesigned first run
  yet). The Mac sentence is checked against it before the copy ships.
- Whether the device page becomes the Settings identity header's target
  (`navigation.md` § D3).
