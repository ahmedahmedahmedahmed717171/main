-- Global environment setup (Ensures the script can find services)
local runService = game:GetService("RunService")
local inputService = game:GetService("UserInputService")
local collectionService = game:GetService("CollectionService")
local gameCamera = workspace.CurrentCamera
local lplr = game:GetService("Players").LocalPlayer

local TargetPart
local Targets
local FOV
local Range
local OtherProjectiles
local Blacklist
local SortMethod
local AeroPAChargePercent
local RandomHeadPercent
local RandomTorsoPercent
local CustomPrediction
local HorizontalMultiplier
local VerticalMultiplier
local DesirePAWorkMode
local DesirePAHideCursor
local DesirePACursorViewMode
local DesirePACursorLimitBow
local DesirePACursorShowGUI
local cursorRenderConnection
local lastGUIState = false
local rayCheck = (cloneRaycast and cloneRaycast()) or RaycastParams.new()
local old
local math_sqrt = math.sqrt
local math_rad = math.rad
local math_cos = math.cos
local math_clamp = math.clamp
local math_min = math.min
local math_max = math.max
local lockedRandomPart = nil
local wasHovering = false
local PAFOVCircle
local ProjectileAimbot
local paFOVCircleDrawing = nil
local AutoCharge
local paFOVCircleConnection = nil

local function runPAFOVCircle(call)
    if paFOVCircleConnection then
        paFOVCircleConnection:Disconnect()
        paFOVCircleConnection = nil
    end
    if paFOVCircleDrawing then
        paFOVCircleDrawing:Remove()
        paFOVCircleDrawing = nil
    end
    if call then
        paFOVCircleDrawing = Drawing.new('Circle')
        paFOVCircleDrawing.Visible = false
        paFOVCircleDrawing.Thickness = 1
        paFOVCircleDrawing.Color = Color3.fromRGB(255, 255, 255)
        paFOVCircleDrawing.Filled = false
        paFOVCircleDrawing.NumSides = 64
        paFOVCircleConnection = runService.RenderStepped:Connect(function()
            if paFOVCircleDrawing and FOV and FOV.Value then
                local shouldShow = false
                if PAFOVCircle and PAFOVCircle.Enabled and ProjectileAimbot and ProjectileAimbot.Enabled then
                    local tool = store.hand and store.hand.tool
                    local itemType = tool and tool.Name or ""
                    local itemMeta = bedwars.ItemMeta and bedwars.ItemMeta[itemType]
                    if itemMeta and itemMeta.projectileSource then
                        local src = itemMeta.projectileSource
                        local isArrow = src.ammoItemTypes and table.find(src.ammoItemTypes, 'arrow')
                        local isHeadhunter = itemType:find('headhunter')
                        if isArrow or isHeadhunter then
                            shouldShow = true
                        elseif OtherProjectiles and OtherProjectiles.Enabled then
                            local projectileType = src.projectileType and (type(src.projectileType) == 'function' and src.projectileType('arrow') or src.projectileType) or ""
                            local blacklisted = false
                            for _, black in ipairs(Blacklist and Blacklist.ListEnabled or {}) do
                                if tostring(projectileType):find(black) then
                                    blacklisted = true
                                    break
                                end
                            end
                            if not blacklisted then
                                shouldShow = true
                            end
                        end
                    end
                end
                paFOVCircleDrawing.Visible = shouldShow
                local mousePos = inputService:GetMouseLocation()
                paFOVCircleDrawing.Position = Vector2.new(mousePos.X, mousePos.Y)
                paFOVCircleDrawing.Radius = FOV.Value
            end
        end)
    end
end

local function hasBowEquipped()
    if not store.hand or not store.hand.toolType then return false end
    return store.hand.toolType == 'bow' or store.hand.toolType == 'crossbow'
end

local function shouldHideCursor()
    if not DesirePAHideCursor or not DesirePAHideCursor.Enabled then return false end
    if DesirePACursorShowGUI and DesirePACursorShowGUI.Enabled and isGUIOpen() then return false end
    if DesirePACursorLimitBow and DesirePACursorLimitBow.Enabled and not hasBowEquipped() then return false end
    local inFirstPerson = isFirstPerson()
    if DesirePACursorViewMode then
        if DesirePACursorViewMode.Value == 'First Person' then return inFirstPerson
        elseif DesirePACursorViewMode.Value == 'Third Person' then return not inFirstPerson
        end
    end
    return true
end

local function updateCursor()
    pcall(function() inputService.MouseIconEnabled = not shouldHideCursor() end)
end

