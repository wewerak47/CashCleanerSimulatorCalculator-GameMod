--[[
    CCS_ScanExport

    On a keypress, reads the currently displayed "Area scan result" panel
    (the game's built-in cash scanner) and copies a compact, plain-text
    breakdown of bill counts per currency/denomination to the Windows
    clipboard, for pasting into the companion web calculator.

    Data source: live W_ScanCurrencyIcon_C widget instances
    (/Game/Core/UI/HUD/ScanObjects/W_ScanCurrencyIcon), each with a `Label`
    TextBlock (e.g. "$100", "\xC2\xA5" .. "10K") and a `Counter` TextBlock
    (e.g. "26,800") — found via CCS_ScannerProbe. We read the two text
    blocks directly rather than the backing S_ScanResult struct's
    DenominationToBillNum TMap, because TMap key enumeration doesn't expose
    usable values in this UE4SS build (ForEach only yields opaque param
    wrapper objects for the key).

    Output clipboard format ("CCS-SCAN v1"):
        CCS-SCAN v1
        USD 100 x26800
        USD 50 x14900
        ...
    One line per visible denomination tile. Values are raw bill counts
    (not bundles).

    Clipboard is set via the Windows `clip` command over io.popen — UE4SS's
    Lua sandbox exposes the standard `io`/`os` libraries, but there is no
    built-in clipboard/HTTP API, so shelling out is the simplest path that
    needs no native companion DLL.
]]

local MOD = "CCS_ScanExport"

local function log(msg)
    print(string.format("[%s] %s", MOD, msg))
end

local function isValid(obj)
    local ok, valid = pcall(function()
        return obj ~= nil and obj.IsValid and obj:IsValid()
    end)
    return ok and valid
end

local function fullNameOf(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok then return name end
    return "<unknown>"
end

local SYMBOL_TO_CURRENCY = {
    ["$"] = "USD",
    ["\xE2\x82\xAC"] = "EUR", -- €
    ["\xC2\xA5"] = "JPY",     -- ¥
    ["\xC2\xA3"] = "GBP",     -- £
}

-- "$100" -> "USD", 100 | "\xC2\xA510K" -> "JPY", 10000 | "$.50" -> "USD", 0.5
local function parseLabel(label)
    if type(label) ~= "string" then return nil, nil end
    for symbol, currency in pairs(SYMBOL_TO_CURRENCY) do
        if label:sub(1, #symbol) == symbol then
            local rest = label:sub(#symbol + 1)
            local kAmount = rest:match("^(%d+)K$")
            if kAmount then
                return currency, tonumber(kAmount) * 1000
            end
            local cents = rest:match("^%.(%d+)$")
            if cents then
                return currency, tonumber("0." .. cents)
            end
            local plain = rest:match("^(%d+)$")
            if plain then
                return currency, tonumber(plain)
            end
            return currency, nil
        end
    end
    return nil, nil
end

-- "26,800" -> 26800
local function parseCounter(counter)
    if type(counter) ~= "string" then return nil end
    local digitsOnly = counter:gsub("[^%d]", "")
    if digitsOnly == "" then return nil end
    return tonumber(digitsOnly)
end

local function collectScanEntries()
    local entries = {}
    local okFind, icons = pcall(function() return FindAllOf("W_ScanCurrencyIcon_C") end)
    if not okFind or not icons then
        return entries, "FindAllOf(\"W_ScanCurrencyIcon_C\") failed"
    end

    -- The game never destroys a scan result's icon widgets when a new scan
    -- replaces it on screen — it just detaches them from their WrapBox
    -- panel. Detached (stale) icons keep Visibility=SelfHitTestInvisible
    -- (so Visibility alone can't tell them apart) but GetParent() goes nil
    -- once removed from the panel, while still-attached (current) icons
    -- report their WrapBox as parent. So GetParent() ~= nil is the reliable
    -- "is this actually part of the current result" signal — confirmed via
    -- CCS_ScannerProbe: stale icons had Slot=<non-nil, unreadable> and
    -- GetParent()=nil; live ones had a real WrapBoxSlot + WrapBox parent.
    for _, icon in ipairs(icons) do
        if isValid(icon) and not fullNameOf(icon):find("Default__", 1, true) then
            local okParent, parent = pcall(function() return icon:GetParent() end)
            if okParent and isValid(parent) then
                local okLabel, labelTxt = pcall(function() return icon.Label:GetText():ToString() end)
                local okCounter, counterTxt = pcall(function() return icon.Counter:GetText():ToString() end)
                if okLabel and okCounter then
                    local currency, denom = parseLabel(labelTxt)
                    local count = parseCounter(counterTxt)
                    if currency and denom and count then
                        entries[#entries + 1] = { currency = currency, denom = denom, count = count }
                    else
                        log(string.format("  could not parse tile: label=%s counter=%s", tostring(labelTxt), tostring(counterTxt)))
                    end
                end
            end
        end
    end

    return entries, nil
end

local function formatEntries(entries)
    local lines = { "CCS-SCAN v1" }
    for _, e in ipairs(entries) do
        -- e.denom may be a whole number (100) or fractional coin value (0.5, 0.25) —
        -- tostring() renders both correctly without forcing a %d truncation.
        lines[#lines + 1] = string.format("%s %s x%d", e.currency, tostring(e.denom), e.count)
    end
    return table.concat(lines, "\n")
end

local function copyToClipboard(text)
    local ok, err = pcall(function()
        local p = io.popen("clip", "w")
        if not p then error("io.popen('clip') failed") end
        p:write(text)
        p:close()
    end)
    return ok, err
end

local function exportScan()
    local ok, err = pcall(function()
        local entries, findErr = collectScanEntries()
        if findErr then
            log("ERROR: " .. findErr)
            return
        end
        if #entries == 0 then
            log("No scan result tiles found/visible right now — open an area scan result first.")
            return
        end

        local text = formatEntries(entries)
        local copyOk, copyErr = copyToClipboard(text)
        if copyOk then
            log(string.format("Copied %d denomination(s) to clipboard.", #entries))
        else
            log("Copied to internal buffer but clipboard write FAILED: " .. tostring(copyErr))
            log("Data was:\n" .. text)
        end
    end)
    if not ok then
        log("ERROR during export: " .. tostring(err))
    end
end

RegisterKeyBindAsync(Key.F8, {}, exportScan)
log("Loaded. Open an area scan result, then press F8 to copy the cash breakdown to the clipboard.")
