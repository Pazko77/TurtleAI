-- TurtleAI Client
-- Adapted from gotoundo/TurtleAI (originally Gemini) to use Groq API
-- Control turtles with natural language through Groq AI

local MODEL = "llama-3.3-70b-versatile"
local VERSION = "1.0.0"

local CLIENT_ID = os.getComputerID()
local DEFAULT_CHANNEL = 65

local DEBUG = false

local function debugLog(message)
  if DEBUG then
    term.setTextColor(colors.orange)
    print("[DEBUG] " .. tostring(message))
    term.setTextColor(colors.white)
  end
end

local function jsonEscape(str)
  if str then
    str = string.gsub(str, '\\', '\\\\')
    str = string.gsub(str, '"', '\\"')
    str = string.gsub(str, '\n', '\\n')
    str = string.gsub(str, '\r', '\\r')
    str = string.gsub(str, '\t', '\\t')
  end
  return str
end

local function jsonUnescape(str)
  if str then
    str = string.gsub(str, '\\n', '\n')
    str = string.gsub(str, '\\r', '\r')
    str = string.gsub(str, '\\t', '\t')
    str = string.gsub(str, '\\"', '"')
    str = string.gsub(str, '\\\\', '\\')
  end
  return str
end

-- Parse OpenAI-compatible JSON response
local function parseJSON(json)
  local result = {}

  local content = json:match('"content"%s*:%s*"(.-[^\\])"')

  if content then
    result.text = jsonUnescape(content)
  else
    content = json:match('"content"%s*:%s*"(.-)"')
    if content then
      result.text = jsonUnescape(content)
    end
  end

  return result
end

local function trim(s)
  if type(s) ~= "string" then return "" end
  return s:match("^%s*(.-)%s*$")
end

-- Find wireless modem
local modem = nil
for _, side in pairs({"left", "right", "top", "bottom", "front", "back"}) do
  if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
    modem = peripheral.wrap(side)
    if modem.isWireless() then
      debugLog("Found wireless modem on " .. side)
      break
    end
    modem = nil
  end
end

if not modem then
  print("No wireless modem found! Please attach one.")
  return
end

settings.define("groq.api_key", {
  description = "Your Groq API key from console.groq.com",
  default = "",
  type = "string"
})

local conversationHistory = {}

local function addToHistory(role, message)
  table.insert(conversationHistory, {role = role, text = message})
end

local function clearHistory()
  conversationHistory = {}
  return "Conversation history cleared."
end

local function buildRequestBody()
  local messages = {}

  for _, message in ipairs(conversationHistory) do
    -- Groq/OpenAI uses "assistant" instead of "model"
    local role = message.role == "model" and "assistant" or message.role
    table.insert(messages, '{"role":"' .. role .. '","content":"' .. jsonEscape(message.text) .. '"}')
  end

  local requestBody = '{"model":"' .. MODEL .. '","messages":[' .. table.concat(messages, ",") .. '],"max_tokens":1024}'
  return requestBody
end

local function generateContent(prompt)
  local apiKey = settings.get("groq.api_key")

  if not apiKey or apiKey == "" then
    return "Error: API key not set. Use 'setkey' to set it."
  end

  addToHistory("user", prompt)

  local url = "https://api.groq.com/openai/v1/chat/completions"
  local requestBody = buildRequestBody()

  debugLog("Sending request to Groq API")

  local response = http.post(
    url,
    requestBody,
    {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. apiKey
    }
  )

  if response then
    local responseText = response.readAll()
    response.close()

    local result = parseJSON(responseText)

    if result.text then
      addToHistory("model", result.text)
      return result.text
    else
      local debugInfo = "Error: Could not parse response."
      if #responseText > 200 then
        debugInfo = debugInfo .. " Raw (first 200 chars): " .. responseText:sub(1, 200) .. "..."
      else
        debugInfo = debugInfo .. " Raw: " .. responseText
      end
      return debugInfo
    end
  else
    return "Error: Could not connect to Groq API"
  end
end

