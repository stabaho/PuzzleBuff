--[[
    Dcr_Buffs.lua - Part of DecursivePlus
    Priest buff casting support: Power Word: Fortitude, Shadow Protection,
    Inner Fire, and Touch of Weakness for self and party/raid members.

    DecursivePlus extends Decursive (by John Wellesz) with buff management.
    This file is released under the GNU General Public License v3.
--]]

local addonName, T = ...;
T._LoadedFiles = T._LoadedFiles or {};
T._LoadedFiles["Dcr_Buffs.lua"] = "2.7.34-plus";

-- ---------------------------------------------------------------------------
-- Spell IDs (TBC Classic)
-- ---------------------------------------------------------------------------
local SPELLS = {
    -- Power Word: Fortitude (Rank 7 - highest single, Rank 3 raid)
    FORTITUDE       = { single = 25389, raid = 25392 },
    -- Shadow Protection (Rank 3 single, Rank 2 raid)
    SHADOW_PROT     = { single = 25433, raid = 25434 },
    -- Inner Fire (Rank 7)
    INNER_FIRE      = { single = 25431, raid = nil },
    -- Touch of Weakness (Rank 6)
    TOUCH_WEAKNESS  = { single = 25461, raid = nil },
}

-- Buff names as they appear on unit auras (used for detection)
local BUFF_NAMES = {
    FORTITUDE      = "Power Word: Fortitude",
    FORTITUDE_RAID = "Prayer of Fortitude",
    SHADOW_PROT    = "Shadow Protection",
    SHADOW_RAID    = "Prayer of Shadow Protection",
    INNER_FIRE     = "Inner Fire",
    TOUCH_WEAKNESS = "Touch of Weakness",
}

-- ---------------------------------------------------------------------------
-- Config defaults
-- ---------------------------------------------------------------------------
DecursivePlusBuffDB = DecursivePlusBuffDB or {
    enabled       = true,
    fortitude     = true,
    shadowProtect = true,
    innerFire     = true,
    touchWeakness = true,
    selfOnly      = false,
    scanInterval  = 5,
}

-- ---------------------------------------------------------------------------
-- Frame and state
-- ---------------------------------------------------------------------------
local buffFrame = CreateFrame("Frame", "DecursivePlusBuffFrame", UIParent)
local lastScan  = 0
local casting   = false
local queue     = {}

-- ---------------------------------------------------------------------------
-- Helper: check if unit has a specific buff by name
-- ---------------------------------------------------------------------------
local function UnitHasBuff(unit, buffName)
    for i = 1, 40 do
        local name = UnitBuff(unit, i)
        if not name then break end
        if name == buffName then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Helper: check if unit has Inner Fire (self only)
-- ---------------------------------------------------------------------------
local function SelfHasInnerFire()
    return UnitHasBuff("player", BUFF_NAMES.INNER_FIRE)
end

-- ---------------------------------------------------------------------------
-- Helper: check if unit has Touch of Weakness (self only)
-- ---------------------------------------------------------------------------
local function SelfHasTouchOfWeakness()
    return UnitHasBuff("player", BUFF_NAMES.TOUCH_WEAKNESS)
end

-- ---------------------------------------------------------------------------
-- Build cast queue: scan self + party/raid for missing buffs
-- ---------------------------------------------------------------------------
local function BuildQueue()
    local db   = DecursivePlusBuffDB
    local units = { "player" }

    if not db.selfOnly then
        local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        local numRaid  = GetNumRaidMembers  and GetNumRaidMembers()  or 0
        if numRaid > 0 then
            for i = 1, numRaid do
                tinsert(units, "raid"..i)
            end
        elseif numParty > 0 then
            for i = 1, numParty do
                tinsert(units, "party"..i)
            end
        end
    end

    wipe(queue)

    for _, unit in ipairs(units) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDead(unit) then
            local isSelf = UnitIsUnit(unit, "player")

            -- Power Word: Fortitude
            if db.fortitude then
                local hasFort = UnitHasBuff(unit, BUFF_NAMES.FORTITUDE)
                               or UnitHasBuff(unit, BUFF_NAMES.FORTITUDE_RAID)
                if not hasFort then
                    tinsert(queue, { unit = unit, spell = SPELLS.FORTITUDE.single, name = "Power Word: Fortitude" })
                end
            end

            -- Shadow Protection
            if db.shadowProtect then
                local hasSP = UnitHasBuff(unit, BUFF_NAMES.SHADOW_PROT)
                             or UnitHasBuff(unit, BUFF_NAMES.SHADOW_RAID)
                if not hasSP then
                    tinsert(queue, { unit = unit, spell = SPELLS.SHADOW_PROT.single, name = "Shadow Protection" })
                end
            end

            -- Inner Fire (self only)
            if db.innerFire and isSelf then
                if not SelfHasInnerFire() then
                    tinsert(queue, { unit = "player", spell = SPELLS.INNER_FIRE.single, name = "Inner Fire" })
                end
            end

            -- Touch of Weakness (self only)
            if db.touchWeakness and isSelf then
                if not SelfHasTouchOfWeakness() then
                    tinsert(queue, { unit = "player", spell = SPELLS.TOUCH_WEAKNESS.single, name = "Touch of Weakness" })
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Cast next spell in queue
-- ---------------------------------------------------------------------------
local function CastNext()
    if #queue == 0 then
        casting = false
        return
    end
    -- Don't cast in combat for group buffs (Inner Fire / Touch OK in combat)
    local entry = tremove(queue, 1)
    if not entry then casting = false; return end

    if UnitExists(entry.unit) then
        CastSpellByID(entry.spell, entry.unit)
    end
    casting = false
