# Squad Delta systems

Actual movement, tool, client lifecycle and partial gamemode/player-component source, plus earlier extracted networking and server lifecycle systems.

- `MovementController.lua`: SquadDelta's full `CharacterController.lua`, including original input/physics, ground and air acceleration, stair contact, sliding, ladders, vaulting, landing effects and PlayerData/Crouch replication wiring. Not a simplified replacement.
- `src/replicatedfirst/Client/Modules/Loader.lua` and `BaseController.lua`: actual dependency-aware client startup, diagnostics, failure policy and lifecycle source. Both match SquadDelta source, apart from outer blank lines. Logger and Maid remain external dependencies; controller inventories and production startup policies are not copied.
- `src/ServerStorage/ItemServers`, client `VMControllers`/`ToolController`, and server `Classes/Item`/`ItemService`: actual tool client/server pipeline. AI firing/hearing hooks and authored material/icon content are omitted. FastCastRedux, PartCache, Framework, weapon data, assets and remotes remain external dependencies.
- `src/server/GameTypes/FPS`: current mode registry, compositional servers, shared flow, mode components and config wiring. Authored config/loadout tables are omitted. Some round/economy and legacy files are held pending the owner's mechanic-sensitivity decision. The original duplicate `.lua`/`.luau` files are retained; `Common/ModePlayerUtils.luau` has an original syntax error at line 23.
- `src/server/Classes/PlayerLike`: shared mount/unmount/binding infrastructure and neutral movement/status/team plus FPS component aliases/loadout lifecycle. Mechanic-heavy player classes/components remain pending.
- `EventService.lua` / `RateLimiter.lua`: the earlier dependency-injected networking extraction.
- `ModuleLoader.lua`: generic server lifecycle loader.

The movement controller requires the original Roblox hierarchy: `ReplicatedFirst.Client.Modules.BaseController` (which uses `ReplicatedStorage.Modules.Framework.Maid`), a local character/camera, `workspace.Ignore`, and its replicated PlayerData and Crouch remote setup. BaseController source is now bundled at its original path; Maid, Logger and game assets are not bundled. This is source for inspection, not a standalone runnable controller.

```sh
luau run.lua
luau loader-tests.lua
```

12 engine-free checks cover the extracted networking and loader lifecycle only. They do not test the full movement controller or added actual client loader. Live Roblox movement, collision, replication and actual ModuleScript discovery have not been verified here.

The client loader reports timeouts but does not cancel the spawned callback, so late side effects remain possible. Dependency no-progress handling is not a full graph-cycle diagnosis. Real ModuleScript startup/teardown behavior has not been exercised here. See `additional-source-manifest.json` for source hashes.

Private work in progress. Public release is not planned until the owner has vetted the systems and used them in-game. See [source and extraction boundaries](EXTRACTION.md). No license is granted.

The new tool/mode/player source has not been run in Roblox. Config omissions, missing dependencies and the preserved source syntax issue make this a partial inspection extraction, not an import-ready game. Matchmaking implementations and third-party libraries are not bundled. See `PIPELINE-SCHEMAS.md` and `component-source-manifest.json` for this pass.
