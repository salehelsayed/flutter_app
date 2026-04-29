# Session 05 - Group Surfaces Plan

## Scope
- Group list shell, loading rows, empty state, pending invite card, and group row content.
- Group info shell, member rows, mute/status/action cards, and dissolved state copy.
- Group conversation header, empty/loading/read-only/backlog states, and highlighted row shell.

## Closure Bar
- Persistent group text/icons use `BackgroundReadableColors` instead of fixed pale foregrounds.
- `AmbientBackground` descendants resolve readable roles from the inner theme scope.
- Representative Daylight widget tests cover the list/card/info/conversation visible states.
- Focused group presentation tests pass.

## Out Of Scope
- Full attachment source sheets, media viewer chrome, emoji picker, and modal overlay styling remain Session 07 transients.
