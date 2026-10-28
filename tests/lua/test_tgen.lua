-- FX-TGEN: zz_xrrfix_tgen*.script, zz_xrrfix_tgen_prof.script (specs/fixes/fx-tgen.md)
local H = ...

local MOD = "zz Task Generation Speed Fix"
local FIX, PROF = "zz_xrrfix_tgen", "zz_xrrfix_tgen_prof"
local MEMO_MARKER = "[XRRFIX] tgen: prerequisites memo installed (5000 ms)"
local BOUNTY_MARKER = "[XRRFIX] tgen: bounty scan shared (snapshot 5000 ms)"
local BOUNTY_SKIP = "[XRRFIX] tgen: Taskboard bounty selector not found, bounty part skipped"

-- Stand-in for PDA Taskboard Redesign v1.3 z_taskboard_bounty_variants.script: the same local
-- names and call shapes (GetVariantInfo -> variant_list -> build_variants and its helpers), with
-- fake server objects { stalker, alive, comm, rela, map, near, bad_smart }. build_variants is
-- the original full scan; Variants(task_id, p) is a test entry that reaches it like
-- setup_bounty_task does. __valid_calls counts candidate_valid; __reject makes it refuse ids.
local BOUNTY_SRC = [==[
local MAX_VARIANTS = 3
local faction_list = { "stalker", "dolg", "freedom", "bandit", "army" }
local blacklisted_maps = { ["l13_generators"] = true, ["fake_start"] = true }

local function selected_blacklist() return __extra_blacklist end
local function is_smart_valid(squad_id) return not (__bad_smarts and __bad_smarts[squad_id]) end
local function level_of(se_obj) return se_obj and se_obj.map end
local function faction_lookup_from_params(p)
	local lookup = {}
	if p[2] == "true" then
		for i = 1, #faction_list do
			if faction_list[i] ~= p[4] then lookup[faction_list[i]] = true end
		end
	else
		for i = 4, #p do lookup[p[i]] = true end
	end
	return lookup
end
local function candidate_relation(id, se_obj, faction_lookup)
	if not (id and se_obj and se_obj.stalker and se_obj.alive) then return end
	if faction_lookup[alife_character_community(se_obj)] ~= true then return end
	return se_obj.rela
end
local function candidate_valid(id, p)
	__valid_calls = (__valid_calls or 0) + 1
	if __reject and __reject[id] then return false end
	local se_obj = alife_object(id)
	return candidate_relation(id, se_obj, faction_lookup_from_params(p)) ~= nil
end
local function append_unique(result, seen, source)
	if #result >= MAX_VARIANTS then return true end
	for _, id in ipairs(source or {}) do
		if not seen[id] then
			seen[id] = true
			result[#result + 1] = id
			if #result >= MAX_VARIANTS then return true end
		end
	end
	return false
end
local function shuffled_copy(source)
	local result = {}
	for _, v in ipairs(source or {}) do result[#result + 1] = v end
	return result
end
local function build_variants(task_id, p)
	local faction_lookup = faction_lookup_from_params(p)
	local valid = { enemy = {}, neutral = {} }
	local other = { enemy = {}, neutral = {} }
	local additional_blacklist = selected_blacklist()
	local sim = alife()
	for id = 1, 65534 do
		local se_obj = sim:object(id)
		if se_obj then
			local relation = candidate_relation(id, se_obj, faction_lookup)
			if relation and is_smart_valid(se_obj.group_id) then
				local map = level_of(se_obj)
				if map and not blacklisted_maps[map] and not (additional_blacklist and additional_blacklist[map]) then
					if p[3] == "true" and not simulation_objects.is_on_the_nearby_level(sim:actor(), se_obj) then
						other[relation][#other[relation] + 1] = id
					else
						valid[relation][#valid[relation] + 1] = id
					end
				end
			end
		end
	end
	local result, seen = {}, {}
	if append_unique(result, seen, shuffled_copy(valid.enemy)) then return result end
	if append_unique(result, seen, shuffled_copy(valid.neutral)) then return result end
	if append_unique(result, seen, shuffled_copy(other.enemy)) then return result end
	append_unique(result, seen, shuffled_copy(other.neutral))
	return result
end
local function variant_list(task_id, p)
	if not candidate_valid then return {} end
	return build_variants(task_id, p)
end
function GetVariantInfo(task_id) return variant_list(task_id) end
function Variants(task_id, p) return variant_list(task_id, p) end
]==]

-- Server-object methods the scan uses; plain fields keep the bounty stand-in simple. The game graph
-- maps a vertex straight to a level name (m_game_vertex_id = level name).
local SE = { __index = {
	section_name = function(self) return self.sec or "obj" end,
	clsid = function(self) return self.cls end,
	is_alive = function(self) return self.living ~= false end,
} }

-- world: id -> fake server object; counts alife():object calls
local function make_world(G, objs)
	G.__objects = 0
	for _, o in pairs(objs) do if not getmetatable(o) then setmetatable(o, SE) end end
	local sim = {}
	function sim:object(id) G.__objects = G.__objects + 1; return objs[id] end
	function sim:actor() return { id = 0 } end
	function sim:level_name(lid) return lid end
	G.alife = function() return sim end
	G.alife_object = function(id) return objs[id] end
	G.alife_character_community = function(se) return se.comm end
	G.game_graph = function() return { vertex = function(_, v) return { level_id = function() return v end } end } end
	G.simulation_objects = {
		is_on_the_nearby_level = function(_, se) return se.near end,
		is_on_the_same_level = function(_, se) return se.m_game_vertex_id == "l01_escape" end,
		is_on_the_linked_level = function(_, se) return se.linked == true end,
		config = { r_value = function() return "l02_garbage" end },
	}
end

local function st(comm, rela, map, near, extra)
	local o = { stalker = true, alive = true, comm = comm, rela = rela, map = map or "l01_escape", near = near ~= false, group_id = 500 }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

-- Loads the fix into G: the entry script now; like the game's script loader, any other zz_xrrfix_tgen_* module of the
-- mod on its first reference (opts.broken = { module name -> true } makes that module fail to load).
local function load_fix(G, opts)
	local broken = opts and opts.broken or {}
	setmetatable(G.__lazy, { __index = function(_, name)
		if type(name) ~= "string" or not name:find("^zz_xrrfix_tgen_") then return nil end
		if broken[name] then return "error('broken module', 0)" end
		local fh = io.open(H.root .. "/mods/" .. MOD .. "/gamedata/scripts/" .. name .. ".script", "rb")
		if not fh then return nil end
		local src = fh:read("*a")
		fh:close()
		return src
	end })
	return H.load_fix(G, MOD, FIX)
end

local function setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__prereq = {}
	G.xr_conditions = opts.no_prereq and {} or {
		has_completed_task_prerequisites = function(actor, npc, p, extra)
			G.__prereq[#G.__prereq + 1] = { actor = actor, npc = npc, id = p and p[1], extra = extra }
			if G.__boom and G.__boom == (p and p[1]) then error("precondition failed", 0) end
			-- like validate_measure_task: asks for the dialog NPC and answers for that NPC only
			if G.__by_npc and G.__by_npc[p and p[1]] then
				return G.mob_trade.GetTalkingNpc():id() == G.__by_npc[p[1]]
			end
			return (G.__answers or {})[p and p[1]] ~= false
		end,
	}
	if opts.mob_trade then
		G.mob_trade = { GetTalkingNpc = function() return { id = function() return G.__talking end } end }
	end
	make_world(G, opts.objs or {})
	if opts.debug then G.debug = opts.debug end
	if not opts.no_bounty then
		local src = BOUNTY_SRC
		if opts.bounty_patch then src = opts.bounty_patch(src) end
		H.lazy(G, "z_taskboard_bounty_variants", src)
	end
	local fix = load_fix(G, opts)
	fix.on_game_start()
	return G, fix
end

local function prereq(G, id) return G.xr_conditions.has_completed_task_prerequisites(nil, nil, { id }) end
local function variants(G, task_id, p) return G.z_taskboard_bounty_variants.Variants(task_id, p) end

---------------------------------------------------------------------------
-- memo
---------------------------------------------------------------------------

H.case("FX-TGEN-001 wraps has_completed_task_prerequisites once and logs the marker", function()
	local G, fix = setup()
	local w = G.xr_conditions.has_completed_task_prerequisites
	fix.on_game_start()
	H.truthy(G.xr_conditions.has_completed_task_prerequisites == w, "second on_game_start keeps the wrapper")
	H.eq(1, H.log_count(G, MEMO_MARKER), "marker once")
	prereq(G, "t1")
	H.eq(1, #G.__prereq, "one call reaches the original (no double wrap)")
end)

H.case("FX-TGEN-001 without the function: logged and skipped", function()
	local G = setup({ no_prereq = true })
	H.log_has(G, "[XRRFIX] tgen: has_completed_task_prerequisites missing, memo skipped")
	H.log_lacks(G, MEMO_MARKER)
	H.falsy(G.xr_conditions.has_completed_task_prerequisites, "nothing installed")
end)

H.case("FX-TGEN-002 generation calls answered from the memo for 5000 ms, per task_id", function()
	local G = setup()
	G.__answers = { t1 = false }
	H.eq(false, prereq(G, "t1"), "original result")
	G.__now = 4999
	H.eq(false, prereq(G, "t1"), "memo result")
	H.eq(1, #G.__prereq, "original called once within 5000 ms")
	H.eq(true, prereq(G, "t2"), "other task_id: own result")
	H.eq(2, #G.__prereq, "other task_id asks the original")
	G.__now = 5000
	G.__answers = { t1 = true }
	H.eq(true, prereq(G, "t1"), "fresh result after 5000 ms")
	H.eq(3, #G.__prereq, "original called again at 5000 ms")
end)

H.case("FX-TGEN-003 calls with an actor, an npc or no task id always reach the original", function()
	local G = setup()
	local f = G.xr_conditions.has_completed_task_prerequisites
	f("actor", nil, { "t1" })
	f("actor", nil, { "t1" })
	f(nil, "npc", { "t1" }, "x")
	f(nil, nil, {})
	f(nil, nil, { 5 })
	H.eq(5, #G.__prereq, "all five reached the original")
	H.eq("actor", G.__prereq[1].actor, "actor passed")
	H.eq("npc", G.__prereq[3].npc, "npc passed")
	H.eq("x", G.__prereq[3].extra, "extra argument passed")
	prereq(G, "t1")
	H.eq(6, #G.__prereq, "logic calls stored nothing")
end)

H.case("FX-TGEN-012 preconditions that read the dialog NPC are never answered from the memo", function()
	local G = setup({ mob_trade = true })
	local talking = G.mob_trade.GetTalkingNpc
	G.__by_npc = { m1 = 1 }
	G.__talking = 1
	H.eq(true, prereq(G, "m1"), "NPC 1")
	G.__now, G.__talking = 100, 2
	H.eq(false, prereq(G, "m1"), "NPC 2 gets its own answer")
	H.eq(2, #G.__prereq, "original asked both times")
	H.truthy(G.mob_trade.GetTalkingNpc == talking, "GetTalkingNpc restored")
	G.__by_npc = nil
	G.__now = 200
	prereq(G, "m1")
	G.__now = 300
	prereq(G, "m1")
	H.eq(4, #G.__prereq, "stays NPC-bound even when it no longer asks")
	prereq(G, "t1")
	prereq(G, "t1")
	H.eq(5, #G.__prereq, "other tasks still memoized")
	G.__boom = "e1"
	local ok, err = pcall(prereq, G, "e1")
	H.falsy(ok, "error re-raised")
	H.eq("precondition failed", err, "same error")
	H.truthy(G.mob_trade.GetTalkingNpc == talking, "GetTalkingNpc restored after an error")
end)

H.case("FX-TGEN-012 without mob_trade the memo works as before", function()
	local G = setup()
	prereq(G, "t1")
	prereq(G, "t1")
	H.eq(1, #G.__prereq, "memoized")
end)

H.case("FX-TGEN-004 on_level_changing clears the memo and the bounty snapshot", function()
	local G = setup({ objs = { [10] = st("bandit", "enemy") } })
	prereq(G, "t1")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	H.eq(65534, G.__objects, "one scan")
	G.SendScriptCallback("on_level_changing")
	prereq(G, "t1")
	H.eq(2, #G.__prereq, "memo cleared")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	H.eq(2 * 65534, G.__objects, "snapshot cleared, scanned again")
end)

---------------------------------------------------------------------------
-- bounty
---------------------------------------------------------------------------

H.case("FX-TGEN-005 swaps build_variants once and logs the marker", function()
	local G, fix = setup({ objs = { [10] = st("bandit", "enemy") } })
	H.eq(1, H.log_count(G, BOUNTY_MARKER), "marker")
	fix.on_game_start()
	H.eq(1, H.log_count(G, BOUNTY_MARKER), "marker once")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "bandit" })
	H.eq(65534, G.__objects, "the shared scan is in place")
end)

H.case("FX-TGEN-005 without the module, debug or a helper: logged and skipped", function()
	local G = setup({ no_bounty = true })
	H.log_has(G, BOUNTY_SKIP)
	H.log_lacks(G, BOUNTY_MARKER)
	H.log_has(G, MEMO_MARKER, "memo still installed")

	G = setup({ debug = {} })
	H.log_has(G, BOUNTY_SKIP, "no debug library")

	G = setup({ objs = { [10] = st("bandit", "enemy") },
		bounty_patch = function(src) return (string.gsub(src, "local MAX_VARIANTS = 3", "MAX_VARIANTS = 3")) end })
	H.log_has(G, BOUNTY_SKIP, "helper missing")
	H.log_lacks(G, BOUNTY_MARKER)
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "bandit" })
	H.eq(2 * 65534, G.__objects, "original build_variants untouched")
end)

H.case("FX-TGEN-006 one scan per 5000 ms snapshot", function()
	local G = setup({ objs = { [10] = st("bandit", "enemy"), [20] = st("army", "enemy"), [30] = st("dolg", "neutral") } })
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	variants(G, "b2", { "b2", "false", "false", "army" })
	G.__now = 4999
	variants(G, "b3", { "b3", "false", "false", "dolg" })
	H.eq(65534, G.__objects, "three tasks, one scan")
	G.__now = 5000
	variants(G, "b4", { "b4", "false", "false", "dolg" })
	H.eq(2 * 65534, G.__objects, "new scan after 5000 ms")
	local s = G.zz_xrrfix_tgen.take_stats()
	H.eq(2, s.built, "two snapshots built")
	H.eq(2, s.reused, "two reused")
end)

H.case("FX-TGEN-006 take_stats counts zero for a module that failed to load", function()
	local G = setup({ broken = { zz_xrrfix_tgen_memo = true } })
	H.log_has(G, "[XRRFIX] tgen: memo install error: broken module", "memo failed")
	H.log_has(G, BOUNTY_MARKER, "bounty still installed")
	variants(G, "b1", { "b1", "false", "false", "bandit" })
	local s = G.zz_xrrfix_tgen.take_stats()
	H.eq(0, s.hits, "no memo hits")
	H.eq(0, s.misses, "no memo misses")
	H.eq(1, s.built, "snapshot counters still read")
end)

H.case("FX-TGEN-007 picks the same candidates, in the same group order, as the original", function()
	local objs = {
		[1] = st("bandit", "enemy", "l01_escape", false),        -- far enemy
		[2] = st("stalker", "neutral", "l01_escape", true),      -- other faction
		[3] = st("bandit", "neutral", "l02_garbage", true),      -- near neutral
		[4] = st("bandit", "enemy", "l03_agroprom", true),       -- near enemy
		[5] = st("bandit", "enemy", "l13_generators", true),     -- blacklisted map
		[6] = st("bandit", "enemy", "l04_darkvalley", true),     -- extra blacklist
		[7] = st("bandit", "enemy", "l01_escape", true, { group_id = 77 }), -- base smart
		[8] = st("bandit", "enemy", "l01_escape", true, { alive = false }),
	}
	local G = setup({ objs = objs })
	G.__extra_blacklist = { l04_darkvalley = true }
	G.__bad_smarts = { [77] = true }
	local p = { "b1", "false", "true", "bandit" }
	H.same({ 4, 3, 1 }, variants(G, "b1", p), "near enemy, near neutral, far enemy")
	H.same({ 1, 4, 3 }, variants(G, "b2", { "b2", "false", "false", "bandit" }), "p[3] false: enemies first")
	H.same({ 2 }, variants(G, "b3", { "b3", "false", "false", "stalker" }), "stalker task sees only stalkers")

	-- the original over the same world
	local O = setup({ objs = objs, debug = {} })
	O.__extra_blacklist = { l04_darkvalley = true }
	O.__bad_smarts = { [77] = true }
	H.same({ 4, 3, 1 }, variants(O, "b1", p), "original agrees")
end)

H.case("FX-TGEN-007 a same-named local seen only by append_unique does not replace build_variants' blacklisted_maps", function()
	-- append_unique gets its own blacklisted_maps that bans l01_escape; build_variants keeps the mod's table
	local function shadow(src)
		src = string.gsub(src, "local function append_unique%(result, seen, source%)\n",
			"local append_unique\ndo\nlocal blacklisted_maps = { l01_escape = true }\n"
			.. "append_unique = function(result, seen, source)\n\tlocal _ = blacklisted_maps\n")
		return (string.gsub(src, "local function shuffled_copy", "end\nlocal function shuffled_copy"))
	end
	local objs = { [10] = st("bandit", "enemy", "l01_escape") }
	local p = { "b1", "false", "false", "bandit" }
	local G = setup({ objs = objs, bounty_patch = shadow })
	H.log_has(G, BOUNTY_MARKER)
	local O = setup({ objs = objs, bounty_patch = shadow, debug = {} })
	H.same({ 10 }, variants(O, "b1", p), "the original ignores append_unique's local")
	H.same({ 10 }, variants(G, "b1", p), "the fix as well")
end)

H.case("FX-TGEN-007 stops at MAX_VARIANTS", function()
	local objs = {}
	for i = 1, 6 do objs[i] = st("bandit", "enemy") end
	local G = setup({ objs = objs })
	H.eq(3, #variants(G, "b1", { "b1", "false", "false", "bandit" }), "three variants")
end)

H.case("FX-TGEN-008 every pick passes candidate_valid; refused ones are replaced", function()
	local objs = { [1] = st("bandit", "enemy"), [2] = st("bandit", "enemy"), [3] = st("bandit", "enemy"), [4] = st("bandit", "enemy") }
	local G = setup({ objs = objs })
	G.__reject = { [2] = true }
	H.same({ 1, 3, 4 }, variants(G, "b1", { "b1", "false", "false", "bandit" }), "2 skipped, 4 takes its place")
	H.eq(4, G.z_taskboard_bounty_variants.__valid_calls, "each pick checked")
	objs[3].alive = false
	G.__reject = nil
	H.same({ 1, 2, 4 }, variants(G, "b2", { "b2", "false", "false", "bandit" }), "dead since the snapshot: skipped")
end)

---------------------------------------------------------------------------
-- profiler
---------------------------------------------------------------------------

local function prof_setup(opts)
	opts = opts or {}
	local G = H.env()
	G.__us = 0
	G.__advance = function(ms) G.__us = G.__us + ms * 1000 end
	G.profile_timer = function()
		local t = { acc = 0 }
		function t:start() self.t0 = G.__us end
		function t:stop() self.acc = self.acc + (G.__us - self.t0) end
		function t:time() return self.acc end
		return t
	end
	G.axr_task_manager = {
		generate_available_tasks = function(npc)
			G.__advance(2)
			G.xr_conditions.validate_assault_task(nil, npc, { "a" })
			return "gen", npc
		end,
	}
	G.xr_conditions = {
		validate_assault_task = function() G.__advance(opts.assault_ms or 3) return true end,
		squad_exist = function() return true end,
	}
	G.xr_effects = {
		setup_bounty_task = function() G.__advance(1) error("bounty failed", 0) end,
	}
	if opts.tgen then
		G.zz_xrrfix_tgen = { take_stats = function() return { hits = 7, misses = 3, built = 1, reused = 4 } end }
	end
	local prof = H.load_fix(G, MOD, PROF)
	prof.on_game_start()
	return G, prof
end

local function first_update(G) G.SendScriptCallback("actor_on_first_update") end
local function update(G) G.SendScriptCallback("actor_on_update") end

H.case("FX-TGEN-009 wraps on actor_on_first_update once; results and errors pass through", function()
	local G = prof_setup()
	H.truthy(G.axr_task_manager.generate_available_tasks, "present")
	local orig = G.xr_conditions.squad_exist
	first_update(G)
	H.log_has(G, "[XRRFIX] taskprof: installed (3 functions timed)")
	H.truthy(G.xr_conditions.squad_exist == orig, "generic logic condition not wrapped")
	local w = G.axr_task_manager.generate_available_tasks
	first_update(G)
	H.truthy(G.axr_task_manager.generate_available_tasks == w, "wrapped once")
	H.eq(1, H.log_count(G, "taskprof: installed"), "marker once")
	local a, b = G.axr_task_manager.generate_available_tasks("npc1")
	H.eq("gen", a, "first result")
	H.eq("npc1", b, "second result")
	local ok, err = pcall(G.xr_effects.setup_bounty_task)
	H.falsy(ok, "error re-raised")
	H.eq("bounty failed", err, "same error")
end)

H.case("FX-TGEN-010 summary after 1 s idle: totals, nested time inside callers, top list", function()
	local G = prof_setup({ tgen = true })
	first_update(G)
	G.axr_task_manager.generate_available_tasks("n1")
	G.axr_task_manager.generate_available_tasks("n2")
	G.__now = 500
	update(G)
	H.log_lacks(G, "taskprof: 0.0 s", "no summary before 1 s idle")
	G.__now = 999
	update(G)
	H.eq(0, H.log_count(G, "| memo"), "still nothing at 999 ms")
	G.__now = 1000
	update(G)
	H.log_has(G, "[XRRFIX] taskprof: 0.0 s, generate 2 calls 10 ms | memo 7/10 hits, world snapshots 1 built, 4 reused")
	H.log_has(G, "[XRRFIX] taskprof: #1 axr_task_manager.generate_available_tasks | total 10.0 ms | calls 2 | max 5.0 ms")
	H.log_has(G, "[XRRFIX] taskprof: #2 xr_conditions.validate_assault_task | total 6.0 ms | calls 2 | max 3.0 ms")
	local n = #G.__log
	G.__now = 3000
	update(G)
	H.eq(n, #G.__log, "counters reset: nothing more")
end)

H.case("FX-TGEN-010 under 5 ms (nested time counted once): no summary, counters reset", function()
	local G = prof_setup({ assault_ms = 2 })   -- generate 4 ms, of which assault 2 ms
	first_update(G)
	G.axr_task_manager.generate_available_tasks("n1")
	G.__now = 1000
	update(G)
	H.eq(0, H.log_count(G, "taskprof: #"), "no top list")
	H.eq(0, H.log_count(G, "generate 1 calls"), "no summary")
	G.__now = 1500
	G.axr_task_manager.generate_available_tasks("n2")
	G.axr_task_manager.generate_available_tasks("n3")
	G.axr_task_manager.generate_available_tasks("n4")
	G.__now = 2500
	update(G)
	H.log_has(G, "generate 3 calls 12 ms | no tgen counters", "only the new burst counted")
end)

---------------------------------------------------------------------------
-- measure and delivery (FX-TGEN-013 .. 016)
---------------------------------------------------------------------------

-- Stand-in for tasks_measure.script (Oleh's Tasks Crash Fixes): the same locals the fix looks for
-- (cache, anomaly_types), blacklisted_maps opened as a module variable like the unlocalizer of
-- G_FLAT's More Measurement Task Maps does, and the original 65534-object scan.
local MEASURE_SRC = [==[
local anomaly_types = { chemical = { zone_acid = true }, electric = { zone_el = true } }
blacklisted_maps = { l13_generators = true }
local cache = {}
function cached(task_id, giver_id) return cache[task_id] and cache[task_id][giver_id] end
xr_conditions.validate_measure_task = function(actor, npc, p)
	if not (p and (#p >= 5)) then return false end
	local task_id = p[1]
	if (not db.actor:is_talking()) then return end
	local task_giver = mob_trade.GetTalkingNpc()
	local task_giver_id = task_giver:id()
	if cache[task_id] and cache[task_id][task_giver_id] then return true end
	local scan_mode = tonumber(p[2]) or 4
	local item_1_sec = ini_sys:section_exist(p[4]) and p[4] or nil
	if (not item_1_sec) then return false end
	local target_types = {}
	for i = 5, #p do target_types[p[i]] = true end
	local ano_tbl = {}
	for typ, v in pairs(anomaly_types) do
		if target_types[typ] then for sec in pairs(v) do ano_tbl[sec] = true end end
	end
	local targets = {}
	local sim = alife()
	local gg = game_graph()
	local dyn_anomalies = bind_anomaly_field and bind_anomaly_field.dyn_anomalies or {}
	for i = 1, 65534 do
		local se_obj = sim:object(i)
		if se_obj and ano_tbl[se_obj:section_name()] then
			local lvl_name = sim:level_name(gg:vertex(se_obj.m_game_vertex_id):level_id())
			if (not blacklisted_maps[lvl_name]) and (not (dyn_anomalies[lvl_name] and dyn_anomalies[lvl_name][i] ~= nil)) then
				local is_online = se_obj.online
				local is_nearby = string.find(simulation_objects.config:r_value(level.name(), "target_maps", 0, ""), lvl_name)
				if ((scan_mode == 1) and is_online) or ((scan_mode == 2) and (is_online or is_nearby))
				or ((scan_mode == 3) and is_nearby) or ((scan_mode == 4) and (not (is_online or is_nearby)))
				or (scan_mode == 5) then
					targets[#targets + 1] = i
				end
			end
		end
	end
	if (#targets == 0) then return false end
	local target_id = targets[math.random(#targets)]
	if not alife_object(target_id) then return false end
	if (not cache[task_id]) then cache[task_id] = {} end
	cache[task_id][task_giver_id] = { target_id = target_id, task_giver_comm = character_community(task_giver), item_1_sec = item_1_sec, monster = false }
	return true
end
]==]

-- G_FLAT's More Measurement Task Maps: keeps the original in a local and forces scan mode 5
local GFLAT_SRC = [==[
local validate_measure_task_original = xr_conditions.validate_measure_task
xr_conditions.validate_measure_task = function(actor, npc, p)
	if p and p[2] then p[2] = 5 end
	return validate_measure_task_original(actor, npc, p)
end
]==]

-- Stand-in for tasks_delivery.script (Tasks QoL): locals delivery_cache and faction_list, original scan
local DELIVERY_SRC = [==[
local faction_list = { "stalker", "dolg", "bandit" }
local delivery_cache = {}
xr_effects.blacklisted_maps = { l13_generators = true }
xr_effects.on_init_delivery_task = function(actor, npc, p)
	if (not p) or (#p < 4) then return end
	local var = p[1]
	local same_faction = (p[2] == "true")
	local far_location = (p[3] == "true")
	local item_1_sec = p[math.random(4, #p)]
	local task_giver = mob_trade.GetTalkingNpc()
	local task_giver_id = task_giver:id()
	local task_giver_comm = character_community(task_giver)
	local target_id
	local sim = alife()
	if delivery_cache[var] and delivery_cache[var][task_giver_id] then
		target_id = delivery_cache[var][task_giver_id]
	else
		local faction_lookup = { [task_giver_comm] = true }
		if (not same_faction) then
			for i = 1, #faction_list do
				if faction_list[i] ~= task_giver_comm and not game_relations.is_factions_enemies(task_giver_comm, faction_list[i]) then
					faction_lookup[faction_list[i]] = true
				end
			end
		end
		local targets = {}
		local gg = game_graph()
		for i = 1, 65534 do
			local se_obj = sim:object(i)
			if (se_obj and IsStalker(nil, se_obj:clsid()) and se_obj:alive() and string.find(se_obj:section_name(), "sim_default") and get_object_story_id(i) == nil) then
				if faction_lookup[alife_character_community(se_obj)] == true then
					local squad = se_obj.group_id and se_obj.group_id ~= 65535 and alife_object(se_obj.group_id)
					if squad and (squad:commander_id() == se_obj.id) and string.find(squad:section_name(), "sim_squad") and (squad.current_action == 1) then
						local lvl_name = sim:level_name(gg:vertex(se_obj.m_game_vertex_id):level_id())
						if not xr_effects.blacklisted_maps[lvl_name] and not simulation_objects.is_on_the_same_level(sim:actor(), se_obj) then
							if far_location and (not simulation_objects.is_on_the_linked_level(sim:actor(), se_obj)) then
								targets[#targets + 1] = i
							elseif (not far_location) then
								targets[#targets + 1] = i
							end
						end
					end
				end
			end
		end
		if (#targets == 0) then
			blacklist_helper.TaskBlacklist[p[1]] = true
			return
		end
		blacklist_helper.TaskBlacklist[p[1]] = false
		target_id = targets[math.random(#targets)]
		if (not delivery_cache[var]) then delivery_cache[var] = {} end
		delivery_cache[var][task_giver_id] = target_id
	end
	local se_target = alife_object(target_id)
	if (not se_target) then return end
	save_var(db.actor, var, { target_id = target_id, task_giver_comm = task_giver_comm, item_1_sec = item_1_sec })
end
]==]

-- xrRazom's host-only guard (xrr_patch_task_guards): wraps the effect, the original is its upvalue
local GUARD_SRC = [==[
local orig = xr_effects.on_init_delivery_task
xr_effects.on_init_delivery_task = function(...)
	if not XrrIsHost() then return nil end
	return orig(...)
end
]==]

local DSE = { __index = {
	section_name = function(self) return self.sec end,
	clsid = function(self) return self.cls end,
	alive = function(self) return self.living ~= false end,
	commander_id = function(self) return self.commander end,
} }

local function anomaly(sec, lvl, online)
	return setmetatable({ sec = sec, m_game_vertex_id = lvl, online = online == true }, DSE)
end

-- a squad commander at `lvl` (squad id = id + 1000) and its squad
local function commander(objs, id, comm, lvl, extra)
	local o = setmetatable({ id = id, cls = "stalker", sec = "sim_default_" .. comm, comm = comm, m_game_vertex_id = lvl,
		group_id = id + 1000 }, DSE)
	for k, v in pairs(extra or {}) do o[k] = v end
	objs[id] = o
	objs[id + 1000] = setmetatable({ commander = id, sec = "sim_squad_" .. comm, current_action = 1 }, DSE)
	return o
end

local function task_setup(objs, opts)
	opts = opts or {}
	local G = H.env()
	G.xr_conditions = { has_completed_task_prerequisites = function() return true end }
	G.xr_effects = {}
	make_world(G, objs)
	G.__giver = 1
	G.db = { actor = { is_talking = function() return true end } }
	G.mob_trade = { GetTalkingNpc = function() return { id = function() return G.__giver end, comm = "stalker",
		character_name = function() return "Giver" end } end }
	G.character_community = function(o) return o.comm or "stalker" end
	G.ini_sys = { section_exist = function() return true end }
	G.level = { name = function() return "l01_escape" end }
	G.blacklist_helper = { TaskBlacklist = {}, GetMcmDropdownValue = function() return 0 end,
		GetNorthernMaps = function() return {} end, ShouldBlacklistNorth = function() return false end,
		GetSouthernMaps = function() return {} end }
	G.IsStalker = function(_, cls) return cls == "stalker" end
	G.get_object_story_id = function() return nil end
	G.game_relations = { is_factions_enemies = function(a, b) return (a == "stalker" and b == "bandit") end }
	G.__saved = {}
	G.save_var = function(_, k, v) G.__saved[k] = v end
	G.printdbg = function() end
	G.CreateTimeEvent = function() end
	G.printe = function(f, ...) G.__log[#G.__log + 1] = "printe: " .. string.format(f, ...) end
	G.game = { translate_string = function(s) return s end }
	G.math = setmetatable({ random = function(a, b) return b or a end }, { __index = math }) -- always the last candidate
	G.XrrIsHost = function() return G.__host ~= false end
	H.load_module(G, "tasks_measure", MEASURE_SRC)
	if not opts.no_gflat then H.load_module(G, "z_more_measurement_task_maps", GFLAT_SRC) end
	H.load_module(G, "tasks_delivery", DELIVERY_SRC)
	if not opts.no_guard then H.load_module(G, "xrr_patch_task_guards", GUARD_SRC) end
	if opts.debug then G.debug = opts.debug end
	local fix = load_fix(G, opts)
	fix.on_game_start()
	return G, fix
end

local MP = { "m1", "4", "false", "detector", "chemical" }   -- measure task, scan mode 4 (G_FLAT makes it 5)
local function measure(G, giver)
	G.__giver = giver or G.__giver
	local p = {}
	for i, v in ipairs(MP) do p[i] = v end
	return G.xr_conditions.validate_measure_task(nil, nil, p)
end
local function deliver(G, var, giver, far)
	G.__giver = giver or G.__giver
	return G.xr_effects.on_init_delivery_task(nil, nil, { var, "false", far and "true" or "false", "package" })
end

local function measure_world()
	return {
		[1] = anomaly("zone_acid", "l02_garbage", false),     -- nearby level
		[2] = anomaly("zone_el", "l03_agroprom", false),      -- other type
		[3] = anomaly("zone_acid", "l13_generators", false),  -- blacklisted map
		[4] = anomaly("zone_acid", "l04_darkvalley", true),   -- online
		[5] = anomaly("zone_acid", "l05_bar", false),         -- far, offline
	}
end

H.case("FX-TGEN-013 measure copy replaces the original under G_FLAT's wrapper, once; G_FLAT still applies", function()
	local G, fix = task_setup(measure_world())
	H.log_has(G, "[XRRFIX] tgen: measure scan shared (snapshot 5000 ms)")
	local top = G.xr_conditions.validate_measure_task
	fix.on_game_start()
	H.truthy(G.xr_conditions.validate_measure_task == top, "G_FLAT's wrapper stays on top")
	H.eq(1, H.log_count(G, "measure scan shared"), "marker once")
	H.eq(true, measure(G, 1), "task available")
	H.eq(5, G.tasks_measure.cached("m1", 1).target_id, "scan mode 5 from G_FLAT: last candidate of all levels")
	H.eq(65534, G.__objects, "one scan")

	local S = task_setup(measure_world(), { debug = {} })
	H.log_has(S, "[XRRFIX] tgen: validate_measure_task not recognised, measure part skipped")
end)

H.case("FX-TGEN-014 measure: same candidates as the original, per-NPC cache, one scan for many NPCs", function()
	for _, gflat in ipairs({ true, false }) do
		local G = task_setup(measure_world(), { no_gflat = not gflat })
		local O = task_setup(measure_world(), { no_gflat = not gflat, debug = {} })
		for giver = 1, 3 do
			H.eq(measure(O, giver), measure(G, giver), "result, NPC " .. giver)
			H.same(O.tasks_measure.cached("m1", giver), G.tasks_measure.cached("m1", giver), "cache entry, NPC " .. giver)
		end
		H.eq(65534, G.__objects, "fix: one scan for three NPCs")
		H.eq(3 * 65534, O.__objects, "original: one scan per NPC")
	end
	-- scan mode 4 without G_FLAT: far + offline only (l02 is a nearby level, #4 is online)
	local G = task_setup(measure_world(), { no_gflat = true })
	measure(G, 1)
	H.eq(5, G.tasks_measure.cached("m1", 1).target_id, "far + offline + right type")
	G.tasks_measure.blacklisted_maps.l05_bar = true -- edited at runtime, as G_FLAT does
	H.eq(false, measure(G, 2), "no candidate left")
	H.eq(nil, G.tasks_measure.cached("m1", 2), "no cache entry")
end)

local function delivery_world()
	local objs = {}
	commander(objs, 10, "stalker", "l02_garbage")
	commander(objs, 11, "bandit", "l03_agroprom")                 -- enemy of the giver
	commander(objs, 12, "dolg", "l04_darkvalley", { linked = true })
	commander(objs, 13, "stalker", "l01_escape")                  -- same level as the actor
	commander(objs, 14, "dolg", "l13_generators")                 -- blacklisted
	commander(objs, 15, "stalker", "l05_bar", { living = false })
	return objs
end

H.case("FX-TGEN-015 delivery copy replaces the original under xrRazom's host guard, once; the guard still works", function()
	local G, fix = task_setup(delivery_world())
	H.log_has(G, "[XRRFIX] tgen: delivery scan shared (snapshot 5000 ms)")
	local top = G.xr_effects.on_init_delivery_task
	fix.on_game_start()
	H.truthy(G.xr_effects.on_init_delivery_task == top, "guard stays on top")
	H.eq(1, H.log_count(G, "delivery scan shared"), "marker once")
	G.__host = false
	deliver(G, "d1", 1)
	H.eq(nil, G.__saved.d1, "peer: guard returns before the copy")
	H.eq(0, G.__objects, "no scan on the peer")
	G.__host = true
	deliver(G, "d1", 1)
	H.eq(12, G.__saved.d1.target_id, "host: target saved")

	local N = task_setup(delivery_world(), { no_guard = true })
	H.log_has(N, "delivery scan shared", "no guard: the table entry itself is replaced")
	deliver(N, "d1", 1)
	H.eq(12, N.__saved.d1.target_id, "works without xrRazom")

	local S = task_setup(delivery_world(), { debug = {} })
	H.log_has(S, "[XRRFIX] tgen: on_init_delivery_task not recognised, delivery part skipped")
end)

H.case("FX-TGEN-016 commanders of squads with current_action ~= 1 are no targets, like the original", function()
	local function world()
		local objs = delivery_world()
		commander(objs, 16, "stalker", "l06_rostok")   -- the highest id: math.random would pick it
		objs[1016].current_action = 0
		return objs
	end
	local G = task_setup(world())
	local O = task_setup(world(), { debug = {} })
	deliver(O, "d1", 1)
	deliver(G, "d1", 1)
	H.eq(12, O.__saved.d1.target_id, "the original skips the busy squad")
	H.eq(O.__saved.d1.target_id, G.__saved.d1.target_id, "the fix as well")
end)

H.case("FX-TGEN-016 delivery: same target as the original, per-NPC cache, no-target answered from the snapshot", function()
	local G = task_setup(delivery_world())
	local O = task_setup(delivery_world(), { debug = {} })
	for _, far in ipairs({ false, true }) do
		local var = far and "far" or "near"
		for giver = 1, 2 do
			deliver(O, var, giver, far)
			deliver(G, var, giver, far)
			H.eq(O.__saved[var].target_id, G.__saved[var].target_id, var .. " NPC " .. giver .. ": target")
			H.eq(O.__saved[var].task_giver_comm, G.__saved[var].task_giver_comm, var .. " NPC " .. giver .. ": giver faction")
		end
	end
	H.eq(10, G.__saved.far.target_id, "far: linked level excluded")
	H.eq(65534, G.__objects, "fix: one scan")
	H.eq(4 * 65534, O.__objects, "original: one scan per NPC and task")

	local E = task_setup({ [1] = anomaly("zone_acid", "l02_garbage", false) })
	deliver(E, "d2", 1)
	deliver(E, "d2", 2)
	H.eq(true, E.blacklist_helper.TaskBlacklist.d2, "no target: blacklisted like the original")
	H.eq(65534, E.__objects, "no target twice: one scan")
end)
