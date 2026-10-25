--[[
    CCS_ScannerProbe — throwaway diagnostic mod.

    Known live scanner UI class hierarchy (found via earlier probe runs):

        W_ScanObjectsOverlay_C (root, lives on the GameInstance)
          -> ScanObjectsResult : W_ScanObjectsResultWindow_C
              -> "New Scan Result" : struct S_ScanResult   <-- the real data
              -> DenominationCounters : W_ScanCurrencyList_C
                  -> N x W_ScanCurrencyIcon_C (Label/Counter text, display only)
              -> N x W_ScanObjectsResultEntry_C

    This mod finds live instances of the known widget classes AND reads the
    "New Scan Result" (S_ScanResult struct) value off the result window,
    recursively dumping nested structs/arrays (bounded depth), so we can see
    the real backing data instead of scraping on-screen text.

    Press F9 in-game after triggering an area scan. Output files land next
    to the game executable, i.e. Binaries\\Win64\\ccs_dump_*.txt (confirmed
    empirically — NOT Binaries\\Win64\\ue4ss\\, despite UE4SS.log's reported
    "working directory").

    This mod does not modify any game state; it only reads and writes its
    own diagnostic files.
]]

local MOD = "CCS_ScannerProbe"
local MAX_DEPTH = 4
local MAX_ARRAY_ELEMENTS = 5

local function log(msg)
    print(string.format("[%s] %s", MOD, msg))
end

