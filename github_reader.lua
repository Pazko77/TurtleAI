-- GitHub repository content fetcher using ComputerCraft http API
-- Replace with your details
local owner = "Pazko77"
local repo = "TurtleAI"
local path = "" -- Empty string for root directory, or specific path like "src"
local branch = "main" -- or "master" or another branch name

-- GitHub API endpoint for contents
local url = "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/contents/" .. path .. "?ref=" .. branch

-- Optional: Add your personal access token for private repos or to avoid rate limits
local headers = {
  -- ["Authorization"] = "token YOUR_PERSONAL_ACCESS_TOKEN"
  ["User-Agent"] = "ComputerCraft/1.0"
}

-- Make the HTTP request
local response, errorMsg, httpResponse = http.get(url, headers)

if response then
  -- Parse the JSON response
  local responseData = response.readAll()
  response.close()
  
  -- Parse JSON (requires a JSON parsing function)
  local success, contents = pcall(textutils.unserializeJSON, responseData)
  
  if success then
    -- Filter for files only
    local filenames = {}
    for _, item in ipairs(contents) do
      if item.type == "file" then
        table.insert(filenames, item.name)
      end
    end
    
    -- Print the filenames
    for _, name in ipairs(filenames) do
      print(name)
    end
  else
    print("Error parsing JSON response: " .. tostring(contents))
  end
else
  print("Error: " .. tostring(errorMsg))
  if httpResponse then
    print("Response code: " .. httpResponse.getResponseCode())
  end
end
