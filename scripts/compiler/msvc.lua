local fs = require "bee.filesystem"

local function format_path(path)
    if path:match " " then
        return '"'..path..'"'
    end
    return path
end

local cl = {
    flags = {
        "/EHsc /Zc:__cplusplus",
    },
    ldflags = {
    },
    optimize = {
        off      = '/Od',
        size     = '/O1 /GL /Zc:inline',
        speed    = '/O2 /GL /Zc:inline',
        maxspeed = '/Ox /GL /Zc:inline /fp:fast',
    },
    warnings = {
        off = "/W0",
        on  = "/W3",
        all = "/W4",
        error = "/WX",
    },
    cxx = {
        ['c++11'] = '/std:c++11',
        ['c++14'] = '/std:c++14',
        ['c++17'] = '/std:c++17',
        ['c++20'] = '/std:c++latest',
        ['c++latest'] = '/std:c++latest',
    },
    c = {
        ['c89'] = '',
        ['c99'] = '',
        ['c11'] = '/std:c11',
        ['c17'] = '/std:c17',
    },
    define = function (macro)
        return "/D" .. macro
    end,
    undef = function (macro)
        return "/U" .. macro
    end,
    includedir = function (dir)
        return "/I" .. format_path(dir)
    end,
    link = function (lib)
        if lib == "stdc++fs" or lib == "stdc++" then
            return
        end
        return lib .. ".lib"
    end,
    linkdir = function (dir)
        return "/libpath:" .. format_path(dir)
    end
}

function cl.update_flags(flags, attribute, name)
    flags[#flags+1] = '/permissive-'
    if attribute.mode == 'debug' then
        flags[#flags+1] = attribute.crt == 'dynamic' and '/MDd' or '/MTd'
        flags[#flags+1] = ('/RTC1 /Zi /FS /Fd%s'):format(fs.path('$obj') / name / "luamake.pdb")
    else
        flags[#flags+1] = attribute.crt == 'dynamic' and '/MD' or '/MT'
    end
end

function cl.update_ldflags(ldflags, attribute)
    if attribute.mode == 'debug' then
        ldflags[#ldflags+1] = '/DEBUG:FASTLINK'
    else
        ldflags[#ldflags+1] = '/DEBUG:NONE'
        ldflags[#ldflags+1] = '/LTCG' -- TODO: msvc2017 has bug for /LTCG:incremental
    end
end

function cl.rule_c(w, name, flags, cflags)
    w:rule('C_'..name:gsub('[^%w_]', '_'), ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cflags),
    {
        description = 'Compile C   $out',
        deps = 'msvc',
    })
end

function cl.rule_cxx(w, name, flags, cxxflags)
    w:rule('CXX_'..name:gsub('[^%w_]', '_'), ([[cl /nologo /showIncludes -c $in /Fo$out %s %s]]):format(flags, cxxflags),
    {
        description = 'Compile C++ $out',
        deps = 'msvc',
    })
end

function cl.rule_dll(w, name, ldflags)
    local lib = (fs.path('$bin') / name)..".lib"
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[cl /nologo $in /link %s /out:$out /DLL /IMPLIB:%s]]):format(ldflags, lib),
    {
        description = 'Link    Dll $out',
        restat = 1,
    })
end

function cl.rule_exe(w, name, ldflags)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), ([[cl /nologo $in /link %s /out:$out]]):format(ldflags),
    {
        description = 'Link    Exe $out'
    })
end

function cl.rule_lib(w, name)
    w:rule('LINK_'..name:gsub('[^%w_]', '_'), [[lib /nologo $in /out:$out]],
    {
        description = 'Link    Lib $out'
    })
end

function cl.rule_rc(w, name)
    w:rule('RC_'..name:gsub('[^%w_]', '_'), [[rc /nologo /fo $out $in]],
    {
        description = 'Compile Res $out',
    })
end

return cl