end

-- ---------------------------------------------------------------------------
-- OnUpdate: periodic scan
-- ---------------------------------------------------------------------------
buffFrame:SetScript("OnUpdate", function(self, elapsed)
    if not DecursivePlusBuffDB.enabled then return end
    lastScan = lastScan + elapsed
    if lastScan < DecursivePlusBuffDB.scanInterval then return end
    lastScan = 0

    -- Only scan when out of combat for safety
    if InCombatLockdown() then return end

    BuildQueue()
    if #queue > 0 and not casting then
        casting = true
        CastNext()
    end
end)

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------
buffFrame:RegisterEvent("ADDON_LOADED")
buffFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- left combat

buffFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Ensure saved vars exist
        if not DecursivePlusBuffDB then
            DecursivePlusBuffDB = {
                enabled       = true,
                fortitude     = true,
                shadowProtect = true,
                innerFire     = true,
                touchWeakness = true,
                selfOnly      = false,
                scanInterval  = 5,
            }
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Buff system loaded. Type /dcrplus for options.")
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Just left combat - trigger an immediate scan
        lastScan = DecursivePlusBuffDB.scanInterval
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands  /dcrplus
-- ---------------------------------------------------------------------------
SLASH_DCRPLUS1 = "/dcrplus"
SlashCmdList["DCRPLUS"] = function(msg)
    local db  = DecursivePlusBuffDB
    local cmd = strtrim(msg):lower()

    if cmd == "" or cmd == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus] Commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus toggle       - enable/disable buff scanning")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus fort         - toggle Power Word: Fortitude")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus shadow       - toggle Shadow Protection")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus innerfire    - toggle Inner Fire (self)")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus weakness     - toggle Touch of Weakness (self)")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus selfonly     - toggle self-only mode")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus status       - show current settings")
        DEFAULT_CHAT_FRAME:AddMessage("  /dcrplus scan         - trigger immediate buff scan")
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Buff scanning: " .. (db.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "fort" then
        db.fortitude = not db.fortitude
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Power Word: Fortitude: " .. (db.fortitude and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "shadow" then
        db.shadowProtect = not db.shadowProtect
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Shadow Protection: " .. (db.shadowProtect and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "innerfire" then
        db.innerFire = not db.innerFire
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Inner Fire: " .. (db.innerFire and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "weakness" then
        db.touchWeakness = not db.touchWeakness
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Touch of Weakness: " .. (db.touchWeakness and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "selfonly" then
        db.selfOnly = not db.selfOnly
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Self-only mode: " .. (db.selfOnly and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus] Current Settings:|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: "       .. (db.enabled       and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Fortitude: "     .. (db.fortitude     and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Shadow Prot: "   .. (db.shadowProtect and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Inner Fire: "    .. (db.innerFire     and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Touch Weakness: " .. (db.touchWeakness and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Self-only: "     .. (db.selfOnly      and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        DEFAULT_CHAT_FRAME:AddMessage("  Scan interval: " .. db.scanInterval .. "s")
    elseif cmd == "scan" then
        if InCombatLockdown() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Cannot scan while in combat.")
        else
            BuildQueue()
            if #queue > 0 then
                casting = true
                CastNext()
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Scanning buffs... " .. #queue .. " buff(s) needed.")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r All buffs are up!")
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DecursivePlus]|r Unknown command. Type /dcrplus help")
    end
end