local function sendAndReceive(channel, message, timeout)
  local replyChannel = os.getComputerID() + 100
  timeout = timeout or 2

  modem.open(replyChannel)
  modem.transmit(channel, replyChannel, message)

  local timer = os.startTimer(timeout)
  while true do
    local event, param1, param2, param3, param4, param5 = os.pullEvent()

    if event == "modem_message" and param3 == channel then
      modem.close(replyChannel)
      return param4
    elseif event == "timer" and param1 == timer then
      modem.close(replyChannel)
      return nil
    end
  end
end

local function scanChannels(startChannel, endChannel)
  startChannel = startChannel or DEFAULT_CHANNEL
  endChannel = endChannel or startChannel + 10

  print("Scanning channels " .. startChannel .. " to " .. endChannel .. "...")
  local servers = {}

  for channel = startChannel, endChannel do
    local response = sendAndReceive(channel, {
      command = "ping",
      clientID = CLIENT_ID
    }, 0.5)

    if response and response.success and response.serverName then
      table.insert(servers, {
        channel = channel,
        name = response.serverName,
        hasSimpleMining = response.hasSimpleMining
      })
      print("Found server '" .. response.serverName .. "' on channel " .. channel)
      if response.hasSimpleMining then
        print("  - Has simple_mining.lua installed")
      end
    end
  end

  return servers
end

local function connectToServer(channel)
  print("Connecting to server on channel " .. channel .. "...")
  local response = sendAndReceive(channel, {
    command = "connect",
    clientID = CLIENT_ID
  })

  if not response or not response.success then
    print("Failed to connect!")
    return false, nil
  end

  print("Connected to: " .. response.serverName)

  if response.authRequired then
    write("Password: ")
    local password = read("*")

    local authResponse = sendAndReceive(channel, {
      command = "auth",
      clientID = CLIENT_ID,
      password = password
    })

    if not authResponse or not authResponse.success then
      print("Authentication failed!")
      return false, nil
    end

    print("Authentication successful")
  end

  return true, response.status
end

local function getTurtleStatus(channel)
  local response = sendAndReceive(channel, {
    command = "status",
    clientID = CLIENT_ID
  }, 1)

  if not response or not response.success then return nil end
  return response.status
end

local function executeRemote(channel, code)
  local response = sendAndReceive(channel, {
    command = "exec",
    clientID = CLIENT_ID,
    code = code
  }, 10)

  if not response then
    return false, "No response from server", nil
  end

  return response.success, response.output, response.status
end

