# Pipeline boundaries and required structure

Partial extraction, October 6, 2026. Tool and shared component infrastructure are present; economy/mechanic-sensitive files remain pending an owner decision. Earlier extraction manifests are unchanged.

## Mode config shapes

Config modules retain `ModeId`, `Server.Components` entries (`module`, `key`), endpoint/control component selection, and original empty initial-state/network wiring where present. Authored values are omitted, including phase durations, team roles/counters, score weights, map catalogs/spawn mappings, weapon/loadout grants, objective messages/actions, revive rules and mode-specific rules. Each config lists its omitted top-level keys. Supply vetted values before running.

`Server.Components` is wiring, not an authored weapon or map catalog. References to held files are intentional and not proof those files are bundled.

## Tool dependencies

Requires Roblox services, Framework, original replicated folders/remotes, weapon/item configuration, rigs/viewmodels, effects/sounds and assets. GunServer refers to FastCastRedux, Table and PartCache under `ReplicatedStorage.Modules.GunServer`; these third-party dependencies are not copied or attributed to the owner. Authored material effects mapping and fallback icon ID are omitted. AI hearing, aiming/fire solver handlers and bot trait/policy wiring are cut, preserving named methods where applicable.

## Component dependencies

PlayerBase mounts registered components and binds their public methods. Registry discovery retains the original module tree assumptions. Gameplay data, class bases and services remain external. Missing mechanic components mean registry discovery and full player initialization are not guaranteed to succeed.

## Known source issue

`Common/ModePlayerUtils.luau` line 23 contains `itemOrTool:IsA and ...`, a parse error already present in the original. The `.lua` version parses. Duplicates are retained at their original paths, not treated as interchangeable or silently repaired.

## Verification limits

Files are compared against live originals and committed readbacks. Named stubs/content omissions are deliberate differences, not game fixes. Syntax checks are not Roblox execution, dependency closure, security review, performance testing or gameplay validation. Matchmaking implementation remains excluded; external match-instance interfaces stay visible. Legacy implementations remain pending in the sensitive slice and are not yet committed in this pass. No license is granted; repository remains private.