local function checkGUIState()
    local currentGUIState = isGUIOpen()
    if lastGUIState ~= currentGUIState then
        updateCursor()
        lastGUIState = currentGUIState
    end
end

local function shouldPAWork()
    if not DesirePAWorkMode then return true end
    local inFirstPerson = isFirstPerson()
    if DesirePAWorkMode.Value == 'First Person' then return inFirstPerson
    elseif DesirePAWorkMode.Value == 'Third Person' then return not inFirstPerson
    end
    return true
end

local function isBlacklisted(projectileName)
    if not OtherProjectiles.Enabled then
        local isTurret = projectileName:find('turret') ~= nil or projectileName:find('vulcan') ~= nil
        return not projectileName:find('arrow') and not isTurret
    end
    for _, black in ipairs(Blacklist.ListEnabled) do
        if projectileName:find(black) then
            return true
        end
    end
    return false
end

local function getValidTargets(originPos, maxDist, maxAngle, sortMethod)
    local valid = {}
    local fovThreshold = math_cos(math_rad(maxAngle) / 2)
    local rangeSq = maxDist * maxDist

    for _, ent in ipairs(entitylib.List) do
        if not Targets.Players.Enabled and ent.Player then continue end
        if (not Targets.NPCs or not Targets.NPCs.Enabled) and ent.NPC then continue end
        if not ent.Targetable then continue end
        if ent.Player and getAccountTier(ent.Player) >= 1 and getAccountTier(lplr) == 0 then continue end
        if not ent.Character or not ent.RootPart or not ent.RootPart.Parent then continue end

        local delta = ent.RootPart.Position - originPos
        local distSq = delta.X*delta.X + delta.Y*delta.Y + delta.Z*delta.Z
        if distSq > rangeSq then continue end

        if maxAngle < 360 then
            local facing = gameCamera.CFrame.LookVector
            if delta.Magnitude > 0.001 then
                local dot = facing:Dot(delta.Unit)
                if dot < fovThreshold then continue end
            end
        end

        if Targets.Walls.Enabled then
            local ray = workspace:Raycast(originPos, delta, rayCheck)
            if ray then continue end
        end

        if sortMethod == "Cursor" then
            local mousePos = inputService:GetMouseLocation()
            local screenPos, onScreen = gameCamera:WorldToScreenPoint(ent.RootPart.Position)
            if not onScreen then continue end
            local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
            if screenDist > FOV.Value then continue end
        end

        table.insert(valid, {Entity = ent})
    end

    if #valid == 0 then return {} end

    local sortFunc = sortmethods[sortMethod] or sortmethods.Distance
    table.sort(valid, sortFunc)
    local unwrapped = {}
    for _, v in ipairs(valid) do
        table.insert(unwrapped, v.Entity)
    end
    return unwrapped
end

local function pickRandomPart(character)
    local roll = math.random(1, 100)
    if roll <= RandomHeadPercent.Value then
        return character:FindFirstChild('Head') or character:FindFirstChild('HumanoidRootPart')
    else
        return character:FindFirstChild('HumanoidRootPart')
    end
end

local function getClosestPart(character, mousePos)
    local parts = {
        'HumanoidRootPart', 'Head', 'LeftHand', 'RightHand',
        'LeftLowerArm', 'RightLowerArm', 'LeftUpperArm', 'RightUpperArm',
        'LeftFoot', 'RightFoot', 'LeftLowerLeg', 'RightLowerLeg',
        'LeftUpperLeg', 'RightUpperLeg', 'LowerTorso', 'UpperTorso'
    }
    local camera = gameCamera
    local rayOrigin = camera.CFrame.Position
    local rayDir = camera:ScreenPointToRay(mousePos.X, mousePos.Y, 0).Direction
    local bestAngle = math.huge
    local bestPart = nil

    for _, partName in ipairs(parts) do
        local part = character:FindFirstChild(partName)
        if part then
            local dirToPart = (part.Position - rayOrigin).Unit
            local angle = math.acos(math_clamp(rayDir:Dot(dirToPart), -1, 1))
            if angle < bestAngle then
                bestAngle = angle
                bestPart = part
            end
        end
    end
    return bestPart or character:FindFirstChild('HumanoidRootPart')
end

