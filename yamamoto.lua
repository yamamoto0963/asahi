--My bot pid :dnPhC0KEAFGdwzY_anDxP_-UsfItQG_iulOWoOHl7M8
--First strategy:
--Find the closest player with the least energy to attack.
-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

function getUpOrDown(y, targetY)
    if y < targetY then
        return "Up"
    elseif y == targetY then
        return ""
    elseif y > targetY then
        return "Down"
    end
end

function getLeftOrRight(x, targetX)
    if x < targetX then
        return "Right"
    elseif x == targetX then
        return ""
    elseif x > targetX then
        return "Left"
    end
end

-- Checks if two points are within a given range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decides the next action based on player proximity and energy, preferring lower energy targets.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRange = false
    local targetId = nil
    local targetEnergy = math.huge

    -- Find the nearest player with the lowest energy
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
            targetInRange = true
            if state.energy < targetEnergy then
                targetId = target
                targetEnergy = state.energy
            end
        end
    end

    if player.energy > 5 and targetInRange and targetId then
        print(colors.red .. "Player in range. Attacking player with lower energy." .. colors.reset)
        ao.send({
            Target = Game,
            Action = "PlayerAttack",
            Player = ao.id,
            AttackEnergy = tostring(player.energy),
            TargetPlayer =
                targetId
        })
    else
        if targetId ~= nil then
            -- , move to target
            print(colors.red .. "move to target." .. colors.reset)
            local ydir = getUpOrDown(player.y, LatestGameState.Players[targetId].y)
            local xdir = getLeftOrRight(player.x, LatestGameState.Players[targetId].x)
            ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = ydir .. xdir })
        end
        -- No target, random move
        print(colors.red .. "No target, random move." .. colors.reset)
        local directionMap = { "Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft" }
        local randomIndex = math.random(#directionMap)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex] })
    end
    InAction = false
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then
            print("Previous action still in progress. Skipping.")
        end
        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then
            InAction = true
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
    end
)

-- Handler to decide the next best action after game state update.
Handlers.add(
    "DecideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            InAction = false
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then
            InAction = true
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if not playerEnergy then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
            end
            InAction = false
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
