GUI               = GUI
tableIterators    = tableIterators
GameObject        = GameObject
basicModule       = basicModule
errorHandling     = errorHandling
Debug             = Debug
Time              = Time
Vector2           = Vector2
Vector3           = Vector3
Vector4           = Vector4
Input             = Input
EnvironmentMaster = EnvironmentMaster


local defRoomAdd = "§Описание§назв карты§§4§§§OS§§§GBRP§"

local newID      = "appID"
local newIDVoice = "appID Voice"
local changeIDs  = false

local maps = {
    Legacy       = 4,
    Canvas       = 5,
    DesertBridge = 6,
    Polar6       = 7,
    PitValley    = 8,
    Facility     = 9,
    Reminiscence = 10,
    Conspiracy   = 11,
    Afterglow    = 12,
    F2Square     = 13,
    Pillars      = 14,
    Waterpark    = 15,
    -- Duels         = 16,
    -- DisasterIsland = 17,
    -- Town          = 22,
}


local regions = {
    eu     = "Европа",
    sa     = "Бразилия",
    us     = "США",
    ru     = "Россия",
    ["in"] = "Индия",
    au     = "Австралия",
    jp     = "Япония",
    tr     = "Турция",
    asia   = "Азия",
}


local goodStates = {
    Joined                  = true,
    ConnectedToMasterServer = true,
    JoinedLobby             = true,
}


local menuWidth    = 400
local buttonHeight = 30



local m16 = GameObject.Instantiate("pickUpAbles/M16")
local photonView = m16.GetComponent("photonView")
local componentType = photonView.CallMethod("GetType")
local assembly = componentType.GetField("Assembly")
m16.Destroy()

local allTypes = assembly.CallMethod("GetTypes")

local typeCache = {}

local function findTypeByName(typeName)
    if typeCache[typeName] then
        return typeCache[typeName]
    end
    for _, typeInfo in tableIterators.pairs(allTypes) do
        if typeInfo.CallMethod("get_Name") == typeName then
            typeCache[typeName] = typeInfo
            return typeInfo
        end
    end
    return nil
end


local PhotonNetworkType   = findTypeByName("PhotonNetwork")
local RoomOptionsType     = findTypeByName("RoomOptions")
local EnterRoomParamsType = findTypeByName("EnterRoomParams")


local roomOptionsProto     = RoomOptionsType.CallMethod("GetConstructors")[1].CallMethod("Invoke", {})
local enterRoomParamsProto = EnterRoomParamsType.CallMethod("GetConstructors")[1].CallMethod("Invoke", {})


local PhotonMono    = GameObject.FindAllByComponent("Photon.Pun.PhotonHandler")[1]
local PhotonHandler = PhotonMono.GetComponent("Photon.Pun.PhotonHandler")
local Client        = PhotonHandler.GetField("Client")


local appSettings

local function changeAppID()
    local success, err = errorHandling.pcall(function()
        local serverSettings = PhotonNetworkType.CallMethod("GetMethod", "get_PhotonServerSettings").CallMethod("Invoke",
            nil,
            nil)
        appSettings = serverSettings.GetField("AppSettings")

        if changeIDs then
            appSettings.SetField("AppIdVoice", newIDVoice)
            appSettings.SetField("AppIdRealtime", newID)
            Debug.log("new AppId: " .. newID)
            Debug.log("new AppIdVoice: " .. newIDVoice)
        end
    end)

    if not success then
        Debug.logError("Ошибка при изменении AppId: " .. basicModule.tostring(err))
    end
end


changeAppID()

local pingMethod = PhotonNetworkType.CallMethod("GetMethod", "GetPing")
local kickMethod = PhotonNetworkType.CallMethod("GetMethod", "CloseConnection")

local getCurrentRoomMethod
local disconnectMethod

local function GetCurrentRoom()
    if not getCurrentRoomMethod then
        getCurrentRoomMethod = PhotonNetworkType.CallMethod("GetMethod", "get_CurrentRoom")
    end
    return getCurrentRoomMethod.CallMethod("Invoke", nil, nil)
