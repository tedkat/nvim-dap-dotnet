-- Module: Dotnet C# Project Info
-- This module provides functionality to locate and build .NET artifact DLLs for debugging.

local M = {}

local Path = require("plenary.path")
local Snacks = require("snacks")
local is_windows = function()
	return (vim.fn.has("win64") or vim.fn.has("win32") or vim.fn.has("win16")) == 1
end

-- Vim Regex Strings identify start and end match for line
local PropertiesMatch = {
	Assembly = "<AssemblyName>(.-)</AssemblyName>",
	Artifacts = "<ArtifactsPath>%$%(MSBuildThisFileDirectory%)(.-)</ArtifactsPath>",
	SLNXProject = 'Project Path="(.-)"',
	SLNProject = 'Project%(".-"%) = ".-", "(.-%.csproj)"',
}

local function D(info)
	vim.notify(vim.inspect(info), vim.log.levels.DEBUG, { title = "nvim-dap-dotnet" })
end

local function E(info)
	vim.notify(vim.inspect(info), vim.log.levels.ERROR, { title = "nvim-dap-dotnet" })
end

-- Snacks Picker
local picker = function(options, on_select_cb)
	if #options == 0 then
		error("No options provided, minimum 1 is required")
	end
	if #options == 1 then
		on_select_cb(options[1])
		return
	end

	local picker_items = {}
	for index, option in ipairs(options) do
		local display_text = index .. ". " .. option.assembly
		table.insert(picker_items, { text = display_text, option = option })
	end

	Snacks.picker.pick(nil, {
		items = picker_items,
		format = "text",
		title = "Select Project",
		layout = "select",
		confirm = function(picker, item)
			picker:close()
			on_select_cb(item.option)
		end,
	})
end

-- Implement async => sync picker
local pick_sync = function(options)
	local co = coroutine.running()
	local selected = nil
	local selector = function(i)
		selected = i
		if coroutine.status(co) ~= "running" then
			coroutine.resume(co)
		end
	end
	picker(options, selector)

	if not selected then
		coroutine.yield()
	end

	return selected
end

--
local function get_property_matches_from_file(filepath, property_match)
	local properties = {}
	local file = io.open(filepath, "r")
	if not file then
		E("Getting Property Matches [[" .. property_match .. "]] from File: Could not open file: " .. filepath)
		return {}
	end
	for line in file:lines() do
		if line:match("<!%-%-%s+<ArtifactsPath>") then
			goto continue
		end
		local match = line:match(property_match)
		if match then
			table.insert(properties, match)
		end
		::continue::
	end
	file:close()
	return properties
end

--
-- Find solution directory between start path and end path
--
local function find_solution_file(start_path, stop_path)
	local path = Path:new(start_path)
	local working_directory = Path:new(stop_path)
	while true do
		local solutions = vim.fn.glob(path:absolute() .. "/*.{slnx,sln}", false, true)
		if #solutions > 0 then
			return solutions[1]
		end
		local parent = path:parent()
		if path:absolute() == working_directory:absolute() or parent:absolute() == path:absolute() then
			return nil
		end
		path = parent
	end
end

--
-- Find the root csproj file of a .NET project
--
local function find_csproj_file(start_path)
	local path = Path:new(start_path)
	while true do
		local csprojs = vim.fn.glob(path .. "/*.csproj", false, true)
		if #csprojs > 0 then
			return csprojs[1]
		end
		local parent = path:parent()
		if parent:absolute() == path:absolute() then
			return nil
		end
		path = parent
	end
end

local function get_highest_net_folder(path)
	local dirs = {}
	for _, dir in ipairs(vim.fn.glob(path .. "/net*", false, true)) do
		local prime, secondary = dir:match("net(%d+)(%.%d+)")
		if prime then
			table.insert(dirs, { dir = dir, version = prime .. secondary })
		end
	end
	-- Sort by numeric version
	table.sort(dirs, function(a, b)
		return tonumber(a.version) > tonumber(b.version)
	end)

	return dirs[1].dir or nil
end

-- Current Info
local function current_info()
	local buffer_file_name = vim.api.nvim_buf_get_name(0)
	if is_windows() then
		buffer_file_name = string.gsub(buffer_file_name, "/", "\\\\")
	end
	local file_path = Path:new(buffer_file_name)
	local directory_path = file_path:parent()
	return {
		file = file_path:absolute(),
		directory = directory_path:absolute(),
		working_directory = vim.fn.getcwd(),
	}
end