local function fullNameOf(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok then return name end
    return "<unknown fullname>"
end

local function isValid(obj)
    local ok, valid = pcall(function()
        return obj ~= nil and obj.IsValid and obj:IsValid()
    end)
    return ok and valid
end

local describeProperty -- forward decl (recursive: struct/array expansion)

local function indentStr(depth)
    return string.rep("  ", depth + 1)
end

-- Appends one or more lines describing Property's value on Object into `lines`.
-- Recurses into StructProperty and array-of-struct elements up to MAX_DEPTH.
describeProperty = function(Object, Property, lines, depth)
    local propClassName = "?"
    pcall(function() propClassName = Property:GetClass():GetFName():ToString() end)
    local propName = "?"
    pcall(function() propName = Property:GetFName():ToString() end)
    local prefix = indentStr(depth) .. propClassName .. " " .. propName .. " = "

    local ok = pcall(function()
        if Property:IsA(PropertyTypes.Int8Property)
            or Property:IsA(PropertyTypes.Int16Property)
            or Property:IsA(PropertyTypes.IntProperty)
            or Property:IsA(PropertyTypes.Int64Property)
            or Property:IsA(PropertyTypes.FloatProperty)
            or Property:IsA(PropertyTypes.ByteProperty) then
            lines[#lines + 1] = prefix .. tostring(Object[propName])
        elseif Property:IsA(PropertyTypes.NameProperty) then
            lines[#lines + 1] = prefix .. Object[propName]:ToString()
        elseif Property:IsA(PropertyTypes.StrProperty) then
            lines[#lines + 1] = prefix .. Object[propName]:ToString()
        elseif Property:IsA(PropertyTypes.TextProperty) then
            lines[#lines + 1] = prefix .. Object[propName]:ToString()
        elseif Property:IsA(PropertyTypes.BoolProperty) then
            lines[#lines + 1] = prefix .. (Object[propName] and "True" or "False")
        elseif Property:IsA(PropertyTypes.EnumProperty) then
            local Value = Object[propName]
            local okEnum, enumName = pcall(function() return Property:GetEnum():GetNameByValue(Value):ToString() end)
            lines[#lines + 1] = prefix .. string.format("%s(%s)", okEnum and enumName or "?", tostring(Value))
        elseif Property:IsA(PropertyTypes.ArrayProperty) then
            local Value = Object[propName]
            local num = Value:GetArrayNum()
            lines[#lines + 1] = prefix .. string.format("<array, %d/%d elements>", num, Value:GetArrayMax())
            local Inner = Property:GetInner()
            if num > 0 and depth < MAX_DEPTH then
                if Inner:IsA(PropertyTypes.ObjectProperty) then
                    local shown = 0
                    Value:ForEach(function(Index, Elem)
                        if shown >= MAX_ARRAY_ELEMENTS then return end
                        shown = shown + 1
                        local okElem, name = pcall(function() return Elem:get():GetFullName() end)
                        lines[#lines + 1] = indentStr(depth + 1) .. string.format("[%d] = %s", Index - 1, okElem and name or "?")
                    end)
                elseif Inner:IsA(PropertyTypes.StructProperty) then
                    local innerStructType = Inner:GetStruct()
                    local shown = 0
                    Value:ForEach(function(Index, Elem)
                        if shown >= MAX_ARRAY_ELEMENTS then return end
                        shown = shown + 1
                        lines[#lines + 1] = indentStr(depth + 1) .. string.format("[%d] (%s):", Index - 1, innerStructType:GetFName():ToString())
                        innerStructType:ForEachProperty(function(innerProp)
                            describeProperty(Elem, innerProp, lines, depth + 2)
                        end)
                    end)
                else
                    local shown = 0
                    Value:ForEach(function(Index, Elem)
                        if shown >= MAX_ARRAY_ELEMENTS then return end
                        shown = shown + 1
                        local okElem, s = pcall(function() return tostring(Elem) end)
                        lines[#lines + 1] = indentStr(depth + 1) .. string.format("[%d] = %s", Index - 1, okElem and s or "?")
                    end)
                end
            end
        elseif Property:IsA(PropertyTypes.StructProperty) then
            local Value = Object[propName]
            local structType = Property:GetStruct()
            local okName, sname = pcall(function() return structType:GetFName():ToString() end)
            lines[#lines + 1] = prefix .. "<struct " .. (okName and sname or "?") .. ">"
            if depth < MAX_DEPTH then
                structType:ForEachProperty(function(innerProp)
                    describeProperty(Value, innerProp, lines, depth + 1)
                end)
            end
        elseif Property:IsA(PropertyTypes.ObjectProperty) then
            local Value = Object[propName]
            if Value and Value.GetFullName then
                lines[#lines + 1] = prefix .. Value:GetFullName()
            else
                lines[#lines + 1] = prefix .. "<null>"
            end
        elseif Property:IsA(PropertyTypes.MapProperty) then
            local Value = Object[propName]
            local okKeyP, keyProp = pcall(function() return Property:GetKeyProp() end)
            local okValP, valProp = pcall(function() return Property:GetValueProp() end)
            local keyPropClass = (okKeyP and pcall(function() return keyProp:GetClass():GetFName():ToString() end) and keyProp:GetClass():GetFName():ToString()) or "?"
            local valPropClass = (okValP and pcall(function() return valProp:GetClass():GetFName():ToString() end) and valProp:GetClass():GetFName():ToString()) or "?"
            local okNum, num = pcall(function() return Value:Num() end)
            lines[#lines + 1] = prefix .. string.format("<map, key=%s value=%s, num=%s>",
                keyPropClass, valPropClass, okNum and tostring(num) or "?")

            -- Try every enumeration method we might plausibly have in this UE4SS build.
            local enumerated = false
            if depth < MAX_DEPTH then
                local function stringifyAny(x)
                    local tries = {
                        function() return x:ToString() end,
                        function() return x.TagName:ToString() end,
                        function() return x:GetFName():ToString() end,
                        function() return x:GetName() end,
                        function() return tostring(x.Value) end,
                        function() return x:get() end,
                        function() return tostring(x) end,
                    }
                    for i, fn in ipairs(tries) do
                        local okTry, result = pcall(fn)
                        if okTry and result ~= nil then
                            return tostring(result) .. " [via try#" .. i .. "]"
                        end
                    end
                    return "<unresolved>"
                end

                local okForEach = pcall(function()
                    Value:ForEach(function(k, v)
                        enumerated = true
                        local okKs, ks = pcall(stringifyAny, k)
                        local okVs, vs = pcall(stringifyAny, v)
                        lines[#lines + 1] = indentStr(depth + 1) .. string.format("%s -> %s",
                            okKs and ks or "<key err>", okVs and vs or "<val err>")
                    end)
                end)
                if not okForEach and not enumerated then
                    lines[#lines + 1] = indentStr(depth + 1) .. "<ForEach not available/failed on this map>"
                end
            end
        else
            lines[#lines + 1] = prefix .. "<unhandled property kind>"
        end
    end)
    if not ok then
        lines[#lines + 1] = prefix .. "<error reading value>"
    end
end

local function dumpObjectToLines(obj, lines)
    lines[#lines + 1] = string.format("*** Property dump for '%s' ***", fullNameOf(obj))
    local class = nil
    local okClass = pcall(function() class = obj:GetClass() end)
    if not okClass or not class or not class:IsValid() then
        lines[#lines + 1] = "<could not resolve class>"
        return
    end
    while class and class:IsValid() do
        lines[#lines + 1] = string.format("=== %s ===", class:GetFullName())
        class:ForEachProperty(function(Property)
            local okLine = pcall(describeProperty, obj, Property, lines, 0)
            if not okLine then lines[#lines + 1] = "  <error describing property>" end
        end)
        local okSuper, super = pcall(function() return class:GetSuperStruct() end)
        class = okSuper and super or nil
    end
end

local function writeLines(filename, lines)
    local ok, err = pcall(function()
        local f = io.open(filename, "w+")
        if not f then error("io.open failed") end
        f:write(table.concat(lines, "\n"))
        f:close()
    end)
    return ok, err
end

local TARGET_CLASSES = {
    "W_ScanObjectsOverlay_C",
    "W_ScanObjectsResultWindow_C",
    "W_ScanCurrencyList_C",
    "W_ScanCurrencyIcon_C",
    "W_ScanObjectsResultEntry_C",
}

-- Among live (non-CDO) instances of className, prefer one with a non-nil
-- WidgetTree: we've seen duplicate/stale instances (e.g. a previous or
-- not-yet-initialized copy) whose WidgetTree is nil, while the one actually
-- driving the on-screen UI has it populated.
local function firstNonCdoInstance(className)
    local ok, found = pcall(function() return FindAllOf(className) end)
    if not ok or not found then return nil, 0 end
    local count = 0
    local first = nil
    local bestWithTree = nil
    for _, inst in ipairs(found) do
        if isValid(inst) and not fullNameOf(inst):find("Default__", 1, true) then
            count = count + 1
            if not first then first = inst end
            if not bestWithTree then
                local okTree, tree = pcall(function() return inst.WidgetTree end)
                if okTree and tree ~= nil and isValid(tree) then
                    bestWithTree = inst
                end
            end
        end
    end
    return bestWithTree or first, count
end

local function dumpScanResultStruct(resultWindow, lines)
    lines[#lines + 1] = "*** 'New Scan Result' struct value on W_ScanObjectsResultWindow_C ***"
    local okVal, structVal = pcall(function() return resultWindow["New Scan Result"] end)
    if not okVal or structVal == nil then
        lines[#lines + 1] = "<could not read 'New Scan Result' property: " .. tostring(structVal) .. ">"
        return
    end
    local okType, structType = pcall(function()
        return StaticFindObject("/Game/Core/Player/Character/Scan/S_ScanResult.S_ScanResult")
    end)
    if not okType or not structType or not structType:IsValid() then
        lines[#lines + 1] = "<could not resolve S_ScanResult struct type>"
        return
    end
    lines[#lines + 1] = string.format("=== %s ===", structType:GetFullName())
    structType:ForEachProperty(function(Property)
        local okLine = pcall(describeProperty, structVal, Property, lines, 0)
        if not okLine then lines[#lines + 1] = "  <error describing property>" end
    end)
end

local function probe()
    local ok, err = pcall(function()
        log("=== CCS_ScannerProbe dump run ===")

        for _, className in ipairs(TARGET_CLASSES) do
            local inst, count = firstNonCdoInstance(className)
            if not inst then
                log(string.format("  %s: no live instance found (count=%d)", className, count))
            else
                local lines = {}
                dumpObjectToLines(inst, lines)
                local filename = "ccs_dump_" .. className .. ".txt"
                local wok, werr = writeLines(filename, lines)
                if wok then
                    log(string.format("  %s: %d instance(s) found, dumped first one -> %s (%d lines)",
                        className, count, filename, #lines))
                else
                    log(string.format("  %s: found %d instance(s) but FAILED to write %s: %s",
                        className, count, filename, tostring(werr)))
                end
            end
        end

        local resultWindow = select(1, firstNonCdoInstance("W_ScanObjectsResultWindow_C"))
        if resultWindow then
            local lines = {}
            dumpScanResultStruct(resultWindow, lines)
            local wok, werr = writeLines("ccs_dump_S_ScanResult.txt", lines)
            if wok then
                log(string.format("  S_ScanResult: dumped -> ccs_dump_S_ScanResult.txt (%d lines)", #lines))
            else
                log("  S_ScanResult: FAILED to write: " .. tostring(werr))
            end
        else
            log("  S_ScanResult: no W_ScanObjectsResultWindow_C instance found")
        end

-- Walk GetOuter() to find the nearest ancestor of a given class name.
local function findAncestorOfClass(obj, className, maxDepth)
    local current = obj
    for _ = 1, maxDepth do
        if not current or not isValid(current) then return nil end
        local okClass, cname = pcall(function() return current:GetClass():GetFName():ToString() end)
        if okClass and cname == className then return current end
        local okOuter, outer = pcall(function() return current:GetOuter() end)
        if not okOuter then return nil end
        current = outer
    end
    return nil
end

        -- Read currency/denomination + count directly off every visible
        -- W_ScanCurrencyIcon_C's Label/Counter TextBlocks. This sidesteps
        -- the TMap key-reading problem entirely (ForEach only gives us
        -- opaque param wrappers for the denomination key, not a usable tag).
        -- Also dumps every candidate "is this still actually displayed"
        -- signal (Slot, GetParent(), ancestor chain + ids) since Visibility
        -- alone does NOT distinguish a stale icon from a previous scan
        -- (orphaned icons keep whatever Visibility they had).
        do
            local okFind, icons = pcall(function() return FindAllOf("W_ScanCurrencyIcon_C") end)
            local lines = {}
            if okFind and icons then
                lines[#lines + 1] = string.format("total W_ScanCurrencyIcon_C instances: %d", #icons)
                for i, icon in ipairs(icons) do
                    if isValid(icon) and not fullNameOf(icon):find("Default__", 1, true) then
                        local okVis, vis = pcall(function()
                            return tostring(icon.Visibility)
                        end)
                        local okLabel, labelTxt = pcall(function()
                            return icon.Label:GetText():ToString()
                        end)
                        local okCounter, counterTxt = pcall(function()
                            return icon.Counter:GetText():ToString()
                        end)
                        local okSlot, slotDesc = pcall(function()
                            local s = icon.Slot
                            if s == nil then return "nil" end
                            local okFn, fn = pcall(function() return s:GetFullName() end)
                            return okFn and fn or "<non-nil, unreadable>"
                        end)
                        local okParent, parentDesc = pcall(function()
                            local p = icon:GetParent()
                            if p == nil or not isValid(p) then return "nil" end
                            return fullNameOf(p)
                        end)
                        local listAncestor = findAncestorOfClass(icon, "W_ScanCurrencyList_C", 10)
                        local windowAncestor = findAncestorOfClass(icon, "W_ScanObjectsResultWindow_C", 10)
                        local overlayAncestor = findAncestorOfClass(icon, "W_ScanObjectsOverlay_C", 10)
                        lines[#lines + 1] = string.format(
                            "[%d] %s\n     visibility=%s | label=%s | counter=%s\n     Slot=%s | GetParent()=%s\n     ancestor(List)=%s | ancestor(Window)=%s | ancestor(Overlay)=%s",
                            i,
                            fullNameOf(icon),
                            okVis and vis or "<err>",
                            okLabel and ("'" .. labelTxt .. "'") or "<err>",
                            okCounter and ("'" .. counterTxt .. "'") or "<err>",
                            okSlot and slotDesc or "<err>",
                            okParent and parentDesc or "<err (no GetParent?)>",
                            listAncestor and fullNameOf(listAncestor) or "<none>",
                            windowAncestor and fullNameOf(windowAncestor) or "<none>",
                            overlayAncestor and fullNameOf(overlayAncestor) or "<none>")
                    end
                end
            else
                lines[#lines + 1] = "FindAllOf(\"W_ScanCurrencyIcon_C\") failed"
            end
            local wok, werr = writeLines("ccs_dump_icons_summary.txt", lines)
            if wok then
                log(string.format("  icons summary -> ccs_dump_icons_summary.txt (%d lines)", #lines))
            else
                log("  icons summary: FAILED to write: " .. tostring(werr))
            end
        end

        log("=== Done. Files are next to the game .exe, in Binaries\\Win64\\ ===")
    end)

    if not ok then
        log("ERROR during probe: " .. tostring(err))
    end
end

RegisterKeyBindAsync(Key.F9, {}, probe)
log("Loaded (v3 - dumps S_ScanResult struct + widgets). Trigger an area scan, then press F9.")
