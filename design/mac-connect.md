# Mac: connect a Pixel

Status: proposed, for review (October 2026). Redesign of the Mac's pairing
sheet (`MacPairingSheet`), following `constitution.md` § Redesign before
refinement. The Pixel side is `pixel-connect.md`.

## 1. The user's question

"How do I connect this Mac to my Pixel?" On the Mac the answer is a code for
the Pixel to scan, because the Mac has no camera to scan the Pixel's code. The
user needs to know what to do on the Pixel, and to see that it worked.

They never need: a receiver name before pairing, an expiry countdown, the
words pairing, receiver or LAN.

## 2. References

| Product | What it does |
| --- | --- |
| BackupDuck iPhone (`IOSConnect.swift`) and Pixel (`pixel-connect.md`) | The same success screen everywhere: the connecting duck, "Connected to Pixel 8 Pro", one sentence. |

## 3. Structure

- **Code** on the left, in a white quiet zone only while a code is shown.
- **Three steps** on the right, using the Pixel's own words: open BackupDuck
  and tap Connect a Device (also in Settings › Connected Devices); tap Connect a
  Mac Instead, then Scan; point the Pixel's camera at the code.
- One note: it connects by itself; only let your own devices scan the code.
- **States:** getting ready (progress in the code area), code, connecting,
  connected (duck, "Connected to Pixel 8 Pro", Done), could not get ready or
  expired (the cause in the code area, Try Again).
- The session itself is unchanged (`DesktopPairingModel`): the Mac exports an
  invite, polls for the Pixel's pairing, and verifies it before showing
  success.

## 4. State (October 19, 2026)

Built behind the design switch; the Mac catalog's `connect.mac` and
`connect.mac-failed` scenarios show the code, the scripted scan and success,
and the failure, in light and dark. Not covered: a real Pixel scanning the
code, and the Mac's first run (none yet).
