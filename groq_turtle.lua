-- Turtle Groq Shell
-- Adapted from gotoundo/TurtleAI (originally gemini_turtle.lua) to use Groq API
-- A program that uses Groq AI to interpret natural language commands into turtle actions

local MODEL = "llama-3.3-70b-versatile"
local VERSION = "1.0.4"

local DEBUG = true

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

settings.define("groq.api_key", {
  description = "Your Groq API key from console.groq.com",
  default = "",
  type = "string"
})

local conversationHistory = {}

local function addToHistory(role, message)
  table.insert(conversationHistory, {role = role, text = message})
end

local function buildRequestBody()
  local messages = {}

  for _, message in ipairs(conversationHistory) do
    -- Gemini used "model", OpenAI/Groq uses "assistant"
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

local function clearHistory()
  conversationHistory = {}
  return "Conversation history cleared. Starting fresh!"
end

local turtleExecutionContext = {
  lastCommand = "",
  isInterpreting = false,
  executeTimer = nil,
  maxCommandsPerTick = 1,
  commandsExecuted = 0,
  commandQueue = {},
  inProgress = false
}

local function checkSimpleMiningExists()
  return fs.exists("simple_mining.lua")
end

local function runSimpleMining(width, height, depth)
  if not checkSimpleMiningExists() then
    return false, "simple_mining.lua not found on this turtle"
  end
  return pcall(function()
    shell.run("simple_mining", tostring(width), tostring(height), tostring(depth))
  end)
end

local function initializeAI()
  local hasMiningProgram = checkSimpleMiningExists()
  local miningInfo = ""

  if hasMiningProgram then
    miningInfo = [[
This turtle has the "simple_mining.lua" program installed. You can use it to mine rectangular areas with these commands:
- "mine a [width] x [height] x [depth] area" - This will use simple_mining.lua to mine the specified dimensions
- "dig a [width] x [height] x [depth] hole" - Same as above, alternative phrasing

The simple_mining program will:
1. Mine in a 3D snake pattern for efficiency
2. Return to deposit items when inventory is full
3. Continue from where it left off
4. Handle fuel management
5. Return to original position when done
    ]]
  end

  local systemPrompt = [[You are TurtleGPT, an AI assistant specialized in controlling ComputerCraft turtles in Minecraft.
Your purpose is to interpret natural language commands into Lua code that controls the turtle.
The turtle is a programmable robot that can move, dig, place blocks, and interact with the world.

For safety, you should:
1. Always confirm DESTRUCTIVE operations before executing them
2. Never directly execute code with 'load' or other unsafe methods
3. Keep commands reasonably sized for better control

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

For mining commands like "mine a 5x5x5 area", check if they match the pattern for the simple_mining program. If they do, generate code that calls the function runSimpleMining(width, height, depth) instead of creating a custom mining algorithm.

Example command: "Move forward 5 blocks then turn right"
Example response:
```lua
for i = 1, 5 do
  if not turtle.forward() then
    print("Path blocked at step " .. i)
    break
  end
end
turtle.turnRight()
```
This will move the turtle forward 5 blocks, stopping if it encounters an obstacle, then turn right.
]]

  addToHistory("user", systemPrompt)

  local initialResponse = "I'm TurtleGPT, your turtle control assistant. I'll help you control your ComputerCraft turtle using natural language commands. What would you like your turtle to do?"
  addToHistory("model", initialResponse)

  return initialResponse
end

local function safeExecute(codeString)
  local success, result = pcall(function()
    local env = {
      turtle = turtle,
      print = print,
      tonumber = tonumber,
      tostring = tostring,
      math = math,
      string = string,
      table = table,
      pairs = pairs,
      ipairs = ipairs,
      next = next,
      type = type,
      select = select,
      unpack = unpack,
      pcall = pcall,
      sleep = sleep,
      os = {
        pullEvent = os.pullEvent,
        time = os.time,
        clock = os.clock,
        startTimer = os.startTimer
      },
      runSimpleMining = runSimpleMining,
      checkSimpleMiningExists = checkSimpleMiningExists,
      shell = {run = shell.run}
    }

    setmetatable(env, {
      __index = function(_, key)
        if _G[key] ~= nil and
           key ~= "load" and
           key ~= "loadstring" and
           key ~= "dofile" and
           key ~= "loadfile" then
          return _G[key]
        end
        return nil
      end
    })

    local func, err = load(codeString, "turtleCommand", "t", env)
    if not func then
      return false, "Compilation error: " .. (err or "unknown error")
    end

    return func()
  end)

  if not success then
    return false, "Execution error: " .. tostring(result)
  end

  return true, result
