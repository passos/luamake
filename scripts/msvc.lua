local sp = require 'bee.subprocess'
local fs = require 'bee.filesystem'

local function Is64BitWindows()
    -- https://docs.microsoft.com/en-us/archive/blogs/david.wang/howto-detect-process-bitness
    return os.getenv "PROCESSOR_ARCHITECTURE" == "AMD64" or os.getenv "PROCESSOR_ARCHITEW6432" == "AMD64"
end

local ProgramFiles = Is64BitWindows() and 'ProgramFiles(x86)' or 'ProgramFiles'
local vswhere = os.getenv(ProgramFiles)..'/Microsoft Visual Studio/Installer/vswhere.exe'
local need = { LIB = true, LIBPATH = true, PATH = true, INCLUDE = true }

local function createfile(filename, content)
    local f = assert(io.open(filename:string(), 'w'))
    if content then
        f:write(content)
    end
    f:close()
end

local function strtrim(str)
    return str:gsub("^%s*(.-)%s*$", "%1")
end

local InstallDir
local function installpath()
    if InstallDir then
        return InstallDir
    end
    local process = assert(sp.spawn {
        vswhere,
        '-latest',
        '-utf8',
        '-products', '*',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath',
        stdout = true,
    })
    local result = strtrim(process.stdout:read 'a')
    process.stdout:close()
    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
    assert(result ~= "", "can't find msvc.")
    InstallDir = fs.path(result)
    return InstallDir
end

local function parse_env(str)
    local pos = str:find('=')
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function findwinsdk()
    local function query(command)
        local f = io.popen(command, "r")
        if f then
            for l in f:lines() do
                local r = l:match "^    [^%s]+    [^%s]+    (.*)$"
                if r then
                    f:close()
                    return r
                end
            end
        end
    end
    local function find(dir)
        local max
        local winsdk = fs.path(dir) / "include"
        for file in fs.pairs(winsdk) do
            if fs.exists(file / "um" / "winsdkver.h") then
                local version = file:filename():string()
                if version:sub(1,3) == "10." then
                    if max then
                        if max < version then
                            max = version
                        end
                    else
                        max = version
                    end
                end
            end
        end
        return max
    end
    for _, v in ipairs {
        [[HKLM\SOFTWARE\Wow6432Node]],
        [[HKCU\SOFTWARE\Wow6432Node]],
        [[HKLM\SOFTWARE]],
        [[HKCU\SOFTWARE]]
    } do
        local WindowsSdkDir = query(([[reg query "%s\Microsoft\Microsoft SDKs\Windows\v10.0" /v "InstallationFolder"]]):format(v))
        if WindowsSdkDir then
            local WindowSdkVersion = find(WindowsSdkDir)
            if WindowSdkVersion then
                return WindowSdkVersion
            end
        end
    end
end

