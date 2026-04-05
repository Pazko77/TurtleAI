-- GitHub repository file downloader using ComputerCraft http API

-- ========== CONFIGURATION PARAMETERS ==========
-- Replace with your repository details
local owner = "Pazko77"
local repo = "TurtleAI"
local branch = "main" -- or "master" or another branch name

-- Files to download (at root level of the repository)
local filesToDownload = {
  "groq_chat.lua",
  "turtle_ai_client.lua",
  -- Add more individual files as needed
}

-- Folders to download (including all files in those folders)
local foldersToDownload = {
  "cc_docs/",
  -- Add more folders as needed (make sure to include the trailing slash)
}

-- Base directory for local saving
local localBaseDir = "" -- Empty string saves to current directory, or specify a path
-- =============================================

-- Optional: Add your personal access token for private repos or to avoid rate limits
local headers = {
  -- ["Authorization"] = "token YOUR_PERSONAL_ACCESS_TOKEN"
  ["User-Agent"] = "ComputerCraft/1.0"
}

-- Function to ensure a directory exists
local function ensureDirectoryExists(path)
  if not fs.exists(path) then
    fs.makeDir(path)
    print("Created directory: " .. path)
  end
end

-- Function to download a single file
local function downloadFile(fileUrl, filePath)
  print("Downloading: " .. filePath)
  
  local response = http.get(fileUrl, headers)
  if response then
    local content = response.readAll()
    response.close()
    
    -- Ensure parent directory exists
    local parentDir = fs.getDir(filePath)
    if parentDir ~= "" then
      ensureDirectoryExists(parentDir)
    end
    
    -- Write the content to the file
    local file = fs.open(filePath, "w")
    file.write(content)
    file.close()
    
    return true
  else
    print("Failed to download: " .. filePath)
    return false
  end
end

-- Function to download an individual file from the repository
local function downloadIndividualFile(fileName)
  local apiUrl = "https://api.github.com/repos/" .. owner .. "/" .. repo .. 
                "/contents/" .. fileName .. "?ref=" .. branch
  
  local response, errorMsg = http.get(apiUrl, headers)
  if not response then
    print("Error fetching file info for " .. fileName .. ": " .. tostring(errorMsg))
    return false
  end
  
  local fileInfo = textutils.unserializeJSON(response.readAll())
  response.close()
  
  local localFilePath = fs.combine(localBaseDir, fileName)
  return downloadFile(fileInfo.download_url, localFilePath)
end

-- Function to download all files in a folder
local function downloadFolder(folderPath)
  -- Ensure the folder path ends with a slash
  if not folderPath:endsWith("/") then
    folderPath = folderPath .. "/"
  end

  local apiUrl = "https://api.github.com/repos/" .. owner .. "/" .. repo .. 
                "/contents/" .. folderPath .. "?ref=" .. branch
  
  local response, errorMsg = http.get(apiUrl, headers)
  if not response then
    print("Error fetching folder contents for " .. folderPath .. ": " .. tostring(errorMsg))
    return 0, 0
  end
  
  local contents = textutils.unserializeJSON(response.readAll())
  response.close()
  
  local fileCount = 0
  local successCount = 0
  
  for _, item in ipairs(contents) do
    if item.type == "file" then
      fileCount = fileCount + 1
      
      local localFilePath = fs.combine(localBaseDir, item.path)
      if downloadFile(item.download_url, localFilePath) then
        successCount = successCount + 1
      end
    end
  end
  
  return fileCount, successCount
end

-- Add string.endsWith if it doesn't exist
if not string.endsWith then
  function string.endsWith(str, ending)
    return ending == "" or str:sub(-#ending) == ending
  end
end

-- Main execution
print("Starting GitHub repository downloader")
print("Repository: " .. owner .. "/" .. repo .. " (branch: " .. branch .. ")")

-- Create base directory if needed
if localBaseDir ~= "" then
  ensureDirectoryExists(localBaseDir)
end

-- Download individual files
local totalIndividualFiles = #filesToDownload
local successfulIndividualFiles = 0

print("\n=== Downloading individual files ===")
for _, fileName in ipairs(filesToDownload) do
  if downloadIndividualFile(fileName) then
    successfulIndividualFiles = successfulIndividualFiles + 1
  end
end

-- Download folders
local totalFolderFiles = 0
local successfulFolderFiles = 0

print("\n=== Downloading folders ===")
for _, folderPath in ipairs(foldersToDownload) do
  print("Processing folder: " .. folderPath)
  local folderFileCount, folderSuccessCount = downloadFolder(folderPath)
  totalFolderFiles = totalFolderFiles + folderFileCount
  successfulFolderFiles = successfulFolderFiles + folderSuccessCount
end

-- Print summary
print("\n=== Download Summary ===")
print("Individual files: " .. successfulIndividualFiles .. "/" .. totalIndividualFiles)
print("Files from folders: " .. successfulFolderFiles .. "/" .. totalFolderFiles)
print("Total files: " .. (successfulIndividualFiles + successfulFolderFiles) .. 
      "/" .. (totalIndividualFiles + totalFolderFiles))
print("Download complete!")

-- Find this line at the end of the main function
print("Exiting TurtleAI Downloader...")
