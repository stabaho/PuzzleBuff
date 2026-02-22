--[[
    Dcr_Buffs.lua - Part of PuzzleBuff
    Integrates Priest buff casting into Decursive's Micro Unit Frames (MUFs).

    Behavior:
      - When a unit has NO debuffs (NORMAL status), the MUF box is colored
        to indicate the highest-priority missing buff:
            Light Blue  = Power Word: Fortitude missing
            Purple      = Shadow Protection missing
            Gold        = Inner Fire missing (self only)
            Green       = Touch of Weakness missing (self only)
            Gray        = All buffs present (normal Decursive gray)

      - RIGHT-CLICK on a colored MUF casts the indicated buff on that unit.
        Each right-click casts one buff.  The box re-colors to the next
        missing buff immediately after, then goes gray when all are up.

      - LEFT-CLICK retains all normal Decursive debuff-cure behavior.

    This file hooks into MicroUnitF.prototype.SetColor (post-hook) and
    MicroUnitF.prototype.OnPreClick to intercept right-clicks on NORMAL
    (no-debuff) units.
--]]

local addonName, T = ...;
T._LoadedFiles = T._LoadedFiles or {};
T._LoadedFiles["Dcr_Buffs.lua"] = false;

-- Wait until Decursive's core objects exist before hooking
local waitFrame = CreateFrame("Frame");
waitFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
waitFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD");
    self:SetScript("OnEvent", nil);

    -- Verify the objects we need exist
    if not (T and T.Dcr and T.Dcr.MicroUnitF and T.Dcr.MicroUnitF.prototype) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[PuzzleBuff]|r ERROR: Decursive core not found. Buff system disabled.");
        return;
    end

    PuzzleBuff_Buffs_Init();
end);

-- ============================================================
-- SPELL DEFINITIONS
-- ============================================================
-- Spell IDs for TBC Classic
-- Priority order: Fort > Shadow Resist > Inner Fire > Touch of Weakness
local BUFF_SPELLS = {
    -- [1] Power Word: Fortitude  -> light blue
    {
        name       = "Power Word: Fortitude",
        spellId    = 25389,          -- Rank 7 single-target TBC
        buffNames  = { "Power Word: Fortitude", "Prayer of Fortitude" },
        selfOnly   = false,
        color      = { 0.45, 0.75, 1.00, 1 }, -- light blue
    },
    -- [2] Shadow Protection  -> purple
    {
        name       = "Shadow Protection",
        spellId    = 25433,          -- Rank 3 single-target TBC
        buffNames  = { "Shadow Protection", "Prayer of Shadow Protection" },
        selfOnly   = false,
        color      = { 0.70, 0.25, 1.00, 1 }, -- purple
    },
    -- [3] Inner Fire  -> gold
    {
        name       = "Inner Fire",
        spellId    = 25431,          -- Rank 7 TBC
        buffNames  = { "Inner Fire" },
        selfOnly   = true,
        color      = { 1.00, 0.80, 0.10, 1 }, -- gold
    },
    -- [4] Touch of Weakness  -> green
    {
        name       = "Touch of Weakness",
        spellId    = 25461,          -- Rank 6 TBC
        buffNames  = { "Touch of Weakness" },
        selfOnly   = true,
        color      = { 0.20, 0.90, 0.20, 1 }, -- green
    },
};

-- ============================================================
-- HELPERS
-- ============================================================
local function UnitHasAnyBuff(unit, nameList)
    for i = 1, 40 do
        local name = UnitBuff(unit, i);
        if not name then break; end
        for _, buffName in ipairs(nameList) do
            if name == buffName then return true; end
        end
    end
    return false;
end

-- Returns the first BUFF_SPELLS entry that the unit is missing,
-- respecting selfOnly restriction.  Returns nil if all buffs present.
local function GetFirstMissingBuff(unit)
    local isSelf = UnitIsUnit(unit, "player");
    for _, buff in ipairs(BUFF_SPELLS) do
        if not buff.selfOnly or isSelf then
            if not UnitHasAnyBuff(unit, buff.buffNames) then
                return buff;
            end
        end
    end
    return nil;
end

-- ============================================================
-- CORE INIT  (runs after PLAYER_ENTERING_WORLD)
-- ============================================================
function PuzzleBuff_Buffs_Init()
    local D   = T.Dcr;
    local MUF = D.MicroUnitF;
    local proto = MUF.prototype;

    -- ----------------------------------------------------------
    -- POST-HOOK  MicroUnitF.prototype:SetColor
    -- After Decursive sets the MUF color, if the unit is NORMAL
    -- (no debuffs) we override the color based on missing buffs.
    -- ----------------------------------------------------------
    local orig_SetColor = proto.SetColor;
    proto.SetColor = function(self)
        local result = orig_SetColor(self);  -- run original first

        -- Only recolor when Decursive thinks the unit is NORMAL
        local DC = T._C;
        if self.UnitStatus == DC.NORMAL and UnitExists(self.CurrUnit) then
            local missing = GetFirstMissingBuff(self.CurrUnit);
            if missing then
                -- Override the main texture color
                local c = missing.color;
                local alpha = D.profile.DebuffsFrameElemAlpha or 1;
                self.Texture:SetColorTexture(c[1], c[2], c[3], alpha);
                -- Tag this MUF so right-click knows what to cast
                self._puzzlebuff_buff = missing;
            else
                -- All buffs present: clear tag
                self._puzzlebuff_buff = nil;
            end
        else
            -- Not NORMAL status: clear tag so right-click falls through
            self._puzzlebuff_buff = nil;
        end

        return result;
    end;

    -- ----------------------------------------------------------
    -- HOOK  MicroUnitF:OnPreClick
    -- Intercept right-clicks when the unit has a pending buff.
    -- ----------------------------------------------------------
    local orig_OnPreClick = MUF.OnPreClick;
    MUF.OnPreClick = function(frame, Button)
        local muf = frame.Object;

        -- Only intercept right-click on a NORMAL unit with a pending buff
        if Button == "RightButton"
           and muf
           and muf._puzzlebuff_buff
           and not InCombatLockdown() then

            local buff = muf._puzzlebuff_buff;
            local unit = muf.CurrUnit;

            -- Cast the spell
            CastSpellByName(buff.name, unit);

            -- Force a re-check of this MUF's color after cast lands
            C_Timer.After(0.5, function()
                if muf and muf.CurrUnit then
                    muf:Update(false, false, false);
                end
            end);

            -- Do NOT call the original; we handled it
            return;
        end

        -- Fall through to original Decursive click handling
        return orig_OnPreClick(frame, Button);
    end;

    -- ----------------------------------------------------------
    -- Periodic refresh: re-evaluate buff colors every 3s
    -- so boxes update even without clicking (e.g. buff expires).
    -- ----------------------------------------------------------
    local ticker = CreateFrame("Frame");
    local elapsed_acc = 0;
    ticker:SetScript("OnUpdate", function(self, elapsed)
        elapsed_acc = elapsed_acc + elapsed;
        if elapsed_acc < 3 then return; end
        elapsed_acc = 0;

        for unit, muf in pairs(MUF.ExistingPerUNIT) do
            if muf and muf.Shown then
                muf:Update(false, true); -- skip debuff rescan, just recolor
            end
        end
    end);

    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[PuzzleBuff]|r Buff system active. Right-click MUFs to cast missing Priest buffs.");
    T._LoadedFiles["Dcr_Buffs.lua"] = "2.7.34-plus";
end
