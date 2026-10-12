# MineCome engineering rules

Keep native game access behind an exact executable/distribution compatibility check. KCSE loader hooks also require the correct address library; a plugin guard cannot protect an incompatible loader.

Never invent engine methods or offsets. Cite inspected upstream code for every hook. Keep transport independent of game APIs and perform engine/Minecraft calls on their respective game threads.

Test protocol framing, malformed data, reconnect/disconnect, and coordinate transforms. Distinguish source implemented, compiled, standalone verified, and live-game verified in docs/PROGRESS.md.

Keep game assets, credentials, downloaded SDKs, runtimes and saves out of Git. No modifications to original executables. Back up saves before deployment. Use a separate Minecraft instance and offline single-player testing.

Do not claim a placeholder cube or mock peer demonstrates Minecraft rendering inside KCD2. The first visual milestone requires actual Minecraft-generated content and a live KCD2 frame.
