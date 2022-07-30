--------------------------------settings

local maxInventory = 0.8
local minEnergy = 0.4
local minDurability = 0.4
local startMiningPos = -32 --все каординаты относительно базы робота
local maxMiningPos = -20
local toolnames = {"pickaxe"}
local port = 573

--------------------------------boot

local component = component
local computer = computer
local unicode = unicode

local robot = component.proxy(component.list("robot")())
robot.setLightColor(0xFFFFFF)
local geo = component.proxy(component.list("geolyzer")())
local modem = component.proxy(component.list("modem")() or "")
local rs = component.proxy(component.list("redstone")() or "")
local inv = component.proxy(component.list("inventory_controller")() or "")

if modem then
    modem.open(port)
    if modem.isWireless() then modem.setStrength(16) end
    modem.broadcast(port, "robotStarted")
    if modem.isWireless() then modem.setStrength(math.huge) end
end

if rs then
    rs.setWakeThreshold(14)
end

local oldInterruptTime = -math.huge
local function interrupt()
    if computer.uptime() - oldInterruptTime > 4 then
        oldInterruptTime = computer.uptime()
        for i = 1, 10 do
            computer.pullSignal(0.1)
        end
    end
end

--------------------------------move

local map

local currentPosX, currentPosY, currentPosZ = 0, 0, 0
local currentFacing = 1
local function setFacing(facing)
    for i = 1, math.abs(currentFacing - facing) do
        robot.turn(facing > currentFacing)
    end
    currentFacing = facing
end

local function move(side)
    while true do
        if robot.detect(side) then
            robot.swing(side)
        else
            if robot.move(side) then
                break
            end
        end
        interrupt()
    end
    if side == 3 then
        if currentFacing == 1 then
            currentPosX = currentPosX + 1
        elseif currentFacing == 3 then
            currentPosX = currentPosX - 1
        elseif currentFacing == 2 then
            currentPosZ = currentPosZ + 1
        elseif currentFacing == 4 then
            currentPosZ = currentPosZ - 1
        end
    elseif side == 0 then
        currentPosY = currentPosY - 1
    elseif side == 1 then
        currentPosY = currentPosY + 1
    elseif side == 2 then
        if currentFacing == 1 then
            currentPosX = currentPosX - 1
        elseif currentFacing == 3 then
            currentPosX = currentPosX + 1
        elseif currentFacing == 2 then
            currentPosZ = currentPosZ - 1
        elseif currentFacing == 4 then
            currentPosZ = currentPosZ + 1
        end
    end
    if map then
        for i = #map.v, 1, -1 do
            if
            map.x[i] == currentPosX and
            map.y[i] == currentPosY and
            map.z[i] == currentPosZ then
                table.remove(map.x, i)
                table.remove(map.y, i)
                table.remove(map.z, i)
                table.remove(map.v, i)
                break
            end
        end
    end
end

local function deltaMoveToPos(x, y, z)
    x = math.floor(x)
    y = math.floor(y)
    z = math.floor(z)

    for i = 1, math.abs(y) do
        if y > 0 then
            move(1)
        elseif y < 0 then
            move(0)
        end
    end
    
    if x > 0 then
        setFacing(1)
    elseif x < 0 then
        setFacing(3)
    end
    for i = 1, math.abs(x) do
        move(3)
    end

    if z > 0 then
        setFacing(2)
    elseif z < 0 then
        setFacing(4)
    end
    for i = 1, math.abs(z) do
        move(3)
    end
end

local function moveToPos(x, y, z)
    deltaMoveToPos(x - currentPosX, y - currentPosY, z - currentPosZ)
end

--------------------------------geolyzer

local blockSize = 3
local function readMap()
    robot.setLightColor(0xFF0000)

    local map = {x = {}, y = {}, z = {}, v = {}}
    
    for bx = -2, 2 do
        for by = -2, 2 do
            for bz = -2, 2 do
                local spx, spy, spz = (bx * blockSize) + 1, (by * blockSize) + 1, (bz * blockSize) + 1

                local rawMap = assert(geo.scan(spx, spz, spy, blockSize, blockSize, blockSize))
                local i = 1
                for y = 0, blockSize - 1 do
                    for z = 0, blockSize - 1 do
                        for x = 0, blockSize - 1 do
                            local blockX, blockY, blockZ =
                            math.floor((spx + x) + currentPosX),
                            math.floor((spy + y) + currentPosY),
                            math.floor((spz + z) + currentPosZ)

                            if blockY <= maxMiningPos and (currentPosX ~= blockX or currentPosY ~= blockY or currentPosZ ~= blockZ) then
                                table.insert(map.x, blockX)
                                table.insert(map.y, blockY)
                                table.insert(map.z, blockZ)
                                table.insert(map.v, rawMap[i])
                            end
                            i = i + 1
                        end
                    end
                end
            end
        end
    end

    return map