end

local function processCommandQueue()
  if #turtleExecutionContext.commandQueue == 0 then
    turtleExecutionContext.inProgress = false
    return
  end

  turtleExecutionContext.inProgress = true

  local cmd = table.remove(turtleExecutionContext.commandQueue, 1)

  term.setTextColor(colors.lightBlue)
  print("Executing command...")
  term.setTextColor(colors.white)

  local success, result = safeExecute(cmd)

  if not success then
    term.setTextColor(colors.red)
    print("Error: " .. tostring(result))
    term.setTextColor(colors.white)
    turtleExecutionContext.commandQueue = {}
    turtleExecutionContext.inProgress = false
    return
  end

  if #turtleExecutionContext.commandQueue > 0 then
    os.sleep(0.5)
    processCommandQueue()
  else
    turtleExecutionContext.inProgress = false
    print("Command execution completed.")
  end
end

local function extractCodeBlocks(response)
  debugLog("Extracting code blocks from response")

  if type(response) ~= "string" then
    debugLog("Error: Response is not a string")
    return {}
  end

  local codeBlocks = {}

  for codeBlock in response:gmatch("```lua(.-)```") do
    debugLog("Found lua code block: " .. codeBlock:sub(1, 30) .. (codeBlock:len() > 30 and "..." or ""))
    local cleanedBlock = codeBlock:gsub("^%s+", ""):gsub("%s+$", "")
    table.insert(codeBlocks, cleanedBlock)
  end

  if #codeBlocks == 0 then
    debugLog("No lua code blocks found, looking for generic code blocks")
    for codeBlock in response:gmatch("```(.-)```") do
      debugLog("Found generic code block: " .. codeBlock:sub(1, 30) .. (codeBlock:len() > 30 and "..." or ""))
      local cleanedBlock = codeBlock:gsub("^%s+", ""):gsub("%s+$", "")
      table.insert(codeBlocks, cleanedBlock)
    end
  end

  debugLog("Extracted " .. tostring(#codeBlocks) .. " code blocks")
  return codeBlocks
end

local function handleTurtleCommand(userInput)
  local width, height, depth = userInput:match("mine%s+a%s+(%d+)%s*x%s*(%d+)%s*x%s*(%d+)")
  if not width then
    width, height, depth = userInput:match("dig%s+a%s+(%d+)%s*x%s*(%d+)%s*x%s*(%d+)")
  end

  if width and height and depth then
    width, height, depth = tonumber(width), tonumber(height), tonumber(depth)

    if checkSimpleMiningExists() then
      debugLog("Direct mining command detected: " .. width .. "x" .. height .. "x" .. depth)

      print("Mining command detected. Running simple_mining.lua with dimensions:")
      print("Width: " .. width .. ", Height: " .. height .. ", Depth: " .. depth)

      write("Execute mining operation? (y/n): ")
      local input = read()

      if input:lower() == "y" then
        local success, err = runSimpleMining(width, height, depth)
        if not success then
          term.setTextColor(colors.red)
          print("Error running mining program: " .. tostring(err))
          term.setTextColor(colors.white)
        end
      else
        print("Mining operation cancelled.")
      end

      return
    end
  end

  term.setTextColor(colors.cyan)
  print("Interpreting command...")
  term.setTextColor(colors.white)

  debugLog("Sending command: " .. userInput)
  local response = generateContent(userInput)

  if not response or type(response) ~= "string" then
    term.setTextColor(colors.red)
    print("Error: Invalid response from Groq AI")
    debugLog("Response type: " .. type(response))
    term.setTextColor(colors.white)
    return
  end

  local codeBlocks = extractCodeBlocks(response)

  if #codeBlocks == 0 then
    term.setTextColor(colors.red)
    print("No executable code found in the response.")
    term.setTextColor(colors.lightGray)
    print(response)
    term.setTextColor(colors.white)
    return
  end

  term.setTextColor(colors.lightGray)
  print(response)
  term.setTextColor(colors.white)

  debugLog("Adding " .. tostring(#codeBlocks) .. " blocks to queue")
  turtleExecutionContext.commandQueue = {}

  for i, codeBlock in ipairs(codeBlocks) do
    debugLog("Adding block " .. i .. " to queue")
    table.insert(turtleExecutionContext.commandQueue, codeBlock)
  end

  write("Execute this code? (y/n): ")
  local input = read()

  if input:lower() == "y" then
    if not turtleExecutionContext.inProgress then
      processCommandQueue()
    else
      print("Already executing commands. Please wait.")
    end
  else
    turtleExecutionContext.commandQueue = {}
    print("Execution cancelled.")
  end
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
  print("=== Turtle Groq Shell Help ===")
  term.setTextColor(colors.white)
  print("Type natural language commands to control your turtle.")
  print("For example: 'move forward 3 blocks and turn right'")
  print("")

  if checkSimpleMiningExists() then
    print("Direct Mining Commands:")
    print("- mine a 5x5x5 area")
    print("- dig a 3x2x10 hole")
    print("These will use the simple_mining.lua program directly.")
    print("")
  end

  print("Special commands:")
  print("- exit: Exit the program")
  print("- help: Show this help message")
  print("- clear: Clear conversation history")
  print("- setkey: Set your Groq API key")
  print("- status: Show turtle status (fuel, inventory, etc.)")
  print("- debug: Toggle debug mode")
end

local function showTurtleStatus()
  term.setTextColor(colors.yellow)
  print("=== Turtle Status ===")
  term.setTextColor(colors.white)

  local fuelLevel = turtle.getFuelLevel()
  print("Fuel Level: " .. (fuelLevel == "unlimited" and "Unlimited" or tostring(fuelLevel)))

  local selectedSlot = turtle.getSelectedSlot()
  print("Selected Slot: " .. selectedSlot)

  local itemDetail = turtle.getItemDetail()
  if itemDetail then
    print("Current Item: " .. itemDetail.name .. " (Count: " .. itemDetail.count .. ")")
  else
    print("Current Item: None")
  end

  print("")
  print("Inventory Summary:")

  local totalItems, slotsUsed = 0, 0

  for i = 1, 16 do
    local count = turtle.getItemCount(i)
    if count > 0 then
      slotsUsed = slotsUsed + 1
      totalItems = totalItems + count

      local detail = turtle.getItemDetail(i)
      local name = detail and detail.name or "Unknown"

      if i == selectedSlot then term.setTextColor(colors.yellow) end
      print("  Slot " .. i .. ": " .. name .. " x" .. count)
      term.setTextColor(colors.white)
    end
  end

  print("")
  print("Total: " .. totalItems .. " items in " .. slotsUsed .. " slots")

  print("")
  print("Installed Special Programs:")
  if checkSimpleMiningExists() then
    print("- simple_mining.lua (3D Mining)")
  else
    print("No special programs installed.")
  end
end

local function toggleDebug()
  DEBUG = not DEBUG
  print("Debug mode: " .. (DEBUG and "ON" or "OFF"))
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)

  term.setTextColor(colors.yellow)
  print("=== Turtle Groq Shell v" .. VERSION .. " ===")
  term.setTextColor(colors.white)
  print("Model: " .. MODEL)
  print("Control your turtle with natural language")
  print("Type 'help' for available commands")
  print("")

  local apiKey = settings.get("groq.api_key")
  if not apiKey or apiKey == "" then
    print("API key not set! Type 'setkey' to set it.")
    print("Get a free key at console.groq.com")
  end

  print("Initializing AI assistant...")
  local initMsg = initializeAI()

  term.setTextColor(colors.lightGray)
  print(initMsg)
  term.setTextColor(colors.white)
  print("")

  while true do
    if turtleExecutionContext.inProgress then
      print("Command execution in progress. Press Enter to start a new command.")
    end

    term.setTextColor(colors.yellow)
    write("> ")
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
      print("Reinitializing assistant...")
      local initMsg = initializeAI()
      term.setTextColor(colors.lightGray)
      print(initMsg)
      term.setTextColor(colors.white)
    elseif input:lower() == "status" then
      showTurtleStatus()
    elseif input:lower() == "debug" then
      toggleDebug()
    elseif trim(input) ~= "" then
      handleTurtleCommand(input)
    end

    print("")
  end

  print("Exiting Turtle Groq Shell. Goodbye!")
end

local function runWithErrorHandling()
  local success, err = pcall(main)
  if not success then
    term.setTextColor(colors.red)
    print("Program crashed with error:")
    print(err)
    term.setTextColor(colors.white)
    print("Press any key to exit...")
    os.pullEvent("key")
  end
end

runWithErrorHandling()
