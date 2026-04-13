# Session CX-001 Plan - Coherent group message context surface

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `CX-001` with the existing shared overlay model rather
  than inventing a second group-only long-press interaction.
- Reuse `MessageContextOverlay` from 1:1 conversation for group messages.
- Keep unsupported edit/delete actions hidden while preserving the selected
  message preview, reaction affordances when available, and local-only actions.
- This seam is also allowed to preserve later row-owned work for `CX-002` to
  `CX-005`, but `CX-001` closes only when the coherent overlay itself is proven.

### closure bar

- Long-pressing a supported group row opens one overlay, not only the detached
  `ReactionBar`.
- The selected message stays visually identifiable inside the overlay.
- The overlay dismisses cleanly without side effects.
- Required direct tests pass.

### source of truth

- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
