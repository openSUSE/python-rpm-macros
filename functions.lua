-- declare common functions
function string.startswith(str, prefix)
    return str:sub(1, prefix:len()) == prefix
end

function string.endswith(str, suffix)
    return str:sub(-suffix:len()) == suffix
end

function string.basename(str)
    while true do
        local idx = str:find("/")
        if not idx then return str end
        str = str:sub(idx + 1)
    end
end

function lookup_table(tbl)
    local result = {}
    for _,v in ipairs(tbl) do result[v] = true end
    return result
end

-- macro replacements
SHORT_FLAVORS = {
    -- ??
    python = "py",
    -- ??
    python2 = "py2",
    python3 = "py3",
    pypy = "pypy",
}

function replace_macros(str, targetflavor)
    local LONG_MACROS = { "sitelib", "sitearch",
        "alternative", "install_alternative", "uninstall_alternative", "reset_alternative",
        "version", "version_nodots", "bin_suffix", "prefix", "provides"}
    local SHORT_MACROS = { "ver" }
    for _, srcflavor in ipairs({flavor, "python"}) do
        str = str:gsub("%%__" .. srcflavor, "%%__" .. targetflavor)
        for _, macro in ipairs(LONG_MACROS) do
            local from = string.format("%s_%s", srcflavor, macro)
            local to = string.format("%s_%s", targetflavor, macro)
            str = str:gsub("%%" .. from, "%%" .. to)
            str = str:gsub("%%{" .. from .. "}", "%%{" .. to .. "}")
            str = str:gsub("%%{" .. from .. "(%s+.-)}", "%%{" .. to .. "%1}")
        end
        for _, macro in ipairs(SHORT_MACROS) do
            local from = string.format("%s_%s", SHORT_FLAVORS[srcflavor], macro)
            local to = string.format("%s_%s", SHORT_FLAVORS[targetflavor], macro)
            str = str:gsub("%%" .. from, "%%" .. to)
            str = str:gsub("%%{" .. from .. "}", "%%{" .. to .. "}")
        end
    end
    return str
end

function package_name(flavor, modname, subpkg, append)
    if flavor == "python2" and old_python2 then
        flavor = "python"
    end
    local name = flavor .. "-" .. modname
    if subpkg and subpkg ~= "" then
        name = name .. "-" .. subpkg
    end
    if append and append ~= "" then
        name = name .. " " .. replace_macros(append, flavor)
    end
    return name
end

-- alternative-related
local bindir = rpm.expand("%{_bindir}")
local mandir = rpm.expand("%{_mandir}")
local ext_man, ext_man_expr
ext_man = rpm.expand("%{ext_man}")
if ext_man == "" then
    ext_man_expr = "%.%d$"
else
    -- ASSUMPTION: ext_man:startswith(".")
    ext_man_expr = "%.%d%" .. ext_man .. "$"
end

function python_alternative_names(arg, binsuffix, keep_path_unmangled)
    local link, name, path
    name = arg:basename()
    local man_ending = arg:match(ext_man_expr) or arg:match("%.%d$")
    if arg:startswith("/") then
        link = arg
    elseif man_ending then
        link = mandir .. "/man" .. man_ending:sub(2,2) .. "/" .. arg
    else
        link = bindir .. "/" .. arg
    end
    if man_ending then
        path = link:sub(1, -man_ending:len()-1) .. "-" .. binsuffix .. man_ending
    else
        path = link .. "-" .. binsuffix
    end

    -- now is the time to append ext_man if appropriate
    -- "link" and "name" get ext_man always
    if ext_man ~= "" and man_ending and not arg:endswith(ext_man) then
        link = link .. ext_man
        name = name .. ext_man
        if not keep_path_unmangled then path = path .. ext_man end
    end
    return link, name, path
end
function alternative_prio(flavor)
    local prio      = rpm.expand("%" .. flavor .. "_version_nodots")
    -- increase priority for primary python3 flavor
    local provides = rpm.expand("%" .. flavor .. "_provides") .. " "
    if provides:match("python3%s") then
        prio = prio + 1000
    end
    return prio
end
function python_install_ualternative(flavor)
    local prio      = alternative_prio(flavor)
    local binsuffix = rpm.expand("%" .. flavor .. "_bin_suffix")

    local params = {}
    for p in string.gmatch(rpm.expand("%*"), "%S+") do
        table.insert(params, p)
    end

    if #params == 0 then
        print("error")
        return
    end

    local link, name, path = python_alternative_names(params[1], binsuffix)
    print(string.format("update-alternatives --quiet --install %s %s %s %s", link, name, path, prio))
    table.remove(params, 1)
    for _, v in ipairs(params) do
        print(string.format(" \\\n   --slave %s %s %s", python_alternative_names(v, binsuffix)))
    end
end
function python_install_libalternative(flavor, target)
    local prio      = alternative_prio(flavor)
    local binsuffix = rpm.expand("%" .. flavor .. "_bin_suffix")    
    local ldir = rpm.expand("%{buildroot}%{_datadir}/libalternatives")
    local link, name, path = python_alternative_names(target, binsuffix)
    local man_ending = name:match(ext_man_expr)
    local entry, lname
    if man_ending then
        lname=name:sub(1,-ext_man:len()-3)
        entry="man=" .. path:basename():sub(1,-ext_man:len()-1)
    else
        entry="binary=" .. path
        lname=name
    end
    print(string.format("mkdir -p %s/%s\n", ldir, lname))
    print(string.format("echo %s >> %s/%s/%s.conf\n", entry, ldir, lname, prio))
end
