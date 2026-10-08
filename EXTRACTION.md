# Source and extraction boundaries

## Movement

`MovementController.lua` is the actual source from `SquadDelta/src/replicatedfirst/Client/Controllers/CharacterController.lua`, read October 6, 2026. The algorithms, original movement constants, ground probes, physics, input bindings, slides, ladders, vaults and integration paths are preserved. Only a final blank line was trimmed by the editor; no movement logic was rewritten or omitted.

The owner explicitly requested the actual controller rather than a simplified sample, then confirmed keeping the `PlayerData` CanMove/Speed/Jump wiring and Crouch remote hookup. These are integration contracts, not copied player records. No embedded credentials, private player records, economy logic or AI/learning/strategy/dialogue implementation was found in this file.

The original `BaseController` is now included at `src/replicatedfirst/Client/Modules/BaseController.lua`; its Maid dependency remains required and is not bundled. The original Roblox hierarchy, character/camera, ground geometry, `workspace.Ignore`, PlayerData replication and Crouch endpoint must exist. The unused SavedData reference and original global movement hooks are preserved. This repository does not provide the complete game or claim the controller can run by itself.

The previous educational movement core, its adapter and its eight mock tests have been removed from the current tree because they no longer describe this controller. Their prior commits remain in history. No test result from that simplified core is attributed to the actual controller.

## Networking

Kept: token-bucket and sliding-window algorithms; per-player/global scopes; remote creation/class checks; guards, validation, middleware and protected handlers. Per-instance construction and explicit dependencies replace Framework/Logger and player globals. Default guards deny requests; the caller provides rate limits and player cleanup.

Production manifests, remote names, thresholds, player/game rules, inventory/economy data and credentials were intentionally excluded from this separate networking extraction at the owner's request. Test endpoints and numeric values are synthetic. The movement wiring approval does not change this networking boundary.

## Lifecycle and validation

The generic server loader dispatches optional Init/Start/Stop/Destroy callbacks. Production bootstrap order and game services are omitted. Four lifecycle tests do not exercise real ModuleScript discovery or require behavior and do not guarantee dependency ordering. Eight networking tests use mocks. Neither suite covers the full movement source.

No live-server, collision, replication, remote serialization or anti-cheat claim is made. No third-party libraries from the full game are bundled. The repository remains private while the owner vets systems in-game. No license is granted.

## Future release gate

Before any public release, audit the complete history of this extraction repository for excluded content, stale drafts and accidental commits. Removing a current file does not remove it from history. Report any recoverable excluded content and review a clean-history or recreated-repository plan with the owner before release. This repository was created separately; the original SquadDelta commit history was not imported.

## Actual client lifecycle source (October 6, 2026)

The owner selected the dependency-aware client loader, not the Hitori generator or party/matchmaking system. Loader.lua (941 source lines) and BaseController.lua retain the original module hierarchy and code without substantive changes. Production controller inventories, startup policy instances and game services were not copied. Logger and Maid remain required at their original paths and are not bundled; no third-party source was copied for those dependencies. See additional-source-manifest.json.

The actual loader resolves dependencies, handles required/optional failures, records startup phase durations/stalls and supports disable/stop/destroy. A timeout returns failure without canceling the spawned callback: late mutations remain possible. No-progress dependency handling reports unresolved dependencies rather than proving a particular graph cycle. The earlier four server-loader mock tests do not test this source; neither runtime Roblox module discovery nor live client startup was verified. No synthetic implementation or test result is substituted for the original code.

Private/no-license and owner-reviewed full-history release gating remain unchanged.
