-- Holy Hand Grenade for Cyberpunk 2077 v1.0.0 - fan-made, non-commercial. See README / CREDITS.
-- Holy Hand Grenade for Cyberpunk 2077: the Cyber Engine Tweaks part.
--
-- Items.HolyHandGrenade (r6/tweaks/holygrenade.yaml) is a throwing knife with the grenade's look
-- (HolyHandGrenade.archive: the knife's grip with the orb in place of the blade). Given a few seconds after a load (or
-- with the hotkey). Thrown like a knife (aim, then attack): the knife's throw gives the animation and the moment; the
-- knife projectile itself is made invisible and our grenade leaves the hand with its own ballistics (bounces, rolls -
-- see "the thrown grenade"). FUSE s after the throw it goes off: the game's explosion attack HolyGrenade.Explosion (the
-- frag grenade's effect made strong) at the spot, the frag grenade's explosion effect entity at the spot and around
-- it, and on top NPCs within KILL_R m die, those within R m take falling damage, all go ragdoll and fly outwards,
-- vehicles the blast hits within CAR_R m explode and are thrown, one after another. The thrown-knife cooldown pool is
-- set full RECOVER s after the throw (much shorter than a knife's). The "Hallelujah" plays through Audioware if it is
-- installed. Log: log.txt next to this file.

local ITEM = "Items.HolyHandGrenade"
local GRENADE_MESH = "holygrenade\\holygrenade.mesh"
local FUSE = 3.0                       -- s from the throw (Worms' default; 'count to three')
local CHOIR_LEN = 2.0                  -- s: the choir clip
local sound_err = false
-- run 8 (owner: 'the blast 20-30 % stronger'): everything x1.25 - 15 / 7 / 10 m -> 19 / 9 / 12.5 m, the throws and
-- the ring of extra blasts too
local R, KILL_R, CAR_R = 19.0, 9.0, 12.5
local BLAST_POWER = 1.25
local NPC_IMPULSE = 75 * 0.07          -- gravgun-cp's calibration: ragdoll impulse units per 1 m/s
local RECOVER = 1.0
local EXTRA_BLASTS = 4                 -- more explosion effects around the spot, for the size of it (effects only - run 10)
-- run 10 (owner: 'into many cars - the game hangs on the blast'; log: our car search found 0 cars, the game attack, then
-- 5 of them, destroyed ~5 cars in one frame, LTBF detaching their parts 2-3 times, and every log stopped there): one
-- game attack, its vehicle damage the frag grenade's own (no one-frame wreck); the cars it hits (their hit events - the
-- targeting search does not return cars) are set off and thrown by us one by one, CAR_STEP s apart, at most CAR_MAX
local CAR_STEP, CAR_MAX, CAR_WINDOW = 0.25, 6, 0.6

local log_lines, hud = {}, {text = nil, t = 0}
local live = {}                        -- thrown grenades: {n, pos, vel, q, t, item, fid, rest, bounces, ...}
local gift = {player = nil, t = 0, tick = 0, done = false, last = -1, stable = 0}
local item_ready = false
local UP

local function Log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    line = ok and line or tostring(fmt)
    print("[holygrenade] " .. line)
    log_lines[#log_lines + 1] = os.date("%H:%M:%S ") .. line
    if #log_lines > 400 then table.remove(log_lines, 1) end
    local f = io.open("log.txt", "w")
    if f then f:write(table.concat(log_lines, "\n"), "\n"); f:close() end
end

local function Hud(text, t) hud.text, hud.t = text, t or 2 end

local function V4(x, y, z) return Vector4.new(x, y, z, 1.0) end
local function add(a, b) return V4(a.x + b.x, a.y + b.y, a.z + b.z) end
local function sub(a, b) return V4(a.x - b.x, a.y - b.y, a.z - b.z) end
local function mul(a, s) return V4(a.x * s, a.y * s, a.z * s) end
local function len(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function norm(a) local l = len(a); if l < 1e-6 then return nil end; return mul(a, 1 / l) end
local function fmt(v) return v and string.format("(%.2f %.2f %.2f)", v.x, v.y, v.z) or "nil" end

local function IdName(id)
    local ok, s = pcall(function() return TDBID.ToStringDEBUG(id) end)
    return ok and s or nil
end

local function KeyOf(e) local k = nil; pcall(function() k = tostring(e:GetEntityID().hash) end); return k end

-- the item V holds, if it is the Holy Hand Grenade
local function HeldGrenade(player)
    local item = nil
    pcall(function()
        local it = Game.GetTransactionSystem():GetItemInSlot(player, TweakDBID.new("AttachmentSlots.WeaponRight"))
        if it and IdName(it:GetItemID().id) == ITEM then item = it:GetItemID() end
    end)
    return item
end

-- the gift ---------------------------------------------------------------------------------------------------------
local function HasItem(player)
    local ok, has = pcall(function()
        local _, list = Game.GetTransactionSystem():GetItemList(player)
        for _, it in ipairs(list or {}) do
            if IdName(it:GetID().id) == ITEM then return true end
        end
        return false
    end)
    return ok and has
end

local function Give()
    local player = Game.GetPlayer()
    if not player or not item_ready then Log("give: no player or no item record"); return end
    if HasItem(player) then Hud("Holy Hand Grenade: already in the inventory"); Log("give: already there"); return end
    local ok, err = pcall(function() Game.AddToInventory(ITEM, 1) end)
    Log("grenade given: %s", ok and "yes" or tostring(err))
    Hud(ok and "Holy Hand Grenade added to the inventory" or "could not add the Holy Hand Grenade", 3)
end

local function GiftTick(dt)
    local player = Game.GetPlayer()
    if not player then return end
    local pid = KeyOf(player)
    if pid ~= gift.player then gift.player, gift.t, gift.tick, gift.done, gift.last, gift.stable = pid, 0, 0, false, -1, 0 end
    if gift.done then return end
    gift.t, gift.tick = gift.t + dt, gift.tick + dt
    if gift.tick < 1 then return end
    gift.tick = 0
    local n = -1
    pcall(function() local _, l = Game.GetTransactionSystem():GetItemList(player); n = #(l or {}) end)
    if n == gift.last and n > 0 then gift.stable = gift.stable + 1 else gift.stable = 0 end
    gift.last = n
    if gift.t > 6 and gift.stable >= 3 then
        gift.done = true
        if item_ready and not HasItem(player) then Give()
        else Log("gift: %s (%d items)", item_ready and "V already has the grenade" or "no item record", n) end
    end
end

-- the thrown grenade ------------------------------------------------------------------------------------------------
-- Run 6 (owner: 'it still hangs in the air; it does not always go off on contact; can it be swapped at the throw for a
-- grenade's physics?'; run 6 log: the knife projectile's OnTick comes only for its first frames - its position froze,
-- the "rest" was false). The knife throw stays only for its animation and its moment: at the projectile's OnShoot /
-- OnProjectileInitialize while V holds the Holy Hand Grenade the projectile's knife mesh goes off (on again later -
-- it is pooled) and our own grenade leaves the hand: a helper entity (holygrenade\fx\empty.ent + the grenade part of
-- the mesh) moved every frame by our own ballistics - gravity, rays against the world (Static, Terrain, Dynamic,
-- Vehicle) with a bounce (BOUNCE of the normal speed, FRICTION of the tangential kept), NPCs bounce it back, it rolls
-- and stops; spinning with its speed. The fuse runs FUSE s from the throw (Worms): it goes off wherever it is.
local FX_ENT = "holygrenade\\fx\\empty_go.ent"   -- run 9: a game object (the physics pulse needs one at the spot)
local HELD_WINDOW = 1.5
local THROW_SPEED, THROW_UP = 24.0, 3.5         -- m/s along the aim, m/s up (run 7, owner: "a bit more push": 17 / 2.5 -> 24 / 3.5)
local BALL_R, GRAVITY, BOUNCE, FRICTION = 0.06, 9.81, 0.35, 0.7
local STOP_SPEED = 0.8
local GROUPS = {"Static", "Terrain", "Dynamic", "Vehicle"}
local ORB_IN_MESH = {0, 0.007, 0.06}            -- the orb's centre in the mesh (blend/build_grenade_mesh.py ORB_AT)
local held = {item = nil, t = 99}               -- the grenade item while in hands, and the time since
local on_assemble = {}                          -- entity key -> function(entity), once
local fired = {}                                -- projectile events seen (logged once each)
local hidden = {}                               -- knife projectiles with their mesh off: key -> {comp, t}
local last_throw = 99

local function cross(a, b) return V4(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

local function GrenadeMesh()
    local c = entMeshComponent.new()
    c.name = "holygrenade_mesh"
    c.mesh = ResRef.FromString(GRENADE_MESH)
    c.meshAppearance = "default"
    c.visualScale = Vector3.new(1, 1, 1)
    pcall(function() c.chunkMask = 1 end)        -- chunk 0 only: the grenade (chunk 1 is the knife grip)
    c:SetLocalPosition(Vector4.new(-ORB_IN_MESH[1], -ORB_IN_MESH[2], -ORB_IN_MESH[3], 0))   -- the orb at the origin
    return c
end

local function SpawnFollower(g, pos)
    local ok, err = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = FX_ENT
        spec.position = pos
        spec.orientation = Quaternion.new(0, 0, 0, 1)
        spec.attached = true
        g.fid = Game.GetStaticEntitySystem():SpawnEntity(spec)
    end)
    if ok and g.fid then
        on_assemble[tostring(g.fid.hash)] = function(e)
            local okc, errc = pcall(function() e:AddComponent(GrenadeMesh()) end)
            Log("grenade %d: model entity assembled, mesh %s", g.n, okc and "added" or ("failed: " .. tostring(errc)))
        end
    else
        Log("grenade %d: model entity failed: %s", g.n, tostring(err))
    end
end

-- quaternion of a rotation by angle a about the unit axis u
local function QAxis(u, a)
    local s = math.sin(a / 2)
    return Quaternion.new(u.x * s, u.y * s, u.z * s, math.cos(a / 2))
end

local function QMul(a, b)
    return Quaternion.new(a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j,
                          a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
                          a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r,
                          a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k)
end

local function Follow(g)
    if not g.fid then return end
    local fe = nil
    pcall(function() fe = Game.GetStaticEntitySystem():GetEntity(g.fid) end)
    if not fe then return end
    local ok, err = pcall(function()
        local tr = fe:GetWorldTransform()
        tr:SetPosition(g.pos)
        tr:SetOrientation(g.q)
        fe:SetWorldTransform(tr)
    end)
    if not ok and not g.follow_err then g.follow_err = true; Log("grenade %d: follow failed: %s", g.n, tostring(err)) end
end

local function Release(g)
    if g.fid then pcall(function() Game.GetStaticEntitySystem():DespawnEntity(g.fid) end); g.fid = nil end
end

local function Ray(a, b)
    local best = nil
    for _, group in ipairs(GROUPS) do
        local ok, hit, res = pcall(function()
            return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(a, b, group, false, false)
        end)
        if ok and hit and res then
            local p = ToVector4(res.position)
            local d = len(sub(p, a))
            if not best or d < best.d then
                local n = nil
                pcall(function() n = ToVector4(res.normal) end)
                if n and len(n) < 0.5 then n = nil end
                best = {p = p, d = d, n = n and norm(n), group = group}
            end
        end
    end
    return best
end

local npc_cache = {t = 99, list = {}}
local grenade_n = 0

local function TakeProjectile(self, why)
    if not fired[why] then fired[why] = true; Log("projectile event %s fired", why) end
    if why ~= "OnShoot" and why ~= "OnProjectileInitialize" then return end
    if not held.item or held.t > HELD_WINDOW then return end
    local key = KeyOf(self)
    -- the knife that the game throws: invisible (its mesh back on a few seconds later - the projectile is pooled)
    pcall(function()
        local knife = self:FindComponentByName(CName.new("mesh"))
        if knife then knife:Toggle(false); hidden[key or "?"] = {comp = knife, t = 0} end
    end)
    if last_throw < 0.4 then return end   -- one throw gives OnProjectileInitialize and OnShoot (and 2 projectiles)
    last_throw = 0
    local player = Game.GetPlayer()
    if not player then return end
    local from, fwd = nil, nil
    pcall(function()
        local f, d = Game.GetTargetingSystem():GetCrosshairData(player)
        from, fwd = ToVector4(f), norm(ToVector4(d))
    end)
    if not from or not fwd then
        from = add(ToVector4(player:GetWorldPosition()), mul(UP, 1.6))
        fwd = norm(ToVector4(player:GetWorldForward())) or V4(0, 1, 0)
    end
    local right = norm(cross(fwd, UP)) or V4(1, 0, 0)
    local start = add(add(add(from, mul(fwd, 0.45)), mul(right, 0.15)), mul(UP, -0.15))
    -- do not start inside a wall right in front of V
    local h = Ray(from, start)
    if h then start = add(h.p, mul(norm(sub(from, start)) or fwd, BALL_R * 2)) end
    grenade_n = grenade_n + 1
    local g = {n = grenade_n, pos = start, vel = add(mul(fwd, THROW_SPEED), mul(UP, THROW_UP)), q = Quaternion.new(0, 0, 0, 1),
               t = 0, item = held.item, bounces = 0, rest = false, hit_npc = {}}
    live[#live + 1] = g
    SpawnFollower(g, start)
    Log("thrown: grenade %d at %s (event %s), velocity %s", g.n, fmt(start), why, fmt(g.vel))
    Hud("One... two... five! Three, sir! THREE!", FUSE - 1.0)
end

local function HookProjectiles()
    local res = {}
    for _, ev in ipairs({"OnShoot", "OnProjectileInitialize", "OnCollision"}) do
        local ok = pcall(function()
            Observe("MeleeProjectile", ev, function(self)
                local okT, errT = pcall(TakeProjectile, self, ev)
                if not okT then Log("take (%s): %s", ev, tostring(errT)) end
            end)
        end)
        res[#res + 1] = ev .. (ok and "" or " (failed)")
    end
    Log("projectile hooks: %s", table.concat(res, ", "))
end

-- one physics step of a grenade
local function Step(g, h)
    if g.rest then return end
    g.vel = add(g.vel, V4(0, 0, -GRAVITY * h))
    local np = add(g.pos, mul(g.vel, h))
    local dir = norm(sub(np, g.pos))
    local hit = dir and Ray(g.pos, add(np, mul(dir, BALL_R))) or nil
    if hit then
        local n = hit.n or mul(dir, -1)
        if dot(n, dir) > 0 then n = mul(n, -1) end
        g.pos = add(hit.p, mul(n, BALL_R))
        local vn = dot(g.vel, n)
        local vt = sub(g.vel, mul(n, vn))
        g.vel = add(mul(vt, FRICTION), mul(n, -vn * BOUNCE))
        g.bounces = g.bounces + 1
        if g.bounces <= 4 then Log("grenade %d bounce on %s at %s, speed now %.1f", g.n, hit.group, fmt(g.pos), len(g.vel)) end
        if len(g.vel) < STOP_SPEED and n.z > 0.6 then
            g.rest = true
            g.vel = V4(0, 0, 0)
            Log("grenade %d at rest at %s after %.2f s", g.n, fmt(g.pos), g.t)
        end
    else
        g.pos = np
    end
end

-- the explosion ----------------------------------------------------------------------------------------------------
local function Hips(npc)
    local p = nil
    pcall(function()
        local ok, wt = npc:GetSlotComponent():GetSlotTransform(CName.new("Hips"))
        if ok and wt then p = WorldPosition.ToVector4(wt.Position) end
    end)
    return p
end

-- never V (portal-cp's crash: the NPC search can return the player)
local function IsNPC(e, player_key)
    local k = KeyOf(e)
    if not k or k == player_key then return false end
    local pl = false
    pcall(function() pl = e:IsPlayer() end)
    if pl then return false end
    local npc = false
    pcall(function() npc = e:IsA("NPCPuppet") end)
    return npc
end

local function Around(player, pos, radius, query)
    local out = {}
    local ok, err = pcall(function()
        local q = Game[query]()
        q.maxDistance = math.min(len(sub(pos, ToVector4(player:GetWorldPosition()))) + radius + 2, 200)
        q.testedSet = TargetingSet.Complete
        local _, parts = Game.GetTargetingSystem():GetTargetParts(player, q)
        for _, part in ipairs(parts or {}) do
            local e = nil
            pcall(function() e = TS_TargetPartInfo.GetComponent(part):GetEntity() end)
            local k = e and KeyOf(e)
            if k then out[k] = e end
        end
    end)
    if not ok then Log("search %s failed: %s", query, tostring(err)) end
    return out
end

-- run 4 log: "PrepareGameEffectAttack parameter 2 must be handle:gameObject" with 5 arguments. Its signature (from
-- final.redscripts): (GameInstance, GameObject instigator, GameObject source, TweakDBID, Vector4, array<SHitFlag>,
-- GameObject target, Float tickRate) - now with all eight. If that fails: CombatGadgetHelper.SpawnAttack(owner, radius,
-- Attack_Record, instigator) and SpawnPhysicalImpulse(owner, radius) - the game's explosive devices use them - with the
-- projectile as the owner while it is still at the spot.
local BLAST_FX = "base\\fx\\weapons\\explosives\\frag_grenade\\w_explosion_001_frag_grenade_01.ent"
local blast_way = nil                  -- what worked last time (logged once)
local fx_ids = {}

local function GameBlast(player, pos, owner)
    local id = TweakDBID.new("HolyGrenade.Explosion")
    local tries = {
        -- run 5 log: "requires from 3 to 7 parameter(s)" - CET fills the GameInstance itself
        {"PrepareGameEffectAttack", function()
            local attack = RPGManager.PrepareGameEffectAttack(player, player, id, pos)
            attack:StartAttack()
        end},
        {"PrepareGameEffectAttack (hit flags)", function()
            local attack = RPGManager.PrepareGameEffectAttack(player, player, id, pos, {})
            attack:StartAttack()
        end},
        {"CombatGadgetHelper.SpawnAttack", function()
            if not owner then error("no owner at the spot") end
            CombatGadgetHelper.SpawnAttack(owner, R, TweakDB:GetRecord("HolyGrenade.Explosion"), player)
            pcall(function() CombatGadgetHelper.SpawnPhysicalImpulse(owner, R) end)
        end},
    }
    local errs = {}
    for _, t in ipairs(tries) do
        local ok, err = pcall(t[2])
        if ok then
            if blast_way ~= t[1] then blast_way = t[1]; Log("explosion attack: %s works", t[1]) end
            return true, t[1]
        end
        errs[#errs + 1] = t[1] .. ": " .. tostring(err)
    end
    return false, table.concat(errs, " | ")
end

-- a vanilla explosion effect entity at the spot (plays its effect when attached; despawned after a while)
local function BlastFx(pos)
    local ok, err = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = BLAST_FX
        spec.position = pos
        spec.orientation = Quaternion.new(0, 0, 0, 1)
        spec.attached = true
        fx_ids[#fx_ids + 1] = {id = Game.GetStaticEntitySystem():SpawnEntity(spec), t = 0}
    end)
    return ok, err
end

-- the shock wave (run 9, owner: 'can it push things away? there is no blast wave - only area damage'):
--  * people: ragdoll first, the impulses PUSH_FRAMES later (a ragdoll needs a few frames before an impulse acts -
--    gravgun-cp; run 8 pushed in the same frame and the push was lost), a second smaller one a little later;
--  * vehicles: an impulse barely moves a car (gravgun-cp runs 1-4) - they fly a ballistic arc of our own (a Teleport per
--    frame, spinning), out and up, until they come down on the ground (gravgun-cp's car flight);
--  * everything physical: the game's own physics pulse of explosive devices, CombatGadgetHelper.SpawnPhysicalImpulse,
--    around our model entity - now a game object (holygrenade\fx\empty_go.ent, entSpawner's empty game object).
local PUSH_FRAMES, PUSH2_FRAMES, PUSH2_SHARE = 2, 6, 0.5
local pushes = {}                      -- {npc, vel, at, f}
local flights = {}                     -- {car, p, v, t, yaw, spin, angles}
local blasts = {}                      -- recent blasts collecting the cars they hit: {n, pos, t, cars, queue, ...}

local function GroundZ(p, above, below)
    local best = nil
    for _, group in ipairs({"Static", "Terrain"}) do
        local ok, hit, res = pcall(function()
            return Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(V4(p.x, p.y, p.z + above), V4(p.x, p.y, p.z - below), group, false, false)
        end)
        if ok and hit and res then
            local z = ToVector4(res.position).z
            if not best or z > best then best = z end
        end
    end
    return best
end

local function Teleport(obj, pos, angles)
    return pcall(function() Game.GetTeleportationFacility():Teleport(obj, pos, angles) end)
end

local function PushTick(dt)
    for i = #pushes, 1, -1 do
        local p = pushes[i]
        p.f = p.f + 1
        if p.f == PUSH_FRAMES or p.f == PUSH2_FRAMES then
            local share = (p.f == PUSH_FRAMES) and 1.0 or PUSH2_SHARE
            local at = Hips(p.npc) or p.at
            pcall(function() p.npc:QueueEvent(CreateRagdollApplyImpulseEvent(at, mul(p.vel, share * NPC_IMPULSE), 0.8)) end)
        end
        if p.f >= PUSH2_FRAMES then table.remove(pushes, i) end
    end
end

local function FlightTick(dt)
    for i = #flights, 1, -1 do
        local f = flights[i]
        f.t = f.t + dt
        f.v = add(f.v, V4(0, 0, -GRAVITY * dt))
        local nextp = add(f.p, mul(f.v, dt))
        local g = (f.v.z < 0) and GroundZ(nextp, 0.4, 0.05) or nil
        if g or f.t > 6.0 then
            local z = g or GroundZ(f.p, 2.0, 200.0)
            if z then f.p = V4(nextp.x, nextp.y, z + 0.05) end
            Teleport(f.car, f.p, EulerAngles.new(f.angles.roll, f.angles.pitch, f.angles.yaw + f.yaw))
            pcall(function() f.car:PhysicsWakeUp() end)
            pcall(function() f.car:ForceBrakesFor(6.0) end)
            table.remove(flights, i)
        else
            f.p = nextp
            f.yaw = f.yaw + f.spin * dt
            Teleport(f.car, f.p, EulerAngles.new(f.angles.roll, f.angles.pitch, f.angles.yaw + f.yaw))
        end
    end
end

local function Explode(g, pos)
    local player = Game.GetPlayer()
    if not player then return end
    local pkey = KeyOf(player)
    local ok, how = GameBlast(player, pos, nil)
    local okf, errf = BlastFx(pos)
    -- the game's physics pulse around our model entity (a game object at the spot)
    local okp, errp = false, "no model entity"
    pcall(function()
        local fe = g.fid and Game.GetStaticEntitySystem():GetEntity(g.fid)
        if fe then okp, errp = pcall(function() CombatGadgetHelper.SpawnPhysicalImpulse(fe, R) end) end
    end)
    Log("explosion at %s: game attack %s; fx entity %s; physics pulse %s", fmt(pos),
        ok and ("by " .. how) or ("failed: " .. tostring(how)), okf and "spawned" or ("failed: " .. tostring(errf)),
        okp and "ok" or ("failed: " .. tostring(errp)))
    for i = 1, EXTRA_BLASTS do
        local a = 2 * math.pi * i / EXTRA_BLASTS
        BlastFx(add(pos, V4(3.75 * math.cos(a), 3.75 * math.sin(a), 0.5)))
    end
    -- people
    local killed, hurt, thrown = 0, 0, 0
    local sps = Game.GetStatPoolsSystem()
    for _, npc in pairs(Around(player, pos, R, "TSQ_NPC;")) do
        if IsNPC(npc, pkey) then
            local at = Hips(npc)
            if not at then pcall(function() at = add(ToVector4(npc:GetWorldPosition()), mul(UP, 0.9)) end) end
            local d = at and len(sub(at, pos)) or R
            if d < R then
                if d < KILL_R then
                    pcall(function() sps:RequestSettingStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, 0, player) end)
                    pcall(function() npc:Kill(player, false, false) end)
                    killed = killed + 1
                else
                    local pct = 100 * (1 - (d - KILL_R) / (R - KILL_R))
                    pcall(function() sps:RequestChangingStatPoolValue(npc:GetEntityID(), gamedataStatPoolType.Health, -pct, player, false, true) end)
                    hurt = hurt + 1
                end
                pcall(function()
                    if ScriptedPuppet.CanRagdoll(npc) then npc:QueueEvent(CreateForceRagdollNoPowerPoseEvent("holygrenade")) end
                end)
                local dir = norm(add(sub(at, pos), V4(0, 0, 0.6))) or UP
                local speed = (6 + 18 * (1 - d / R)) * BLAST_POWER
                pushes[#pushes + 1] = {npc = npc, vel = mul(dir, speed), at = at, f = 0}
                thrown = thrown + 1
            end
        end
    end
    -- vehicles: collected from the blast's hits over CAR_WINDOW s (CarHit), then CarTick takes them one by one
    blasts[#blasts + 1] = {n = g.n, pos = pos, t = 0, cars = {}, queue = {}, hits = 0, blown = 0, flown = 0, step = 0}
    Log("explosion: %d killed, %d hurt, %d to be thrown; vehicles: from the blast's hits", killed, hurt, thrown)
    Release(g)
end

-- a car hit by a game attack right after one of our blasts and within CAR_R of it: into that blast's queue
local car_hook_fired = nil
local function CarHit(car, how)
    if #blasts == 0 then return end
    local isCar = false
    pcall(function() isCar = car:IsVehicle() end)
    if not isCar then return end
    local k = KeyOf(car)
    if not k then return end
    local cp = nil
    pcall(function() cp = ToVector4(car:GetWorldPosition()) end)
    if not cp then return end
    for _, b in ipairs(blasts) do
        b.hits = b.hits + 1
        if b.t <= CAR_WINDOW and not b.cars[k] then
            local d = len(sub(cp, b.pos))
            if d < CAR_R then
                if not car_hook_fired then car_hook_fired = how; Log("vehicle hits come through %s", how) end
                b.cars[k] = true
                b.queue[#b.queue + 1] = {car = car, d = d}
            end
        end
    end
end

local function LaunchCar(b, item, player)
    local e, d = item.car, item.d
    local cp = nil
    pcall(function() cp = ToVector4(e:GetWorldPosition()) end)
    if not cp then return end
    d = len(sub(cp, b.pos))
    if d < CAR_R * 0.7 then
        local okE, errE = pcall(function() e:GetVehicleComponent():ExplodeVehicle(player) end)
        if okE then b.blown = b.blown + 1 elseif b.blown == 0 then Log("ExplodeVehicle failed: %s", tostring(errE)) end
    end
    local k = math.max(0, 1 - d / CAR_R)
    local out = norm(V4(cp.x - b.pos.x, cp.y - b.pos.y, 0)) or V4(1, 0, 0)
    local v = add(mul(out, (5 + 9 * k) * BLAST_POWER), V4(0, 0, (5 + 7 * k) * BLAST_POWER))
    local angles = EulerAngles.new(0, 0, 0)
    pcall(function() angles = GetSingleton("Quaternion"):ToEulerAngles(e:GetWorldOrientation()) end)
    local spin = (math.random() < 0.5 and -1 or 1) * (90 + 180 * k)
    for _, f in ipairs(flights) do if f.car == e then return end end
    flights[#flights + 1] = {car = e, p = cp, v = v, t = 0, yaw = 0, spin = spin, angles = angles}
    b.flown = b.flown + 1
end

-- one car per CAR_STEP s, nearest first, CAR_MAX per blast; the blast's record is dropped with its queue empty
local function CarTick(dt)
    local player = Game.GetPlayer()
    for i = #blasts, 1, -1 do
        local b = blasts[i]
        b.t = b.t + dt
        b.step = b.step - dt
        if #b.queue > 0 and b.step <= 0 and player and b.flown < CAR_MAX then
            table.sort(b.queue, function(x, y) return x.d < y.d end)
            b.step = CAR_STEP
            LaunchCar(b, table.remove(b.queue, 1), player)
        end
        if b.t > CAR_WINDOW and (#b.queue == 0 or b.flown >= CAR_MAX) then
            local n = 0
            for _ in pairs(b.cars) do n = n + 1 end
            Log("explosion %d: %d hit events, %d vehicles in reach, %d set off, %d flying", b.n, b.hits, n, b.blown, b.flown)
            table.remove(blasts, i)
        end
    end
end

local function HookCarHits()
    local res = {}
    for _, cls in ipairs({"VehicleObject", "GameObject"}) do
        local ok, err = pcall(function()
            Observe(cls, "OnHit", function(self)
                local okH, errH = pcall(CarHit, self, cls .. ".OnHit")
                if not okH then Log("car hit: %s", tostring(errH)) end
            end)
        end)
        res[#res + 1] = cls .. ".OnHit" .. (ok and "" or (" (failed: " .. tostring(err) .. ")"))
    end
    Log("vehicle hit hooks: %s", table.concat(res, ", "))
end

-- the cooldown: the thrown-knife pool full
local function Recover(g)
    local player = Game.GetPlayer()
    if not player or not g.item then return end
    local ok, err = pcall(function()
        local sid = Game.GetTransactionSystem():GetItemData(player, g.item):GetStatsObjectID()
        Game.GetStatPoolsSystem():RequestSettingStatPoolValue(sid, gamedataStatPoolType.ThrowRecovery, 100, player)
    end)
    Log("cooldown: ThrowRecovery pool set full: %s", ok and "ok" or ("failed: " .. tostring(err)))
end

local function GrenadeTick(dt)
    PushTick(dt)
    CarTick(dt)
    FlightTick(dt)
    for i = #fx_ids, 1, -1 do
        local f = fx_ids[i]
        f.t = f.t + dt
        if f.t > 6 then pcall(function() Game.GetStaticEntitySystem():DespawnEntity(f.id) end); table.remove(fx_ids, i) end
    end
    last_throw = last_throw + dt
    for k, hd in pairs(hidden) do   -- the pooled knife projectile looks right again a while after the throw
        hd.t = hd.t + dt
        if hd.t > 4 then pcall(function() hd.comp:Toggle(true) end); hidden[k] = nil end
    end
    local player = Game.GetPlayer()
    if player then
        local it = HeldGrenade(player)
        if it then held.item, held.t = it, 0 else held.t = held.t + dt end
    end
    if #live == 0 then return end
    -- NPCs near the grenades (refreshed now and then): they knock the grenade back
    npc_cache.t = npc_cache.t + dt
    if npc_cache.t > 0.25 and player then
        npc_cache.t = 0
        npc_cache.list = {}
        local pkey = KeyOf(player)
        for k, npc in pairs(Around(player, live[1].pos, 25, "TSQ_NPC;")) do
            if IsNPC(npc, pkey) then npc_cache.list[k] = npc end
        end
    end
    for i = #live, 1, -1 do
        local g = live[i]
        g.t = g.t + dt
        local speed = len(g.vel)
        local n = math.max(1, math.min(8, math.ceil(speed * dt / 0.25)))
        for _ = 1, n do Step(g, dt / n) end
        if not g.rest then
            for k, npc in pairs(npc_cache.list) do
                if not g.hit_npc[k] then
                    local at = Hips(npc)
                    if not at then pcall(function() at = add(ToVector4(npc:GetWorldPosition()), mul(UP, 0.9)) end) end
                    local d = at and V4(g.pos.x - at.x, g.pos.y - at.y, 0)
                    if d and len(d) < 0.45 and g.pos.z > at.z - 1.0 and g.pos.z < at.z + 0.9 then
                        g.hit_npc[k] = true
                        local out = norm(d) or mul(g.vel, -1)
                        g.vel = add(mul(out, len(g.vel) * 0.3), V4(0, 0, 0.5))
                        Log("grenade %d bounced off an NPC", g.n)
                    end
                end
            end
            -- spin with its speed about the axis across its motion
            local axis = norm(cross(UP, g.vel))
            if axis then g.q = QMul(QAxis(axis, len(g.vel) * dt / BALL_R * 0.5), g.q) end
        end
        Follow(g)
        if not g.recovered and g.t >= RECOVER then g.recovered = true; Recover(g) end
        -- run 8 (owner: 'add the sound'): the 2-s "Hallelujah" (Audioware, r6/audioware/holygrenade) ends with the blast
        if g.t >= FUSE - CHOIR_LEN and not g.choir then
            g.choir = true
            Hud("~ Hallelujah! ~", CHOIR_LEN)
            local okS, errS = pcall(function() Game.GetAudioSystem():Play("holygrenade_hallelujah") end)
            if not okS and not sound_err then sound_err = true; Log("sound failed (Audioware?): %s", tostring(errS)) end
        end
        if g.t >= FUSE then
            table.remove(live, i)
            Explode(g, g.pos)
        end
    end
end

-- CET ----------------------------------------------------------------------------------------------------------------
registerForEvent("onInit", function()
    UP = V4(0, 0, 1)
    Log("holygrenade loaded (CET %s)", tostring(GetVersion and GetVersion() or "?"))
    local ok, rec = pcall(function() return TweakDB:GetRecord(ITEM) end)
    item_ready = ok and rec ~= nil
    Log("item: %s %s", ITEM, item_ready and "found (TweakXL)" or "MISSING - TweakXL and r6/tweaks/holygrenade.yaml?")
    local okh, errh = pcall(function()
        Observe("EntityBuilder", "OnAssemble", function(_, event)
            local e = nil
            pcall(function() e = event:GetEntity() end)
            local k = e and KeyOf(e)
            local fn = k and on_assemble[k]
            if fn then
                on_assemble[k] = nil
                local okA, errA = pcall(fn, e)
                if not okA then Log("assemble: %s", tostring(errA)) end
            end
        end)
    end)
    Log("assemble hook: %s", okh and "ok" or tostring(errh))
    HookProjectiles()
    HookCarHits()
end)

registerForEvent("onUpdate", function(dt)
    if hud.t > 0 then hud.t = hud.t - dt end
    local okg, errg = pcall(GiftTick, dt)
    if not okg and not gift.err then gift.err = true; Log("gift error: %s", tostring(errg)) end
    local ok, err = pcall(GrenadeTick, dt)
    if not ok and not hud.err then hud.err = true; Log("grenade tick error: %s", tostring(err)) end
end)

registerForEvent("onDraw", function()
    if not hud.text or hud.t <= 0 then return end
    ImGui.SetNextWindowPos(40, 200, ImGuiCond.Always)
    if ImGui.Begin("holygrenade_hud", true, ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.AlwaysAutoResize
                   + ImGuiWindowFlags.NoInputs + ImGuiWindowFlags.NoBackground) then
        ImGui.Text(hud.text)
    end
    ImGui.End()
end)

registerHotkey("holygrenade_give", "Give the Holy Hand Grenade", Give)