local function vsdevcmd(winsdk, arch, f)
    local vsvars32 = installpath() / 'Common7' / 'Tools' / 'VsDevCmd.bat'
    local args = { vsvars32:string() }
    if arch then
        args[#args+1] = ('-arch=%s'):format(arch)
    end
    if winsdk then
        args[#args+1] = ('-winsdk=%s'):format(winsdk)
    end
    local process = assert(sp.spawn {
        args, '&', 'set',
        stderr = true,
        stdout = true,
        searchPath = true,
        env = {
            VSCMD_SKIP_SENDTELEMETRY = "1"
        }
    })
    for line in process.stdout:lines() do
        local name, value = parse_env(line)
        if name and value then
            f(name, value)
        end
    end
    local err = process.stderr:read "a"
    process.stdout:close()
    process.stderr:close()
    local code = process:wait()
    if code ~= 0 then
        io.stderr:write("Call `VsDevCmd.bat` error:\n")
        io.stderr:write(err)
        os.exit(code, true)
    end
end

local function environment(winsdk, arch)
    local env = {}
    vsdevcmd(winsdk, arch, function (name, value)
        name = name:upper()
        if need[name] then
            env[name] = value
        end
    end)
    return env
end

local function prefix(env)
    local testdir = fs.path(os.tmpname())
    fs.create_directories(testdir)
    createfile(testdir / 'test.h')
    createfile(testdir / 'test.c', '#include "test.h"')
    local process = assert(sp.spawn {
        'cmd', '/c',
        'cl', '/showIncludes', '/nologo', '-c', 'test.c',
        searchPath = true,
        env = env,
        cwd = testdir,
        stdout = true,
        stderr = true,
    })
    local result
    for line in process.stdout:lines() do
        local m = line:match('[^:]+:[^:]+:')
        if m then
            result = m
            break
        end
    end
    process.stdout:close()
    process.stderr:close()
    process:wait()
    fs.remove_all(testdir)
    assert(result, "can't find msvc.")
    return result
end

local function toolspath()
    local ToolsVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCToolsVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    return installpath() / 'VC' / 'Tools' / 'MSVC' / ToolsVersion
end

local function vcrtpath(arch, mode)
    local RedistVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCRedistVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    local ToolsVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCToolsVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    local ToolsetVersion = (function ()
        local verfile = installpath() / 'VC' / 'Tools' / 'MSVC' / ToolsVersion / 'include' / 'yvals_core.h'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return r:match '#define%s+_MSVC_STL_VERSION%s+(%d+)'
    end)()
    local path = installpath() / 'VC' / 'Redist' / 'MSVC' / RedistVersion
    if mode == "debug" then
        return path / "debug_nonredist" / arch / ('Microsoft.VC'..ToolsetVersion..'.DebugCRT')
    end
    return path / arch / ('Microsoft.VC'..ToolsetVersion..'.CRT')
end

local function ucrtpath(arch, mode)
    local UniversalCRTSdkDir
    vsdevcmd(findwinsdk(), arch, function (name, value)
        if name == "UniversalCRTSdkDir" then
            UniversalCRTSdkDir = value
        end
    end)
    if not UniversalCRTSdkDir then
        return
    end
    local path = fs.path(UniversalCRTSdkDir) / 'Redist'
    local redist, ver
    local function accept(p)
        local ucrt = p / 'ucrt' / 'DLLs' / arch
        if fs.exists(ucrt) then
            local version = 0
            if p ~= path then
                version = p:filename():string():gsub('10%.0%.([0-9]+)%.0', '%1')
                version = tonumber(version)
            end
            if not ver or ver < version then
                redist, ver = ucrt, version
            end
        end
    end
    accept(path)
    for p in fs.pairs(path) do
        accept(p)
    end
    if not redist then
        return
    end
    if mode == "debug" then
        return redist, fs.path(UniversalCRTSdkDir) / "bin" / ("10.0.%d.0"):format(ver) / arch / "ucrt"
    end
    return redist
end

local function copy_vcrt(arch, target, mode)
    local ignore = mode == "debug" and fs.path "vccorlib140d.dll" or fs.path "vccorlib140.dll"
    fs.create_directories(target)
    for dll in fs.pairs(vcrtpath(arch, mode)) do
        local filename = dll:filename()
        if filename ~= ignore then
            fs.copy_file(dll, target / filename, fs.copy_options.overwrite_existing)
        end
    end
end

local function copy_ucrt(arch, target, mode)
    fs.create_directories(target)
    if mode == "debug" then
        local redist, bin = ucrtpath(arch, mode)
        local ignore = fs.path "ucrtbase.dll"
        for dll in fs.pairs(redist) do
            local filename = dll:filename()
            if filename ~= ignore then
                fs.copy_file(dll, target / filename, fs.copy_options.overwrite_existing)
            end
        end
        fs.copy_file(bin / "ucrtbased.dll", target / "ucrtbased.dll", fs.copy_options.overwrite_existing)
    else
        for dll in fs.pairs(ucrtpath(arch, mode)) do
            fs.copy_file(dll, target / dll:filename(), fs.copy_options.overwrite_existing)
        end
    end
end

return {
    installpath = installpath,
    toolspath = toolspath,
    environment = environment,
    prefix = prefix,
    copy_vcrt = copy_vcrt,
    copy_ucrt = copy_ucrt,
    findwinsdk = findwinsdk
}