local function extractCodeBlocks(response)
  debugLog("Extracting code blocks from response")

  if type(response) ~= "string" then
    debugLog("Error: Response is not a string")
    return {}
  end

  local codeBlocks = {}

  for codeBlock in response:gmatch("```lua(.-)```") do
    debugLog("Found lua code block")
    local cleanedBlock = codeBlock:gsub("^%s+", ""):gsub("%s+$", "")
    table.insert(codeBlocks, cleanedBlock)
  end

  if #codeBlocks == 0 then
    debugLog("No lua code blocks found, looking for generic code blocks")
    for codeBlock in response:gmatch("```(.-)```") do
      debugLog("Found generic code block")
      local cleanedBlock = codeBlock:gsub("^%s+", ""):gsub("%s+$", "")
      table.insert(codeBlocks, cleanedBlock)
    end
  end

  debugLog("Extracted " .. tostring(#codeBlocks) .. " code blocks")
  return codeBlocks
end

local function initializeAI(turtleStatus)
  local hasMiningProgram = turtleStatus and turtleStatus.hasSimpleMining
  local miningInfo = ""

  if hasMiningProgram then
    miningInfo = [[
This turtle has the "simple_mining.lua" program installed. You can use it to mine rectangular areas with these commands:
- "mine a [width] x [height] x [depth] area" - This will use simple_mining.lua to mine the specified dimensions
- "dig a [width] x [height] x [depth] hole" - Same as above, alternative phrasing
]]
  end

  local systemPrompt = [[You are TurtleGPT, an AI assistant specialized in controlling ComputerCraft turtles in Minecraft remotely via a wireless connection.
Your purpose is to interpret natural language commands into Lua code that controls the turtle.

Key turtle functions include:
- Movement: turtle.forward(), turtle.back(), turtle.up(), turtle.down(), turtle.turnLeft(), turtle.turnRight()
- Digging: turtle.dig(), turtle.digUp(), turtle.digDown()
- Placing: turtle.place(), turtle.placeUp(), turtle.placeDown()
- Inventory: turtle.select(slot), turtle.getItemCount(slot), turtle.getItemDetail(slot)
- Item Transfer: turtle.drop(), turtle.dropUp(), turtle.dropDown(), turtle.suck(), turtle.suckUp(), turtle.suckDown()
- Inspection: turtle.detect(), turtle.detectUp(), turtle.detectDown(), turtle.inspect(), turtle.inspectUp(), turtle.inspectDown()
- Fuel: turtle.getFuelLevel(), turtle.refuel(count)
- Combat: turtle.attack(), turtle.attackUp(), turtle.attackDown()

]] .. miningInfo .. [[

When interpreting commands, please:
1. Provide ONLY executable Lua code in code blocks (no explanations in the code)
2. AFTER the code, you can briefly explain what the code does
3. For complex tasks, break them down into simpler steps
4. Always handle errors and edge cases when possible

The user is talking to you through a wireless network. Your code will be sent to the turtle to execute.
]]

  addToHistory("user", systemPrompt)

  if turtleStatus then
    local statusPrompt = "Current turtle status:\n"
    statusPrompt = statusPrompt .. "- Fuel level: " .. tostring(turtleStatus.fuelLevel) .. "\n"
    statusPrompt = statusPrompt .. "- Inventory: " .. turtleStatus.itemCount .. " items in " .. turtleStatus.slotsUsed .. " slots\n"
    statusPrompt = statusPrompt .. "- Selected slot: " .. turtleStatus.selectedSlot
    addToHistory("user", statusPrompt)
  end

  local initialResponse = "I'm TurtleGPT, your wireless turtle control assistant. I'll help you control your ComputerCraft turtle using natural language commands. What would you like your turtle to do?"
  addToHistory("model", initialResponse)

  return initialResponse
end

local function saveApiKey()
  term.setTextColor(colors.cyan)
  write("Enter your Groq API key (gsk_...): ")
  term.setTextColor(colors.white)

  local key = read("*")
  if key and key ~= "" then
    settings.set("groq.api_key", key)
    settings.save()
    print("API key saved!")
  else
    print("API key not changed")
  end
end

local function showHelp()
  term.setTextColor(colors.yellow)
  print("=== TurtleAI Remote Client Help ===")
  term.setTextColor(colors.white)
  print("Type natural language commands to control your remote turtle.")
  print("")
  print("Networking Commands:")
  print("- scan [start] [end] - Scan for turtle servers")
  print("- connect <channel> - Connect to a turtle server")
  print("- status - Show current turtle status")
  print("")
  print("Special commands:")
  print("- exit: Exit the program")
  print("- help: Show this help message")
  print("- clear: Clear conversation history")
  print("- setkey: Set your Groq API key")
  print("- debug: Toggle debug mode")
end

local function toggleDebug()
  DEBUG = not DEBUG
  print("Debug mode: " .. (DEBUG and "ON" or "OFF"))
end

local function displayTurtleStatus(status)
  if not status then
    print("Could not retrieve turtle status!")
    return
  end

  term.setTextColor(colors.yellow)
  print("=== Turtle Status ===")
  term.setTextColor(colors.white)

  local fuelStr = status.fuelLevel == "unlimited" and "Unlimited" or tostring(status.fuelLevel)
  print("Fuel Level: " .. fuelStr)
  print("Selected Slot: " .. status.selectedSlot)

  print("")
  print("Inventory Summary:")
  print(status.itemCount .. " items in " .. status.slotsUsed .. " slots")

  if status.inventory then
    for slot, item in pairs(status.inventory) do
      print("  Slot " .. slot .. ": " .. item.name .. " x" .. item.count)
    end
  end

  print("")
  print("Installed Programs:")
  if status.hasSimpleMining then
    print("- simple_mining.lua (3D Mining)")
  else
    print("No special programs installed.")
  end
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)

  term.setTextColor(colors.yellow)
  print("=== TurtleAI Remote Client v" .. VERSION .. " ===")
  term.setTextColor(colors.white)
  print("Model: " .. MODEL)
  print("Control remote turtles with natural language")
  print("Type 'help' for available commands")

  local apiKey = settings.get("groq.api_key")
  if not apiKey or apiKey == "" then
    print("API key not set! Type 'setkey' to set it.")
    print("Get a free key at console.groq.com")
  end

  local connected = false
  local currentChannel = nil
  local turtleStatus = nil

  clearHistory()

  while true do
    if connected then
      term.setTextColor(colors.green)
      write("[Connected CH:" .. currentChannel .. "] > ")
    else
      term.setTextColor(colors.yellow)
      write("[Disconnected] > ")
    end

    term.setTextColor(colors.white)
    local input = read()

    if input:lower() == "exit" then
      break

    elseif input:lower() == "help" then
      showHelp()

    elseif input:lower() == "setkey" then
      saveApiKey()

    elseif input:lower() == "clear" then
      print(clearHistory())
      if connected then
        print("Reinitializing AI assistant...")
        local initMsg = initializeAI(turtleStatus)
        print(initMsg)
      end

    elseif input:lower() == "debug" then
      toggleDebug()

    elseif input:lower() == "status" then
      if connected then
        turtleStatus = getTurtleStatus(currentChannel)
        displayTurtleStatus(turtleStatus)
      else
        print("Not connected to a turtle. Use 'connect <channel>' first.")
      end

    elseif input:lower():find("^scan") == 1 then
      local parts = {}
      for part in input:gmatch("%S+") do table.insert(parts, part) end
      local startChannel = tonumber(parts[2]) or DEFAULT_CHANNEL
      local endChannel = tonumber(parts[3]) or (startChannel + 10)
      scanChannels(startChannel, endChannel)

    elseif input:lower():find("^connect%s+%d+") == 1 then
      local channelNum = tonumber(input:match("connect%s+(%d+)"))
      if channelNum then
        local success, status = connectToServer(channelNum)
        if success then
          connected = true
          currentChannel = channelNum
          turtleStatus = status
          print("Initializing AI assistant...")
          local initMsg = initializeAI(turtleStatus)
          print(initMsg)
        end
      else
        print("Invalid channel number")
      end

    elseif trim(input) ~= "" and connected then
      term.setTextColor(colors.cyan)
      print("Interpreting command...")
      term.setTextColor(colors.white)

      local response = generateContent(input)

      if not response or type(response) ~= "string" then
        print("Error: Invalid response from Groq AI")
        debugLog("Response type: " .. type(response))
      else
        local codeBlocks = extractCodeBlocks(response)

        if #codeBlocks == 0 then
          term.setTextColor(colors.red)
          print("No executable code found in the response.")
          term.setTextColor(colors.lightGray)
          print(response)
          term.setTextColor(colors.white)
        else
          term.setTextColor(colors.lightGray)
          print(response)
          term.setTextColor(colors.white)

          write("Execute this code? (y/n): ")
          local confirm = read():lower()

          if confirm == "y" then
            for i, codeBlock in ipairs(codeBlocks) do
              print("Executing code block " .. i .. " of " .. #codeBlocks)

              local success, output, newStatus = executeRemote(currentChannel, codeBlock)

              if success then
                if output and #output > 0 then
                  for _, line in ipairs(output) do print(line) end
                end
                if newStatus then turtleStatus = newStatus end
              else
                term.setTextColor(colors.red)
                print("Execution error: " .. tostring(output))
                term.setTextColor(colors.white)
                break
              end
            end
            print("Command execution completed.")
          else
            print("Execution cancelled.")
          end
        end
      end

    elseif trim(input) ~= "" and not connected then
      print("Not connected to a turtle. Use 'connect <channel>' first.")
    end

    print("")
  end

  print("Exiting TurtleAI Client. Goodbye!")
end

local success, err = pcall(main)
if not success then
  term.setTextColor(colors.red)
  print("Program crashed with error:")
  print(err)
  term.setTextColor(colors.white)
  print("Press any key to exit...")
  os.pullEvent("key")
end
