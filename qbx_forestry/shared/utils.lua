-----------------------------------------------------------
-- SHARED: UTILITY FUNCTIONS
-- Available to both client and server contexts.
-----------------------------------------------------------

ForestryUtils = {}

-----------------------------------------------------------
-- TREE KEY: Composite identifier for individual trees.
-- Format: "modelHash:x.x:y.y:z.z" (1 decimal precision)
-----------------------------------------------------------
---@param modelHash number
---@param coords vector3
---@return string
function ForestryUtils.TreeKey(modelHash, coords)
    return ('%d:%.1f:%.1f:%.1f'):format(modelHash, coords.x, coords.y, coords.z)
end

-----------------------------------------------------------
-- XP FOR LEVEL: XP cost to advance from (level-1) to level.
-- Formula: floor(XPPerLevel * level ^ XPFormula)
-----------------------------------------------------------
---@param level number
---@return number
function ForestryUtils.XPForLevel(level)
    if level <= 0 then return 0 end
    return math.floor(Config.Progression.XPPerLevel * (level ^ Config.Progression.XPFormula))
end

-----------------------------------------------------------
-- LEVEL FROM XP: Highest level reachable with totalXP.
-- Cumulative cost: sum of XPForLevel(1..level).
-----------------------------------------------------------
---@param totalXP number
---@param maxLevel number
---@return number
function ForestryUtils.LevelFromXP(totalXP, maxLevel)
    local level = 0
    local cumulative = 0
    for l = 1, maxLevel do
        cumulative = cumulative + ForestryUtils.XPForLevel(l)
        if cumulative > totalXP then break end
        level = l
    end
    return level
end

-----------------------------------------------------------
-- SPECIES FROM MODEL: Reverse lookup via Config.ModelToSpecies.
-----------------------------------------------------------
---@param modelHash number
---@return string? speciesKey
---@return table? speciesData
function ForestryUtils.GetSpeciesFromModel(modelHash)
    local speciesKey = Config.ModelToSpecies[modelHash]
    if not speciesKey then return nil, nil end
    return speciesKey, Config.TreeSpecies[speciesKey]
end

-----------------------------------------------------------
-- CAN TOOL FELL SIZE: Check if tool handles given tree size.
-----------------------------------------------------------
---@param toolName string
---@param treeSize string
---@return boolean
function ForestryUtils.CanToolFellSize(toolName, treeSize)
    local toolData = Config.Tools[toolName]
    if not toolData then return false end
    return toolData.treeSizes[treeSize] == true
end

-----------------------------------------------------------
-- GET FELLING SKILL CHECK: Pattern for given tree size.
-----------------------------------------------------------
---@param treeSize string
---@return table
function ForestryUtils.GetFellingSkillCheck(treeSize)
    return Config.SkillCheck[treeSize] or {}
end

-----------------------------------------------------------
-- GET FALL DIRECTION: Tree falls away from player (XY plane).
-----------------------------------------------------------
---@param playerPos vector3
---@param treePos vector3
---@return vector3 normalized direction
function ForestryUtils.GetFallDirection(playerPos, treePos)
    local dir = treePos - playerPos
    dir = vec3(dir.x, dir.y, 0.0)
    local len = #dir
    if len < 0.01 then return vec3(1.0, 0.0, 0.0) end
    return dir / len
end

-----------------------------------------------------------
-- DIRECTION TO HEADING: Convert direction vec to GTA heading.
-- GTA heading: 0=North, 90=West, 180=South, 270=East.
-----------------------------------------------------------
---@param direction vector3
---@return number heading (0-360)
function ForestryUtils.DirectionToHeading(direction)
    return math.deg(math.atan(direction.x, direction.y)) % 360.0
end

-----------------------------------------------------------
-- DISTANCE TO LINE SEGMENT: Perpendicular distance from
-- point P to line segment AB. Used for crush zone checks.
-----------------------------------------------------------
---@param point vector3
---@param a vector3 segment start
---@param b vector3 segment end
---@return number distance
function ForestryUtils.DistanceToLineSegment(point, a, b)
    local ab = b - a
    local ap = point - a

    local abLenSq = ab.x * ab.x + ab.y * ab.y
    if ab.z then abLenSq = abLenSq + ab.z * ab.z end

    if abLenSq < 0.0001 then return #(point - a) end

    local dot = ap.x * ab.x + ap.y * ab.y
    if ab.z and ap.z then dot = dot + ap.z * ab.z end

    local t = math.max(0.0, math.min(1.0, dot / abLenSq))
    local closest = a + ab * t
    return #(point - closest)
end