ProjectileAimbot = vape.Categories.Blatant:CreateModule({
    Name = 'ProjectileAimbot',
    Function = function(callback)
        if callback then
            if PAFOVCircle then
                runPAFOVCircle(PAFOVCircle.Enabled)
            end
            if DesirePAHideCursor and DesirePAHideCursor.Enabled and not cursorRenderConnection then
                cursorRenderConnection = runService.RenderStepped:Connect(function()
                    checkGUIState()
                    updateCursor()
                end)
            end

            old = bedwars.ProjectileController.calculateImportantLaunchValues
            bedwars.ProjectileController.calculateImportantLaunchValues = function(...)
                local self, projmeta, worldmeta, origin, shootpos = ...
                local originPos = entitylib.isAlive and (shootpos or (entitylib.character and entitylib.character.RootPart and entitylib.character.RootPart.Position)) or Vector3.zero
                if not wasHovering then lockedRandomPart = nil end
                wasHovering = true
                local entityPart = (TargetPart.Value == 'Head') and 'Head' or 'RootPart'
                local plr = entitylib.EntityMouse({
                    Part = entityPart,
                    Range = FOV.Value,
                    Players = Targets.Players.Enabled,
                    NPCs = (Targets.NPCs and Targets.NPCs.Enabled) or false,
                    Wallcheck = Targets.Walls.Enabled,
                    Origin = originPos
                })

                if not plr then
                    wasHovering = false
                    local s, r = pcall(old, ...)
                    return s and r or nil
                end

                if not getgenv().AeroLocalPaid and plr.Player and getgenv().isAeroPaid and getgenv().isAeroPaid(plr.Player) then
                    wasHovering = false
                    return old(...)
                end

                if not shouldPAWork() then
                    wasHovering = false
                    return old(...)
                end

                local targetBodyPart = nil
                if TargetPart.Value == 'Dynamic' then
                    local tool = store.hand and store.hand.tool
                    local itemType = tostring(tool and tool.Name or ""):lower()
                    local isHH = itemType:find("headhunter")
                    targetBodyPart = isHH and (plr.Character:FindFirstChild("Head") or plr.RootPart) or plr.RootPart
                elseif TargetPart.Value == 'RootPart' then
                    targetBodyPart = plr.RootPart
                elseif TargetPart.Value == 'Head' then
                    targetBodyPart = plr.Head or plr.RootPart
                elseif TargetPart.Value == 'Closest' then
                    local mousePos = inputService:GetMouseLocation()
                    targetBodyPart = getClosestPart(plr.Character, mousePos)
                elseif TargetPart.Value == 'Randomize' then
                    if not lockedRandomPart or not lockedRandomPart.Parent then
                        lockedRandomPart = pickRandomPart(plr.Character)
                    end
                    targetBodyPart = lockedRandomPart
                else
                    targetBodyPart = plr.RootPart
                end

                if not targetBodyPart then
                    wasHovering = false
                    return old(...)
                end

                local dist = (targetBodyPart.Position - originPos).Magnitude
                if dist > Range.Value then
                    wasHovering = false
                    return old(...)
                end

                local pos = shootpos or self:getLaunchPosition(origin)
                if not pos then
                    wasHovering = false
                    return old(...)
                end

                local projectileName = projmeta.projectile or ""
                if isBlacklisted(projectileName) then
                    wasHovering = false
                    return old(...)
                end

                local meta = projmeta:getProjectileMeta()
                local lifetime = (worldmeta and meta.predictionLifetimeSec or meta.lifetimeSec or 3)
                local gravity = (meta.gravitationalAcceleration or 196.2) * projmeta.gravityMultiplier
                local projSpeed = (meta.launchVelocity or 100)
                local offsetpos = pos + (projmeta.projectile == 'owl_projectile' and Vector3.zero or projmeta.fromPositionOffset)
                local balloons = plr.Character and plr.Character:GetAttribute('InflatedBalloons')
                local playerGravity = workspace.Gravity
                if balloons and balloons > 0 then
                    playerGravity = workspace.Gravity * (1 - (balloons >= 4 and 1.2 or balloons >= 3 and 1 or 0.975))
                end
                if plr.Character and plr.Character.PrimaryPart and plr.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
                    playerGravity = 6
                end
                if plr.Player and plr.Player:GetAttribute('IsOwlTarget') then
                    for _, owl in ipairs(collectionService:GetTagged('Owl')) do
                        if owl:GetAttribute('Target') == plr.Player.UserId and owl:GetAttribute('Status') == 2 then
                            playerGravity = 0
                            break
                        end
                    end
                end

                local targetVelocity = targetBodyPart.Velocity
                if CustomPrediction and CustomPrediction.Enabled then
                    local hMult = (HorizontalMultiplier and HorizontalMultiplier.Value or 100) / 100
                    local vMult = (VerticalMultiplier and VerticalMultiplier.Value or 100) / 100
                    targetVelocity = Vector3.new(
                        targetVelocity.X * hMult,
                        targetVelocity.Y * vMult,
                        targetVelocity.Z * hMult
                    )
                end
                local bowRelX = bedwars.BowConstantsTable.RelX or 0
                local bowRelY = bedwars.BowConstantsTable.RelY or 0
                local bowRelZ = bedwars.BowConstantsTable.RelZ or 0
                local newlook = CFrame.new(offsetpos, targetBodyPart.Position) *
                    CFrame.new(projmeta.projectile == 'owl_projectile' and Vector3.zero or
                        Vector3.new(bowRelX, bowRelY, bowRelZ))

                local calc = prediction.SolveTrajectory(
                    newlook.p, projSpeed, gravity,
                    targetBodyPart.Position,
                    projmeta.projectile == 'telepearl' and Vector3.zero or targetVelocity,
                    playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck
                )

                if calc then
                    if targetinfo and targetinfo.Targets then
                        targetinfo.Targets[plr] = tick() + 1
                    end

                    local customDrawDuration = 5
                    if AutoCharge.Enabled then
                        if projmeta.projectile:find('arrow') then
                            customDrawDuration = 0.58 * (AeroPAChargePercent.Value / 100)
                        elseif projmeta.projectile:find('frosty_snowball') then
                            local tool = store.hand and store.hand.tool
                            if tool and tool.Name:find('frost_staff') then
                                local cd = (tool.Name:find('frost_staff_3') and 0.16) or
                                        (tool.Name:find('frost_staff_2') and 0.18) or 0.2
                                customDrawDuration = cd * (AeroPAChargePercent.Value / 100)
                            end
                        end
                    else
                        customDrawDuration = 0.05
                    end

                    wasHovering = false
                    return {
                        initialVelocity = CFrame.new(newlook.Position, calc).LookVector * projSpeed,
                        positionFrom = offsetpos,
                        deltaT = lifetime,
                        gravitationalAcceleration = gravity,
                        drawDurationSeconds = customDrawDuration
                    }
                end

                wasHovering = false
                return old(...)
            end
        else
            bedwars.ProjectileController.calculateImportantLaunchValues = old
            wasHovering = false
            lockedRandomPart = nil
            if cursorRenderConnection then
                cursorRenderConnection:Disconnect()
                cursorRenderConnection = nil
            end
            runPAFOVCircle(false)
            pcall(function() inputService.MouseIconEnabled = true end)
            task.defer(function()
                pcall(function() inputService.MouseIconEnabled = true end)
                pcall(function() game:GetService('UserInputService').MouseIconEnabled = true end)
            end)
        end
    end,
    Tooltip = 'Silently adjusts your aim towards the enemy'
})