end

local function Disconnect()
    if not disconnectMethod then
        disconnectMethod = PhotonNetworkType.CallMethod("GetMethod", "Disconnect")
    end
    disconnectMethod.CallMethod("Invoke", nil, nil)
end


local ModLoader       = GameObject.FindAllByComponent("ModLoader")[1].GetComponent("ModLoader")
local cmaster         = GameObject.FindAllByComponent("ConnectionMaster")[1].GetComponent("ConnectionMaster")
local cmasterActive   = cmaster.Active

local DeviceInfo      = Input.GetDeviceInfo()
local localID         = string.gsub(
    basicModule.tostring(DeviceInfo.processorType) ..
    basicModule.tostring(string.sub(DeviceInfo.deviceUniqueIdentifier, 1, 10)) ..
    basicModule.tostring(DeviceInfo.graphicsDeviceName)
    , "[^%w]", "")

local state           = ""
local address         = "Нет соединения"
local connectedReg    = ""
local ping            = 0
local stateChangeTime = 0


local curRoom          = nil
local curRoomName      = ""
local playersList      = {}
local playersWithSinks = {}
local isMeHost         = false


local roomName   = "Room"
local mapName    = "Legacy"
local fixMapNum  = 4
local regionName = appSettings and appSettings.GetField("BestRegionSummaryFromStorage") or "eu"


local useCustomIK = false
local customIK    = ModLoader.CallMethod("GetIntegrityKey") or ""
local myIK        = ""
local checkIK     = false


local screenSize = Input.GetScreenRect()
local isMenuOpen = false
local inMenu     = true
local cors       = {}

local togglePos  = Vector4.New(screenSize.x / 2 - 400, 10, 400, 40)
local areaRect   = Vector4.New(screenSize.x / 2 - menuWidth / 2 - 250, 40, menuWidth, 450)

local myStyle    = GUI.NewStyle()
local tex        = Importer.ImportTexture("text.png")
local logoPos    = Vector4.New(screenSize.x / 2 - 450, 390, 50, 50)
local tex2       = Importer.ImportTexture("servers.png")
local logoPos2   = Vector4.New(screenSize.x / 2 - 100, 390, 50, 60)


local time            = 0
local lastStateUpdate = 0
local lastLoad        = 0
local lastFiveCheck   = 0
local last15Sync      = 0

function FindChild(obj, childName)
    local objt = obj.Transform
    for i = 0, objt.ChildCount - 1 do
        local childGO = objt.GetChild(i).GameObject
        if childGO.Name == childName then
            return childGO
        else
            FindChild(childGO, childName)
        end
    end
    return false
end

function KickPlayer(playerNam)
    local LuaPlayer = FindPlayer(playerNam)
    if LuaPlayer then
        LuaPlayer.Kick()
        Debug.log("kicked " .. playerNam)
    else
        Debug.SendChatMessageError("Не удалось найти игрока")
    end
end

local function OnOffcmaster(enabled)
    if cmaster then
        cmaster.Active = enabled
        cmasterActive  = enabled
    end
end

function GetID(LuaPlayer123)
    local character123 = LuaPlayer123.GetCharacter()
    if not character123 then return false end
    return character123.GameObject.GetComponent("PhotonView").GetAsUnknownType("Owner").GetField("UserID")
end

local function GetName(Pobj)
    return string.sub(string.gsub(string.sub(basicModule.tostring(Pobj), 16, -2), "[#']", ""), 1, 18)
end

function FindPlayer(str)
    local list = Player.GetAllPlayers()
    for i = 1, #list do
        if string.find(list[i].GetName(), str) or string.find(str, list[i].GetName()) then
            return list[i]
        end
    end
end

