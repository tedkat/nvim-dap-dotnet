# nvim-dap-dotnet

## nvim-dap-dotnet: .NET C# Project Debugging Artifact Locator

This module provides functionality to locate and identify .NET project artifact DLLs, facilitating their use in debugging sessions, particularly within `nvim-dap`.

### Public Functionality

#### `build_artifact_dll_path()`

This function is responsible for interactively finding a .NET C# project and determining the absolute path to its debug DLL artifact.

**Purpose:**
It scans the current Neovim workspace for .NET solution (`.sln`, `.slnx`) and project (`.csproj`) files. If multiple projects are found, it presents a user interface (powered by `Snacks.nvim`) to allow the user to select the desired project. Once a project is selected, it attempts to resolve the path to its compiled debug DLL.

**How it works:**

1.  **Current Context:** Gathers information about the current file, directory, and Neovim's working directory.
2.  **Solution Discovery:** Searches for a `.sln` or `.slnx` file in the current directory or its parent directories up to the working directory.
3.  **Project Discovery:**
    - If a solution file is found, it parses the solution file to list all associated `.csproj` files.
    - If no solution file is found, it attempts to locate a `.csproj` file in the current directory or its parents, assuming a single-project context.
4.  **Project Selection:** If more than one project is identified, a picker UI is displayed to the user to choose the target project.
5.  **Artifact Path Resolution:** For the selected project, it determines the path to the debug DLL, typically located in `bin/Debug/netX.Y/ProjectName.dll`. It prioritizes paths specified in `Directory.Build.props` or the project's `.csproj` file.
6.  **Validation:** Verifies that the resolved DLL file actually exists on the filesystem.

**Returns:**

- A string representing the absolute path to the debug DLL file of the selected project.

**Errors:**
This function will `error` and halt execution if:

- No project artifact can be found to run (e.g., no projects discovered or user cancels selection).
- The determined debug DLL file does not exist on the filesystem.
- A `.csproj` file is identified in a solution, but the file itself does not exist.
- In a single-project context (no solution found), it fails to locate a `.csproj` file.
- In a single-project context, it fails to gather project information from the located `.csproj` file.

**Usage Example (Conceptual, typically called by `nvim-dap` configuration):**

```lua
-- This function is intended to be used as a source for dap configuration
-- For instance, in an nvim-dap setup:
local dap = require('dap')
local dap_dotnet = require('nvim-dap-dotnet')

dap.configurations["cs"] = {
      {
        type = "netcoredbg",
        name = "Auto Run Artifact",
        request = "launch",
        program = function()
          return dap_dotnet.build_artifact_dll_path()
        end,
        cwd = "${fileDirname}",
        env = {
          ASPNETCORE_ENVIRONMENT = "Development",
          ASPNETCORE_HOSTINGSTARTUPASSEMBLIES = "Microsoft.AspNetCore.Watch.BrowserRefresh;Microsoft.AspNetCore.SpaProxy;Microsoft.WebTools.BrowserLink.Net",
          ASPNETCORE_HTTPS_PORT = "5001",
          ASPNETCORE_URLS = "https://localhost:5001;http://localhost:5000",
        },
      },
}
```

### Dependencies

This module relies on the following Neovim plugins/libraries:

- [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim) for file system path manipulation.
- [`snacks.nvim`](https://github.com/davidmh/snacks.nvim) for the interactive project picker UI.
