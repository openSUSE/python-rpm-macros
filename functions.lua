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

function pkgname_from_param(param)
    if param == modname then
        return ""
    elseif param:startswith(modname .. "-") then
        return param:sub(modname:len() + 2)
    else
        return "-n " .. param
    end
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
function python_install_alternative(flavor)
    local prio      = alternative_prio(flavor)
    local binsuffix = rpm.expand("%" .. flavor .. "_bin_suffix")
    local libalternatives = rpm.expand("%{with libalternatives}")

    local params = {}
    for p in string.gmatch(rpm.expand("%*"), "%S+") do
        table.insert(params, p)
    end

    if #params == 0 then
        print("error")
        return
    end

    if libalternatives == "1" then
        for _, v in ipairs(params) do
	    local link, name, path = python_alternative_names(v, binsuffix)
            if not v:match(".+%.%d") then
                local group = ""
	        local man = ""
                for _, v2 in ipairs(params) do
	           local man_match = v2:match(".+%.%d")
	           if man_match then
		      if string.sub(man_match,1,-3) == v then
		        local man_entry = v .. "-" .. binsuffix .. "." .. string.sub(man_match,man_match:len())
                        if man:len() > 0 then
		           man = man .. ", " .. man_entry
		        else
                           man = man_entry
		        end
		      end
		   else
		      if group:len() > 0 then
		         group = group .. ", " .. v2
		      else
                         group = v2
		      end
		   end
	        end
	        local bindir = rpm.expand("%_bindir")
	        local datadir = rpm.expand("%_datadir")
                print(string.format("mkdir -p %s/libalternatives/%s\n", datadir, v))
                print(string.format("echo binary=%s/%s-%s >%s/libalternatives/%s/%s.conf\n",
		    bindir, v, binsuffix, datadir, v, prio))
		if man:len() > 0 then
                    print(string.format("echo man=%s >>%s/libalternatives/%s/%s.conf\n",
	                man, datadir, v, prio))
		end
                if group:len() > 0 then
                    print(string.format("echo group=%s >>%s/libalternatives/%s/%s.conf\n",
	                group, datadir, v, prio))
		end
	    end
        end
    else
        local link, name, path = python_alternative_names(params[1], binsuffix)
        print(string.format("update-alternatives --quiet --install %s %s %s %s", link, name, path, prio))
        table.remove(params, 1)
        for _, v in ipairs(params) do
            print(string.format(" \\\n   --slave %s %s %s", python_alternative_names(v, binsuffix)))
        end
    end
end
