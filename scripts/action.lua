local globals = require "globals"
local sp = require 'bee.subprocess'
local sim = require 'simulator'
local arguments = require "arguments"

local function ninja(args)
    local option = {
        "ninja", "-f",  globals.builddir .. "/build.ninja",
        args,
        stdout = true,
        stderr = "stdout",
        searchPath = true,
    }
    if globals.compiler == 'msvc' then
        local msvc = require "msvc_util"
        option.env = msvc.getEnv()
        option.env.VS_UNICODE_OUTPUT = false
        option.env.TMP = globals.builddir
    end
    if globals.hostshell == "cmd" then
        option[1] = {'cmd', '/c', 'ninja'}
    end

    local process = assert(sp.spawn(option))
    for line in process.stdout:lines() do
        io.write(line, "\n")
        io.flush()
    end
    process.stdout:close()

    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
end

local function init()
    sim.import(arguments.f)
end

local function generate(force)
    sim.generate(force)
end

local function make()
    local options = {}
    for _, opt in ipairs {"h", "v", "j", "k", "l", "n", "d", "t", "w"} do
        if arguments[opt] then
            table.insert(options, {
                "-"..opt,
                arguments[opt] ~= "on" and arguments[opt] or nil
            })
        end
    end
    ninja {arguments.targets, options}
end

local function clean()
    ninja {"-t", "clean"}
end

if globals.perf then
    local monotonic = require 'bee.time'.monotonic
    local perf_status = {}
    local function perf_end()
        local time = monotonic() - perf_status[2]
        print(("%s: %dms."):format(perf_status[1], time))
    end
    local function perf(what)
        perf_status[1] = what
        perf_status[2] = monotonic()
        return perf_status
    end
    setmetatable(perf_status, {__close = perf_end})

    local function perf_init()
        local _ <close> = perf "init"
        return init()
    end
    local function perf_generate(...)
        local _ <close> = perf "generate"
        return generate(...)
    end
    local function perf_make()
        local _ <close> = perf "make"
        return make()
    end
    local function perf_clean()
        local _ <close> = perf "clean"
        return clean()
    end
    return {
        init = perf_init,
        generate = perf_generate,
        make = perf_make,
        clean = perf_clean,
    }
end

return {
    init = init,
    generate = generate,
    make = make,
    clean = clean,
}