local function joinOrCreateRoom()
    fixMapNum = maps[mapName] or basicModule.tonumber(mapName)
    if not fixMapNum then return end

    OnOffcmaster(false)

    local roomOpt = roomOptionsProto.CallMethod("MemberwiseClone")
    roomOpt.SetField("MaxPlayers", 32)

    local enterOpt = enterRoomParamsProto.CallMethod("MemberwiseClone")
    enterOpt.SetField("RoomName", roomName .. string.gsub(defRoomAdd, "назв карты", mapName))
    enterOpt.SetField("RoomOptions", roomOpt)

    Client.CallMethod("OpJoinOrCreateRoom", enterOpt)


    PhotonNetworkType.CallMethod("GetMethod", "set_IsMessageQueueRunning").CallMethod("Invoke", nil, false)

    OnOffcmaster(false)
    lastLoad = Time.GetRealTimeMs()
    GameObject.FindAllByComponent("GoreBoxMenu")[1].GetComponent("GoreBoxMenu").CallMethod("LoadLevelAsync", fixMapNum,
        true, ModLoader.CallMethod("GetIntegrityKey"))
    cmaster.GetField("gameModes").CallMethod("SwitchGameMode", "Custom")
    Debug.log("загрузка карты...")
end

local function leaveRoom()
    Client.CallMethod("OpLeaveRoom", false, false)
end


local function drawLeftPanel()
    local w       = 220
    local padding = 5
    local rect    = Vector4.New(areaRect.x - w - 10, areaRect.y, w, 400)

    GUI.BeginArea(rect)
    GUI.Box(Vector4.New(0, 0, w, 450), "")
    GUI.Space(10)

    if curRoom then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        GUI.Label("<#ffb><b>" .. curRoomName, w - padding * 2, 20)
        GUI.EndHorizontal()

        GUI.BeginHorizontal()
        GUI.Space(padding)
        GUI.Label(
            "<#ccc>Игроков:<b> " .. #playersList .. "/" ..
            basicModule.tostring(curRoom.GetField("MaxPlayers")),
            w - padding * 2, 20)




        GUI.EndHorizontal()

        for i = 1, #playersList do
            GUI.BeginHorizontal()
            GUI.Space(padding)
            local currName = GetName(playersList[i])
            GUI.Label("   " .. currName, w * 0.75 - padding * 2, 20)
            if GUI.Button("Кик", 50, buttonHeight / 1.5) then
                local result = KickPlayer(currName)
            end
            GUI.EndHorizontal()
        end
    else
        GUI.BeginHorizontal()
        GUI.Space(padding)
        GUI.Label("<#ffb><b>Выбор карт (" .. mapName .. ")", w - padding * 2, 20)
        GUI.EndHorizontal()

        for minimap in tableIterators.pairs(maps) do
            GUI.BeginHorizontal()
            GUI.Space(padding)
            if GUI.Button(minimap, w - padding * 2, buttonHeight / 1.15) then
                mapName = minimap
            end
            GUI.EndHorizontal()
        end
    end

    GUI.EndArea()
end


local function drawRightPanel()
    local w       = 220
    local padding = 5
    local rect    = Vector4.New(areaRect.x + menuWidth + 10, areaRect.y, w, 400)

    GUI.BeginArea(rect)
    GUI.Box(Vector4.New(0, 0, w, 450), "")
    GUI.Space(10)

    GUI.BeginHorizontal()
    GUI.Space(padding)
    GUI.Label("<#ffb><b>Выбор региона (" .. (regionName or "не выбран") .. ")", w - padding * 2, 20)
    GUI.EndHorizontal()

    for regCode, regTitle in tableIterators.pairs(regions) do
        GUI.BeginHorizontal()
        GUI.Space(padding)
        if GUI.Button(regTitle, w - padding * 2, buttonHeight / 1.15) then
            regionName = regCode
        end
        GUI.EndHorizontal()
    end

    GUI.EndArea()
end


