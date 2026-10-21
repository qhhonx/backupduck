# Apple backup notifications

Notifications answer a current problem or the end of the earlier-photo import.
They use the system template, never filenames, account identifiers or cloud
claims. The shared host projection is `BackupNotifier`; Rust remains the owner
of preparation, receipt and receiver gallery observations.

## Events and destinations

| Event | Evidence | Opens |
| --- | --- | --- |
| Pixel unreachable for a day | The host observes an unreachable state at least 24 hours after the first observation; recovery or queue pause resets the interval | Backup, where the current problem and recovery action are shown |
| Pixel full | The current receiver's capacity problem | Backup |
| Live Photos need a choice | The current receiver's core conversion-required count, or confirmed conversion failures among known jobs when that aggregate is unavailable | Backup hub's Needs you photo view |
| Earlier photos finished | All frozen scan members' latest exact-revision attempts have confirmed Pixel gallery publication, with no pending preparation | Backup hub's recently backed-up photo view |

Each condition announces once, rearming after it clears. A new earlier-photo
scan has its own identity. An already completed scan first encountered at launch
does not generate a retrospective notification. Failed system delivery retries
on the next observation. Memory persists across process restarts and belongs to
the selected receiver. Changing or removing the pairing withdraws old reminders;
tapping an old receiver's notification never redirects it to the new one.

The 24-hour reminder is evaluated when the host runs and observes the problem
again. It is not an exact timer: iOS may suspend the process, and a previously
scheduled local notification cannot recheck receiver connectivity before it
fires. Do not schedule an unverified future problem or claim continuous offline
observation while the host was asleep.

## Permission and lifecycle

First run explains notifications after the first confirmed saved photo and asks
only when the user chooses Allow. Auto Backup settings provide the same explicit
permission entry after skipping first run on iPhone. Subsequent
changes use system notification settings. Passive observation never raises a
system permission prompt. Denied permission leaves backup unaffected.

Configure the notification delegate at launch, before cold-start responses can
arrive. The model subscription starts on normal and background launches, uses
bounded update frequency and evaluates the initial state. Notification taps
restore the relevant destination without changing backup intent or scope.
Foreground updates remain in the task UI; no extra in-app banner is requested.

## Completion semantics

`history_status.published` counts confirmed gallery publications for the frozen
source/revision members, using each member's latest attempt and receiver. Missing
publication evidence remains unknown. `scanned` and `pending == 0` prove only
that enumeration and preparation have drained. Both the earlier-photo card and
its notification require the publication count to match the member count before
saying the photos are saved.

Validation must distinguish pure event/restart tests, native builds, synthetic
catalog review, system notification delivery/taps and physical-device behavior.