Targets = ProjectileAimbot:CreateTargets({
    Players = true,
    NPCs = true,
    Walls = true
})

TargetPart = ProjectileAimbot:CreateDropdown({
    Name = 'Part',
    List = {'Dynamic', 'RootPart', 'Head', 'Closest', 'Randomize'},
    Default = 'RootPart',
    Tooltip = 'Select which body part to aim at',
    Function = function()
        lockedRandomPart = nil
        wasHovering = false
    end
})

SortMethod = ProjectileAimbot:CreateDropdown({
    Name = 'Sort Method',
    List = {'Distance', 'Damage', 'Threat', 'Kit', 'Health', 'Angle', 'Cursor', 'Forest'},
    Default = 'Distance',
    Tooltip = 'Prioritize targets when multiple are in range'
})

DesirePAWorkMode = ProjectileAimbot:CreateDropdown({
    Name = 'PA Work Mode',
    List = {'First Person', 'Third Person', 'Both'},
    Default = 'Both',
    Tooltip = 'Which perspective the aimbot works in'
})

Range = ProjectileAimbot:CreateSlider({
    Name = 'Range',
    Min = 10,
    Max = 500,
    Default = 100,
    Tooltip = 'Maximum distance (in studs) for targeting'
})

FOV = ProjectileAimbot:CreateSlider({
    Name = 'FOV',
    Min = 1,
    Max = 1000,
    Default = 1000
})

PAFOVCircle = ProjectileAimbot:CreateToggle({
    Name = 'FOV Circle',
    Tooltip = 'Shows a circle representing your FOV on screen',
    Function = function(call)
        runPAFOVCircle(call)
    end
})

RandomHeadPercent = ProjectileAimbot:CreateSlider({
    Name = 'Head Chance',
    Min = 0,
    Max = 100,
    Default = 50,
    Darker = true,
    Tooltip = 'Chance to aim at head when Part is set to Randomize',
    Visible = false
})

RandomTorsoPercent = ProjectileAimbot:CreateSlider({
    Name = 'Torso Chance',
    Min = 0,
    Max = 100,
    Default = 50,
    Darker = true,
    Tooltip = 'Chance to aim at torso when Part is set to Randomize',
    Visible = false
})