local function drawCenterPanel()
    local contentW = menuWidth * 0.85
    local padding  = (menuWidth - contentW) / 2

    GUI.BeginArea(areaRect)
    GUI.Box(Vector4.New(0, 0, menuWidth, 350), "")
    GUI.Space(20)


    GUI.BeginHorizontal()
    GUI.Space(padding)
    GUI.Label(
        (goodStates[state] and "<#bfb>" or "") .. "Статус: " .. state,
        contentW, 20)
    GUI.EndHorizontal()

    if state == "ConnectingToNameServer" and Time.GetRealTimeMs() > stateChangeTime + 5000 then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        GUI.Label("Если не удаётся подключиться, перезапустите игру или роутер", contentW, 20)
        GUI.EndHorizontal()
    end





    GUI.BeginHorizontal()
    GUI.Space(padding)
    GUI.Label(
        "Адрес сервера: " .. address ..
        " (<b>" .. connectedReg .. "</b>) | ping: " .. ping,
        contentW + 50, 20)
    GUI.EndHorizontal()


    GUI.BeginHorizontal()
    GUI.Space(padding)
    GUI.Label("Название сервера:", contentW, 20)
    GUI.EndHorizontal()

    GUI.BeginHorizontal()
    GUI.Space(padding)
    roomName = GUI.TextField(roomName, 32, contentW, 25)
    GUI.EndHorizontal()


    GUI.BeginHorizontal()
    GUI.Space(padding)
    if GUI.Button((checkIK and "<b>" or "") .. "[Хост] Проверка целостности модов: " .. (checkIK and "✓" or "X"), contentW, buttonHeight * 0.8) then
        checkIK = not checkIK
    end
    GUI.EndHorizontal()

    if checkIK then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        if GUI.Button((useCustomIK and "<b>" or "") .. "Свой IK ключ: " .. (useCustomIK and "✓" or "X"), contentW, buttonHeight * 0.75) then
            useCustomIK = not useCustomIK
        end
        GUI.EndHorizontal()
        GUI.BeginHorizontal()
        GUI.Space(padding)
        GUI.Label("↑ Если выключено, ключ читается автоматически", contentW, 20)
        GUI.EndHorizontal()
    end

    if useCustomIK then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        customIK = GUI.TextField(customIK, 2048, contentW, 20)
        GUI.EndHorizontal()
    end

    GUI.Space(10)


    GUI.BeginHorizontal()
    GUI.Space(padding)
    if GUI.Button("Подключение (" .. regionName .. ")", contentW, buttonHeight) then
        OnOffcmaster(false)

        Client.CallMethod("ConnectUsingSettings", appSettings)
        Client.CallMethod("ConnectToRegionMaster", regionName)
    end
    GUI.EndHorizontal()

    GUI.Space(5)

    if state ~= "Disconnected" then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        if GUI.Button("Отключить", contentW, buttonHeight) then
            Disconnect()
        end
        GUI.EndHorizontal()
    end

    GUI.Space(10)

    if state == "JoinedLobby" or state == "ConnectedToMasterServer" then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        if GUI.Button("Войти/Создать сервер", contentW, buttonHeight) then
            joinOrCreateRoom()
        end
        GUI.EndHorizontal()
    end

    GUI.Space(5)

    if state == "Joined" then
        GUI.BeginHorizontal()
        GUI.Space(padding)
        if GUI.Button("Покинуть сервер", contentW, buttonHeight) then
            leaveRoom()
        end
        GUI.EndHorizontal()
    end

    GUI.Space(5)

    GUI.BeginHorizontal()
    GUI.Space(padding)
    if GUI.Button("Ресет", contentW, buttonHeight) then
        GameObject.FindAllByComponent("LoadingScreen")[1].GetComponent("LoadingScreen").CallMethod("DoLoading", 0, 0, 1,
            true, false, true, "Intro", "", "", "")
    end
    GUI.EndHorizontal()

    GUI.EndArea()
end