end

--------------------------------logic

local function mathDist(x, y, z, x2, y2, z2)
    return math.abs(x - x2) + math.abs(y - y2) + math.abs(z - z2)
end

local function findPoint(isRecursion)
    robot.setLightColor(0xFF6600)
    local x, y, z, index

    for i = 1, #map.v do
        if map.v[i] > 2.5 then
            if not x or 
            mathDist(map.x[i], map.y[i], map.z[i], currentPosX, currentPosY, currentPosY) <
            mathDist(x,        y,        z       , currentPosX, currentPosY, currentPosY) then
                x = map.x[i]
                y = map.y[i]
                z = map.z[i]
                index = i
            end
        end
    end

    --[[
    table.remove(map.x, index)
    table.remove(map.y, index)
    table.remove(map.z, index)
    table.remove(map.v, index)
    ]]

    if not x then
        interrupt()
        if isRecursion then return nil, nil, nil end
        map = readMap()
        return findPoint(true)
    end

    return x, y, z
end

local function moveToHome()
    robot.setLightColor(0x00FF00)
    local y = currentPosY
    if y <= 4 and y >= -4 then
        if y >= 0 then
            y = 4
        else
            y = -4
        end
    end
    moveToPos(0, y, 0)
    moveToPos(0, 0, 0)
end

local function energy()
    return computer.energy() / computer.maxEnergy()
end

local function inventoryFullness()
    local value = 0

    for i = 1, robot.inventorySize() do
        value = value + (robot.count(i) / robot.space(i))
    end

    return value / robot.inventorySize()
end

--------------------------------main

local function isTool(name)
    for i = 1, #toolnames do
        if toolnames[i]:find("%:") then --is full mimecraft name
            if toolnames[i] == name then
                return true
            end
        else
            if unicode.sub(name, unicode.len(name) - (unicode.len(toolnames[i]) - 1), unicode.len(name)) == toolnames[i] then
                return true
            end
        end
    end
end

local function readDurability(info)
    if not info.damage then return 1 end
    return info.damage / info.maxDamage
end

local function checkTool(isHome)
    local durability, str = robot.durability()
    if (durability and durability < minDurability) or (not durability and str == "no tool equipped") then
        if not inv then
            return false
        else
            local toolstol
            for i = 1, robot.inventorySize() do
                local info = inv.getStackInInternalSlot(i)
                if info and info.name and readDurability(info) >= minDurability then
                    if isTool(info.name) then
                        toolstol = i
                        break
                    end
                end
            end
            if not toolstol then
                if isHome then
                    setFacing(4)
                    if not robot.suck(3) then
                        return false
                    end
                    setFacing(1)
                    return checkTool()
                end
                return false
            end
            robot.select(toolstol)
            inv.equip()
            return true
        end
    end
    return true
end

local function homeAction(isStart)
    robot.setLightColor(0x00FFFF)
    setFacing(1)
    
    for i = 1, robot.inventorySize() do
        local info = inv.getStackInInternalSlot(i)
        if robot.count(i) > 0 and (not info or not info.name or not isTool(info.name) or readDurability(info) < minDurability) then
            robot.select(i)
            robot.drop(3, math.huge)
        end
    end

    while energy() < 0.9 do
        interrupt()
    end

    if not checkTool(true) then
        computer.shutdown()
    end

    if not isStart then
        if rs.getInput(2) > 0 then
            computer.shutdown()
        end
    end
end

local function start()
    robot.setLightColor(0xFFFF00)
    moveToPos(0, startMiningPos, 0)
    map = readMap()

    while true do
        if energy() < minEnergy or inventoryFullness() > maxInventory then break end
        if not checkTool() then break end

        local x, y, z = findPoint()
        interrupt()
        if not x then
            robot.setLightColor(0xFF00FF)
            local offsetX = math.random(0, 2)
            local offsetZ = math.random(0, 2)
            if offsetX == 1 then
                offsetX = -20
            elseif offsetX == 2 then
                offsetX = 20
            end
            if offsetZ == 1 then
                offsetZ = -20
            elseif offsetZ == 2 then
                offsetZ = 20
            end
            deltaMoveToPos(offsetX, 0, offsetZ)
        else
            robot.setLightColor(0xFFFF00)
            moveToPos(x, y, z)
        end
        interrupt()
    end
end

homeAction(true)

while true do
    interrupt()
    start()

    interrupt()
    moveToHome()

    interrupt()
    homeAction()
end