local function updateRandomizeVisibility()
    local vis = (TargetPart.Value == 'Randomize')
    RandomHeadPercent.Object.Visible = vis
    RandomTorsoPercent.Object.Visible = vis
end
if TargetPart.AddHook then
    TargetPart:AddHook(updateRandomizeVisibility)
end
updateRandomizeVisibility()

DesirePAHideCursor = ProjectileAimbot:CreateToggle({
    Name = 'Hide Cursor',
    Default = false,
    Tooltip = 'Hides the cursor while aiming',
    Function = function(callback)
        if DesirePACursorViewMode then DesirePACursorViewMode.Object.Visible = callback end
        if DesirePACursorLimitBow then DesirePACursorLimitBow.Object.Visible = callback end
        if DesirePACursorShowGUI then DesirePACursorShowGUI.Object.Visible = callback end
        if callback and ProjectileAimbot.Enabled then
            if not cursorRenderConnection then
                cursorRenderConnection = runService.RenderStepped:Connect(function()
                    checkGUIState()
                    updateCursor()
                end)
            end
            updateCursor()
        else
            if cursorRenderConnection then
                cursorRenderConnection:Disconnect()
                cursorRenderConnection = nil
            end
            pcall(function() inputService.MouseIconEnabled = true end)
            task.defer(function()
                pcall(function() inputService.MouseIconEnabled = true end)
                pcall(function() game:GetService('UserInputService').MouseIconEnabled = true end)
            end)
        end
    end
})

DesirePACursorViewMode = ProjectileAimbot:CreateDropdown({
    Name = 'Cursor View Mode',
    List = {'First Person', 'Third Person', 'Both'},
    Default = 'First Person',
    Darker = true,
    Visible = false,
    Function = function()
        if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
            updateCursor()
        end
    end
})

DesirePACursorLimitBow = ProjectileAimbot:CreateToggle({
    Name = 'Limit to Bow',
    Darker = true,
    Visible = false,
    Tooltip = 'Only hides cursor when bow/crossbow is equipped',
    Function = function()
        if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
            updateCursor()
        end
    end
})

DesirePACursorShowGUI = ProjectileAimbot:CreateToggle({
    Name = 'Show on GUI',
    Darker = true,
    Visible = false,
    Tooltip = 'Shows cursor when a GUI is open',
    Function = function()
        if ProjectileAimbot.Enabled and DesirePAHideCursor.Enabled then
            updateCursor()
        end
    end
})

CustomPrediction = ProjectileAimbot:CreateToggle({
    Name = 'Custom Prediction',
    Default = false,
    Tooltip = 'Enable to customize horizontal/vertical prediction multipliers',
    Function = function()
        if HorizontalMultiplier then
            HorizontalMultiplier.Object.Visible = CustomPrediction.Enabled
        end
        if VerticalMultiplier then
            VerticalMultiplier.Object.Visible = CustomPrediction.Enabled
        end
    end
})

HorizontalMultiplier = ProjectileAimbot:CreateSlider({
    Name = 'Horizontal Multiplier',
    Min = 0,
    Max = 200,
    Default = 100,
    Suffix = '%',
    Darker = true,
    Visible = false,
    Tooltip = 'Adjust horizontal prediction strength (0% = none, 100% = normal, 200% = double)'
})

VerticalMultiplier = ProjectileAimbot:CreateSlider({
    Name = 'Vertical Multiplier',
    Min = 0,
    Max = 200,
    Default = 100,
    Suffix = '%',
    Darker = true,
    Visible = false,
    Tooltip = 'Adjust vertical prediction strength (0% = none, 100% = normal, 200% = double)'
})

OtherProjectiles = ProjectileAimbot:CreateToggle({
    Name = 'Other Projectiles',
    Default = true,
    Function = function(call)
        if Blacklist then Blacklist.Object.Visible = call end
    end
})

Blacklist = ProjectileAimbot:CreateTextList({
    Name = 'Blacklist',
    Darker = true,
    Default = {'telepearl'},
    Visible = OtherProjectiles.Enabled
})

AutoCharge = ProjectileAimbot:CreateToggle({
    Name = "AutoCharge",
    Default = true,
    Function = function(v)
        if AeroPAChargePercent and AeroPAChargePercent.Object then AeroPAChargePercent.Object.Visible = v end
    end
})

AeroPAChargePercent = ProjectileAimbot:CreateSlider({
    Name = 'Charge Percent',
    Min = 1,
    Max = 100,
    Default = 100,
    Tooltip = 'Bow/frost staff charge percentage (affects damage)'
})