function OnGUIOver()
    if inMenu or PlayerMaster.InUI then
        if GUI.ButtonRect(togglePos, "Neptune") then
            isMenuOpen = not isMenuOpen
        end
    end

    if not isMenuOpen then return end

    if GUI.ButtonRect(logoPos, "", myStyle) then
        local comp = GameObject.Create("linkOpener").AddComponent("BrowserLink")
        comp.SetField("url", "https://t.me/s/GoreBoxPiped")
        comp.CallMethod("OpenLink")
        comp.GameObject.Destroy()
    end
    GUI.DrawTexture(logoPos, tex, "StretchToFill", true, 1)

    if GUI.ButtonRect(logoPos2, "", myStyle) then
        local comp = GameObject.Create("linkOpener").AddComponent("BrowserLink")
        comp.SetField("url", "https://mpmod.vercel.app/")
        comp.CallMethod("OpenLink")
        comp.GameObject.Destroy()
    end
    GUI.DrawTexture(logoPos2, tex2, "StretchToFill", true, 1)

    GUI.Label(
        "<align=center><size=30>\n\n\n\n\n\n\n\n\n\n\n<size=10>\n<size=40>←                                                                  ",
        screenSize.x, screenSize.y)

    drawLeftPanel()
    drawRightPanel()
    drawCenterPanel()
end

function OnRPC(arg)
    if ListenForRPC then
        Debug.log(arg)
    end
end

