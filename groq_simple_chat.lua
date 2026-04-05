-- Groq Chat for ComputerCraft
-- Simple conversational AI, no documentation system
local MODEL, VERSION = "llama-3.3-70b-versatile", "1.0.0"
local DEBUG = false

local function jsonEscape(str)
  return str and str:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
                  :gsub('\r', '\\r'):gsub('\t', '\\t') or ""
end

local function jsonUnescape(str)
  return str and str:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t')
               :gsub('\\"', '"'):gsub('\\\\', '\\') or ""
end

local function parseJSON(json)
  local content = json:match('"content"%s*:%s*"(.-[^\\])"') or json:match('"content"%s*:%s*"(.-)"')
  return content and {text = jsonUnescape(content)} or {}
end

settings.define("groq.api_key", {description = "Groq API key", default = "", type = "string"})
settings.load()

local conversationHistory = {}

local function addToHistory(role, message)
  table.insert(conversationHistory, {role = role, text = message})
end

local function clearHistory()
  conversationHistory = {}
  return "Conversation cleared!"
end

local function callGroq(prompt)
  local apiKey = settings.get("groq.api_key")
  if not apiKey or apiKey == "" then return nil, "API key not set. Type 'setkey'." end

  addToHistory("user", prompt)

  local messages = {}
  for _, msg in ipairs(conversationHistory) do
    local role = msg.role == "model" and "assistant" or msg.role
    table.insert(messages, '{"role":"' .. role .. '","content":"' .. jsonEscape(msg.text) .. '"}')
  end

  local requestBody = '{"model":"' .. MODEL .. '","messages":[' .. table.concat(messages, ",") .. '],"max_tokens":500}'

  local response = http.post(
    "https://api.groq.com/openai/v1/chat/completions",
    requestBody,
    {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. apiKey
    }
  )

  if not response then
    table.remove(conversationHistory)
    return nil, "Could not connect to Groq API"
  end

  local responseText = response.readAll()
  response.close()

  local result = parseJSON(responseText)
  if not result.text then
    table.remove(conversationHistory)
    if DEBUG then print("Raw: " .. responseText:sub(1, 200)) end
    return nil, "Failed to parse response"
  end

  addToHistory("model", result.text)
  return result.text
end

local function saveConversation(filename)
  if not filename or filename == "" then
    filename = "chat_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  elseif not filename:match("%.txt$") then
    filename = filename .. ".txt"
  end

  local file = fs.open(filename, "w")
  if not file then return "Error: Could not create " .. filename end

  for i, message in ipairs(conversationHistory) do
    file.writeLine((message.role == "user" and "You: " or "Groq: ") .. message.text)
    if i % 2 == 0 then file.writeLine("") end
  end

  file.close()
  return "Saved to " .. filename
end

local function main()
  term.clear()
  term.setCursorPos(1, 1)

  term.setTextColor(colors.yellow)
  print("=== Groq Chat v" .. VERSION .. " ===")
  term.setTextColor(colors.white)
  print("Commands: exit, setkey, clear, save, debug")
  print("-------------------------------------------")

  if not settings.get("groq.api_key") or settings.get("groq.api_key") == "" then
    print("API key not set! Type 'setkey'.")
    print("Get a free key at console.groq.com")
  end

  print("")

  while true do
    term.setTextColor(colors.yellow)
    write("You: ")
    term.setTextColor(colors.white)

    local input = read()
    local command = (input:match("^%s*(%S+)") or ""):lower()

    if command == "exit" then
      break

    elseif command == "setkey" then
      term.setTextColor(colors.cyan)
      write("Groq API key (gsk_...): ")
      term.setTextColor(colors.white)
      local key = read("*")
      if key and key ~= "" then
        settings.set("groq.api_key", key)
        settings.save()
        print("API key saved!")
      else
        print("Not changed.")
      end

    elseif command == "clear" then
      term.setTextColor(colors.cyan)
      print("Groq: ")
      term.setTextColor(colors.white)
      print(clearHistory())

    elseif command == "debug" then
      DEBUG = not DEBUG
      print("Debug: " .. (DEBUG and "ON" or "OFF"))

    elseif command:match("^save") then
      print(saveConversation(input:match("^save%s+(.+)$")))

    elseif input ~= "" then
      term.setTextColor(colors.cyan)
      print("Groq: ")
      term.setTextColor(colors.white)

      local response, err = callGroq(input)
      if not response then
        term.setTextColor(colors.red)
        print("Error: " .. err)
        term.setTextColor(colors.white)
      else
        print(response)
      end
    end

    print("")
  end

  print("Goodbye!")
end

main()