-- Solution Info
local function solution_info(start_path, stop_path)
	local solution = { file = "", directory = "", artifacts = {} }
	local file = find_solution_file(start_path, stop_path)
	if file then -- Try to build up artifacts for solution
		local file_path = Path:new(file)
		solution.file = file_path:absolute()
		solution.directory = file_path:parent():absolute()
		local props_path = Path:new(solution.directory, "Directory.Build.props")
		if props_path:exists() then
			-- found special soloution wide build file
			local artifacts = get_property_matches_from_file(props_path:absolute(), PropertiesMatch.Artifacts)
			if #artifacts > 0 then
				solution.artifacts.partial = artifacts[1]
				local artifacts_path = Path:new(solution.directory, artifacts[1])
				if solution.artifacts.partial then
					if artifacts_path:exists() then
						solution.artifacts.directory = artifacts_path:absolute()
					end
				end
			end
		end
	end
	return solution
end

-- Project Info
local function project_info(csproj)
	local csproj_path = Path:new(csproj)
	if csproj_path:exists() then
		local project = { file = csproj, assembly = "", artifact = "", name = "" }
		local filename = csproj_path:absolute():match("([^/%\\]+)$")
		local ext_index = filename:find(".-%.([^%.]*)$")
		if ext_index then
			project.name = filename:gsub("%.[^%.]*$", "")
		end
		local assemblies = get_property_matches_from_file(csproj, PropertiesMatch.Assembly)
		if #assemblies > 0 then
			project.assembly = assemblies[1] -- only pull first assembly found in file
		else
			project.assembly = project.name -- last chance for assembly is same as base name for .csproj
		end
		local bin_debug_path = Path:new(csproj_path:parent(), "bin", "Debug")
		if bin_debug_path:exists() then
			local highest_net_folder = get_highest_net_folder(bin_debug_path:absolute())
			if highest_net_folder then
				local artifact_path = Path:new(highest_net_folder, project["assembly"] .. ".dll")
				if artifact_path then
					project.artifact = artifact_path:absolute()
				end
			end
		end
		return project
	end
	return {}
end

-- Projects Info
local function projects_info(current, solution)
	local projects = {}
	-- First Try by solution to get list of projects
	if solution.file ~= "" then
		local property_match
		local suffix = solution.file:match("%.([^%p%s]+)$")
		local type = string.lower(suffix)
		if type == "slnx" then
			property_match = PropertiesMatch.SLNXProject
		elseif type == "sln" then
			property_match = PropertiesMatch.SLNProject
		end
		if property_match then
			local csprojs = get_property_matches_from_file(solution.file, property_match)
			if #csprojs > 0 then
				for _, csproj in ipairs(csprojs) do
					if not is_windows() then
						csproj = string.gsub(csproj, "\\", "/")
					end
					local csproj_path = Path:new(csproj)
					local project = project_info(csproj_path:absolute())
					if project.file then
						table.insert(projects, project)
					else
						E("Found csproj in solution, but file [[" .. csproj_path .. "]] does not exist")
					end
				end
			end
		end
	-- No solution found assume this is the project
	else
		local csproj = find_csproj_file(current.directory)
		if not csproj then
			error("Last Chance: Could not find csproj file!")
		end
		local csproj_path = Path:new(csproj)
		local project = project_info(csproj_path:absolute())
		if project.file then
			table.insert(projects, project)
		else
			error("Last Chance: Could not gather project info from [[" .. csproj_path .. "]]")
		end
	end
	return projects
end

-- Initialize Dotnet C# project info
local function csharp_info()
	local current = current_info()
	local solution = solution_info(current.directory, current.working_directory)
	return { current = current, solution = solution, projects = projects_info(current, solution) }
end

-- @brief Builds and returns the absolute path to the debug DLL of the selected project.
-- @param None
-- @return The absolute path to the debug DLL file.
function M.build_artifact_dll_path()
	local info = csharp_info()
	local selected_project = pick_sync(info.projects)

	if not selected_project then
		error("Could Not file Artifact to Run!")
	end

	local dll_path

	if selected_project.artifact == "" then
		dll_path = Path:new(
			info.solution.artifacts.directory,
			"bin",
			selected_project.name,
			"debug",
			selected_project.assembly .. ".dll"
		):absolute()
	else
		dll_path = selected_project.artifact
	end

	if not Path:new(dll_path):is_file() then
		error("Built artifact does not exist! => " .. dll_path)
	end

	print("Launching: " .. dll_path)
	return dll_path
end

return M