function Update()
    time = Time.GetRealTimeMs()


    if time > lastStateUpdate + 500 then
        lastStateUpdate = time

        local newState = basicModule.tostring(Client.GetField("State") or "Unknown")
        if newState ~= state then
            state = newState
            stateChangeTime = time
        end
        address      = basicModule.tostring(Client.GetField("CurrentServerAddress") or "Нет соединения")
        connectedReg = basicModule.tostring(Client.GetField("CloudRegion"))
        ping         = pingMethod.CallMethod("Invoke", nil, nil) or 0
        curRoom      = GetCurrentRoom()
        if curRoom then
            curRoomName = string.gsub(curRoom.GetField("Name"), "§.*", "")
            playersList = curRoom.GetField("players") or {}

            for i = 1, #playersList do
                playersList[i] = playersList[i].GetField("value")
            end

            if EnvironmentMaster.GetCurrentScene() == "sys_Menu" then
                if not inMenu then
                    OnOffcmaster(true)
                    playersWithSinks = {}
                end
                inMenu = true
            else
                if inMenu then
                    inMenu = false
                    lastFiveCheck = 0
                    PhotonNetworkType.CallMethod("GetMethod", "set_IsMessageQueueRunning").CallMethod("Invoke", nil,
                        true)
                    isMenuOpen = false
                    OnOffcmaster(false)



                    local GameMaster = GameObject.FindAllByComponent("GameMaster")[1].Transform

                    local button1 = GameMaster.Find("GameCanvas-3/PanelManager/MenuPanel/ReturnMenu/Button")
                        .GameObject
                        .GetComponent("UnityEngine.UI.Button")
                    local button2 = GameMaster.Find(
                            "GameCanvas-3/PanelManager/MenuPanel (NewRestricted)/ReturnMenu/Button").GameObject
                        .GetComponent(
                            "UnityEngine.UI.Button")
                    if button1 then
                        button1.GetField("onClick").AddListener(function()
                            OnOffcmaster(true)
                        end)
                    else
                        Debug.log("кнопка 1 не найдена")
                    end
                    if button2 then
                        button2.GetField("onClick").AddListener(function()
                            OnOffcmaster(true)
                        end)
                    else
                        Debug.log("кнопка 2 не найдена")
                    end
                end
                inMenu = false
            end
        else
            inMenu      = true
            curRoomName = ""
            playersList = {}
        end
    end




    if Input.GetKeyDown("Escape") then
        isMenuOpen = false
    end

    if state == "LeavingRoom" or state == "Disconnecting" then
        OnOffcmaster(true)
    end

    if time > lastFiveCheck + 6000 then
        local x
        x = coroutine.create(function()
            local function wait(waittime)
                cors[x] = time + waittime
                coroutine.yield()
            end


            lastFiveCheck     = time
            local localPlayer = Client.GetField("LocalPlayer")
            local localProps  = localPlayer.GetAsUnknownType("CustomProperties")
            if localProps.CallMethod("ContainsKey", "IK") then
                localProps.CallMethod("set_Item", "IK", ModLoader.CallMethod("GetIntegrityKey"))
            else
                localProps.CallMethod("Add", "IK", ModLoader.CallMethod("GetIntegrityKey"))
            end
            if localProps.CallMethod("ContainsKey", "ID") then
                localProps.CallMethod("set_Item", "ID", localID)
            else
                localProps.CallMethod("Add", "ID", localID)
            end

            localPlayer.CallMethod("SetCustomProperties", localProps, nil, nil)
            myIK     = ModLoader.CallMethod("GetIntegrityKey")
            isMeHost = localPlayer.GetField("isHost")
            localPlayer.SetField("isOriginalHost", false)
            local PInfos = GameObject.FindAllByComponent("PlayerInfo")
            if not curRoom then return end
            wait(0)
            for i = 1, #playersList do
                wait(0)
                local realPlayer = playersList[i]
                local realName   = GetName(realPlayer)
                local props      = realPlayer.GetAsUnknownType("CustomProperties")
                local realID     = basicModule.tostring(props.CallMethod("get_Item", "ID"))
                local playerIK   = basicModule.tostring(props.CallMethod("get_Item", "IK"))
                local kick       = false

                if isMeHost and checkIK then
                    if useCustomIK then
                        if playerIK ~= customIK then
                            kick = true
                        end
                    else
                        if playerIK ~= myIK then
                            kick = true
                        end
                    end


                    if kick then
                        local msg = "<color=red><b>" ..
                            realName .. "</b> использует моды, попытка кика...</color>"
                        Server.SendChatMessage(msg, 20)
                        Debug.log(msg)
                        kickMethod.CallMethod("Invoke", nil, realPlayer)

                        local result = KickPlayer(realName)
                        if not result then
                            Server.SendChatMessage("Ошибка при кике ", 20)
                        end
                    end
                    
                end
                
                realPlayer.CallMethod("SetCustomProperties", props, nil, nil)
                realPlayer.SetField("Username", realName)
                realPlayer.SetField("UserId", realID)
                if isMeHost then
                    local codeForSink = basicModule.tostring(realPlayer)

                    if not playersWithSinks[codeForSink] then
                        playersWithSinks[codeForSink] = true
                        local GameRules = GameObject.FindAllByComponent("GameRules")[1].GetComponent("GameRules")
                        local EnvMaster = GameObject.FindAllByComponent("EnvironmentMaster")[1].GetComponent(
                            "EnvironmentMaster")
                        GameRules.CallMethod("SendSyncGamemode", realPlayer)
                        EnvMaster.CallMethod("SendSyncWeather", realPlayer)
                        Debug.log("Отправлена погода и права для " .. realName)
                        Server.SendChatMessage(
                            "<color=yellow>" .. basicModule.tostring(realName) .. " Зашёл на сервер",
                            20)
                    end
                end
            end

            for i = 1, #PInfos do
                local info = PInfos[i]
                local infocomp = info.GetComponent("PlayerInfo")

                local playerll = infocomp.GetField("player")

                if playerll == nil then
                    Debug.log(basicModule.tostring(infocomp.GetField("name")) .. " ошибка: Pinfo")
                end

                local TransferHostButton = info.Transform.Find("Options (OBD)/TransferHost")
                if TransferHostButton then
                    if playerll.GetField("IsLocal") then
                        TransferHostButton.GameObject.Destroy()
                    end
                end
                wait(0)
            end
        end)
        cors[x] = 0
    end

    for corout, cortime in tableIterators.pairs(cors) do
        if time > cortime then
            cors[corout] = nil
            local succes, error = coroutine.resume(corout)
            if not succes then
                Debug.logError("Ошибка в корутине (Neptune): " .. error)
            end
        end
    end
end
