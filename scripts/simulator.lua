local writer = require 'writer'
local sandbox = require "sandbox"
local fs = require 'bee.filesystem'
local fsutil = require 'fsutil'
local arguments = require "arguments"
local globals = require "globals"
local pathutil = require "pathutil"

local mainSimulator = {}
local api = {}

function api:source_set(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'source_set', name, attribute, self }
    end
end
function api:shared_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'shared_library', name, attribute, self }
    end
end
function api:static_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'static_library', name, attribute, self }
    end
end
function api:executable(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'executable', name, attribute, self }
    end
end
function api:lua_library(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        attribute.luaversion = attribute.luaversion or "lua54"
        writer:add_target { 'shared_library', name, attribute, self }
    end
end
function api:lua_source(name)
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        attribute.luaversion = attribute.luaversion or "lua54"
        writer:add_target { 'source_set', name, attribute, self }
    end
end
function api:build(name)
    if type(name) == "table" then
        writer:add_target { 'build', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'build', name, attribute, self }
    end
end
function api:copy(name)
    if type(name) == "table" then
        writer:add_target { 'copy', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'copy', name, attribute, self }
    end
end
function api:default(attribute)
    if self == mainSimulator then
        writer:add_target {'default', attribute}
    end
end
function api:phony(name)
    if type(name) == "table" then
        writer:add_target { 'phony', nil, name, self }
        return
    end
    assert(type(name) == "string", "Name is not a string.")
    return function (attribute)
        writer:add_target { 'phony', name, attribute, self }
    end
end
function api:has(name)
    assert(type(name) == "string", "Name is not a string.")
    return writer:has(name)
end
function api:path(value)
    return pathutil.create(value)
end

local alias = {
    exe = "executable",
    dll = "shared_library",
    lib = "static_library",
    src = "source_set",
    lua_dll = "lua_library",
    lua_src = "lua_source",
}
for to, from in pairs(alias) do
    api[to] = api[from]
end

local mainMt = {}
function mainMt:__index(k)
    local v = globals[k]
    if v ~= nil then
        return v
    end
    return api[k]
end
function mainMt:__newindex(k, v)
    if arguments.args[k] ~= nil then
        return
    end
    globals[k] = pathutil.accept(globals.workdir, v)
end
function mainMt:__pairs()
    return pairs(globals)
end

do
    setmetatable(mainSimulator, mainMt)
end

local function createSubSimulator(parentSimulator, workdir)
    local subMt = {}
    subMt.__index = parentSimulator
    function subMt:__newindex(k, v)
        if arguments.args[k] ~= nil then
            return
        end
        v = pathutil.accept(workdir, v)
        rawset(self, k, v)
    end
    function subMt:__pairs()
        local selfpairs = true
        local mark = {}
        local pnext, parent = pairs(parentSimulator)
        return function (_, k)
            if selfpairs then
                local newk, newv = next(self, k)
                if newk ~= nil then
                    mark[newk] = true
                    return newk, newv
                end
                selfpairs = false
                k = nil
            end
            local newk = k
            local newv
            repeat
                newk, newv = pnext(parent, newk)
            until newk == nil or not mark[newk]
            return newk, newv
        end, self
    end
    return setmetatable({workdir=workdir}, subMt)
end

local function openfile(name, mode)
    local f, err = io.open(name, mode)
    if f and (mode == nil or mode:match "r") then
        writer:add_script(name)
    end
    return f, err
end

local visited = {}

local function isVisited(path)
    if visited[path] then
        return true
    end
    visited[path] = true
end

local function importfile(simulator, rootdir, filename)
    sandbox {
        rootdir = rootdir,
        builddir = globals.builddir,
        preload =  {
            luamake = simulator,
            msvc = (not arguments.args.prebuilt and globals.compiler == 'msvc') and require "msvc" or nil
        },
        openfile = openfile,
        main = filename,
        args = {}
    }
end

function api:import(path)
    local fullpath = fsutil.normalize(self.workdir, path)
    if fs.is_directory(fullpath) then
        fullpath = fsutil.join(fullpath, "make.lua")
    end
    if isVisited(fullpath) then
        return
    end
    local rootdir = fsutil.parent_path(fullpath)
    local filename = fsutil.filename(fullpath)
    local subSimulator = createSubSimulator(self, rootdir)
    importfile(subSimulator, rootdir, filename)
end

local function import(path)
    path = path or "make.lua"
    local fullpath = fsutil.normalize(WORKDIR, path)
    if isVisited(fullpath) then
        return
    end
    globals.workdir = WORKDIR
    importfile(mainSimulator, WORKDIR, path)
end

local function generate(force)
    writer:generate(force)
end

return  {
    import = import,
    generate = generate,
}
