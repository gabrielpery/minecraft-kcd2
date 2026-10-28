# MineCome engineering rules

Keep native game access behind an exact executable/distribution compatibility check. KCSE loader hooks also require the correct address library; a plugin guard cannot protect an incompatible loader.

Never invent engine methods or offsets. Cite inspected upstream code for every hook. Keep transport independent of game APIs and perform engine/Minecraft calls on their respective game threads.

Test protocol framing, malformed data, reconnect/disconnect, and coordinate transforms. Distinguish source implemented, compiled, standalone verified, and live-game verified in docs/PROGRESS.md.

Keep game assets, credentials, downloaded SDKs, runtimes and saves out of Git. No modifications to original executables. Back up saves before deployment. Use a separate Minecraft instance and offline single-player testing.

Do not claim a placeholder cube or mock peer demonstrates Minecraft rendering inside KCD2. The first visual milestone requires actual Minecraft-generated content and a live KCD2 frame.

## Delivery and testing workflow

The user prioritizes playable progress per unit of time/usage and minimal manual testing.

- Deliver integrated, user-visible capabilities. Do not count standalone policies, new diagnostics or test counts as completed gameplay features.
- Preserve verified behavior and batch related changes into a feature milestone. Defer non-blocking polish instead of repeatedly stopping feature work for another small live comparison.
- Reuse existing actual-Minecraft fixtures and coupled-game checks. Run focused checks once per relevant change; broaden or repeat only for a new failure, changed code or unresolved concern.
- Ask for human testing only where foreground input, visible composition or subjective feel cannot be established automatically. Combine needed checks into one acceptance session after automated checks pass; do not repeat already-proven inventory/face/control sequences without a relevant change.
- Prefer a user-started, repeatable session to a countdown race. Never start a countdown while asking whether the user is available.
- Keep investigations tied to a concrete blocker and a next decision. Record a non-blocking issue and continue the milestone rather than extending an open-ended tuning loop.
- Use delegation only for a short, independent implementation or review that saves work. Avoid overlapping research and repeated broad audits.
- Keep status and handoffs concise: working capability, actual blocker, next implementation, and the evidence needed to resume. Do not reread the full historical log by default.
