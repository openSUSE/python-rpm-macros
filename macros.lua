function _python_scan_spec()
    -- make sure this is only included once.
    -- for reasons.
    -- (we're defining some globals here. we can do that multiple times, but
    -- it's rather ugly, esp. seeing as we will be invoking _scan_spec rather often
    -- because we *need* it to run at start and we don't want to burden the user
    -- with including it manually)
    --rpm.define("_python_scan_spec", "")
    if _spec_is_scanned ~= nil then return end
    _spec_is_scanned = true

    -- declare common functions
    function string.startswith(str, prefix)
        return str:find(prefix) == 1
    end

    function string.endswith(str, suffix)
        return suffix == str:sub(-suffix:len())
    end

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
            "alternative", "install_alternative", "uninstall_alternative",
            "version", "version_nodots"}
        local SHORT_MACROS = { "ver" }
        for _, srcflavor in ipairs({flavor, "python"}) do
            for _, macro in ipairs(LONG_MACROS) do
                local from = string.format("%s_%s", srcflavor, macro)
                local to = string.format("%s_%s", targetflavor, macro)
                str = str:gsub("%%" .. from, "%%" .. to)
                str = str:gsub("%%{" .. from .. "}", "%%{" .. to .. "}")
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

    function pkgname_from_param(param)
        if param == modname then
            return ""
        elseif param:startswith(modname .. "-") then
            return param:sub(modname:len() + 1)
        else
            return "-n " .. param
        end
    end

    function python_exec_flavor(flavor, command)
        print(rpm.expand("%{_python_push_flavor " .. flavor .. "}\n"));
        print(command .. "\n");
        print(rpm.expand("%{_python_pop_flavor " .. flavor .. "}\n"));
    end

    pythons = {}
    for str in string.gmatch(rpm.expand("%pythons"), "%S+") do
        table.insert(pythons, str)
    end

    modname = rpm.expand("%name")
    flavor = "python"
    -- modname from name
    local name = modname
    for _,py in ipairs(pythons) do
        if name:find(py .. "-") == 1 then
            flavor = py
            modname = name:sub(py:len() + 1)
            break
        end
    end
    -- if not found, modname == %name, flavor == "python"
    rpm.define("_modname " .. modname)
    rpm.define("_flavor " .. flavor)

    -- find the spec file
    specpath = name .. ".spec"
    local locations = { rpm.expand("%_sourcedir"), rpm.expand("%_specdir"), "." }
    for _,loc in ipairs(locations) do
        local filename = loc .. "/" .. specpath
        if posix.stat(filename, "mode") ~= nil then
            specpath = filename
            break
        end
    end

    subpackages = {}
    descriptions = {}
    filelists = {}
    requires = {}
    scriptlets = {}

    spec, err = io.open(specpath, "r")
    local section = nil
    local section_name = ""
    local section_content = ""

    -- build section lookup structure
    local KNOWN_SECTIONS = {"package", "description", "files", "prep",
        "build", "install", "check", "clean", "pre", "post", "preun", "postun",
        "pretrans", "posttrans", "changelog"}
    local SCRIPTLET_SECTIONS = { "pre", "post", "preun", "postun", "pretrans", "posttrans" }
    local section_table = {}
    local scriptlet_table = {}
    for _,v in ipairs(KNOWN_SECTIONS) do section_table[v] = true end
    for _,v in ipairs(SCRIPTLET_SECTIONS) do scriptlet_table[v] = true end

    local function enter_section(name, param)
        if name == "package" then
            -- TODO "%package -n ahoj"
            table.insert(subpackages, param)
            descriptions[param] = ""
            filelists[param] = {}
            requires[param] = {}
        end
    end

    -- create entry for main package
    enter_section("package", "")

    local function leave_section(name, param, content)
        if name == "description" then
            descriptions[param] = content
        elseif scriptlet_table[name] then
            if not scriptlets[param] then scriptlets[param] = {} end
            scriptlets[param][name] = content
        end
    end

    if err then print ("bad spec " .. specpath) return end
    while true do
        local line = spec:read()
        if line == nil then break end
        -- match section delimiter
        local section_noparam = line:match("^%%(%S+)(%s*)$")
        local section_withparam, param = line:match("^%%(%S+) (.+)$")
        local newsection = nil
        local newsection_name = ""
        if section_noparam then
            newsection = section_noparam
        elseif section_withparam then
            newsection = section_withparam
            newsection_name = param
        end

        -- TODO convert parameter to modname-like

        if section_table[newsection] then
            leave_section(section, section_name, section_content)
            enter_section(newsection, newsection_name)
            section = newsection
            section_name = newsection_name
            section_content = ""
        elseif line == "%python_subpackages" or line == "%{python_subpackages}" then
            -- nothing
        else
            section_content = section_content .. line .. "\n"
            local property, value = line:match("^([A-Z]%S-):%s*(.*)$")
            if property == "Requires" or property == "Recommends" or property == "Suggests" then
                table.insert(requires[section_name], {property, value})
            elseif section == "files" then
                table.insert(filelists[section_name], line)
            end
        end
    end
end

function _python_output_subpackages()
    for _,python in ipairs(pythons) do
        if python == flavor then
            -- this is already *it*
        else
            print(string.format("%%{_python_subpackage_for %s %s}\n", python, modname))
            for _,subpkg in ipairs(subpackages) do
                if subpkg:startswith("-n ") then
                    subpkg = subpkg:sub(4)
                    print(string.format("%%{_python_subpackage_for %s %s}\n", python, subpkg))
                elseif subpkg ~= "" then
                    print(string.format("%%{_python_subpackage_for %s %s-%s}\n", python, modname, subpkg))
                end
            end
        end
    end
end

function _python_output_requires()
    local myflavor = rpm.expand("%1")
    local pkgname = pkgname_from_param(rpm.expand("%2"))
    for _,req in ipairs(requires[pkgname]) do
        local prop = req[1]
        local val = rpm.expand(req[2])
        if val:match("^"..flavor) then
            val = val:gsub("^"..flavor, myflavor)
        elseif val:match("^python") then
            val = val:gsub("^python", myflavor)
        end
        print(prop .. ": " .. val .. "\n")
    end
end

function _python_output_filelist()
    local myflavor = rpm.expand("%1")
    local pkgname = pkgname_from_param(rpm.expand("%2"))

    if myflavor == "python" then myflavor = "python2" end

    local IFS_LIST = { python3=true, python2=true, pypy3=true, pycache=false}

    local only = nil
    for _,file in ipairs(filelists[pkgname]) do
        file = replace_macros(file, myflavor)
        local continue = false

        -- test %ifpython2 etc
        for k, _ in pairs(IFS_LIST) do
            if file == "%if" .. k then
                only = k
                continue = true
            end
        end
        if file == "%endif" then
            only = nil
            continue = true
        end

        -- test %python2_only etc
        -- for find, gsub etc., '%' is a special character and must be doubled
        for k, _ in pairs(IFS_LIST) do
            local only_expr = "%%" .. k .. "_only "
            if file:startswith(only_expr) then
                -- only_expr is 1 longer because of double %
                -- but string.sub counts 1-based
                -- so only_expr:len() is actually the right number
                local justfile = file:sub(only_expr:len())
                if myflavor == k then
                    print(justfile .. "\n")
                elseif k == "pycache" and myflavor ~= "python2" then
                    print(justfile .. "\n")
                end
                continue = true
            end
        end

        if not continue
           and (only == nil or only == myflavor
            or (only == "pycache" and myflavor ~= "python2")) then
                print(file .. "\n")
        end
    end
end

function _python_output_scriptlets()
    local myflavor = rpm.expand("%1")
    local label = rpm.expand("%2")
    local pkgname = pkgname_from_param(label)
    if not scriptlets[pkgname] then return end
    for k, v in pairs(scriptlets[pkgname]) do
        print("%" .. k .. " -n " .. myflavor .. "-" .. label .. "\n")
        print(replace_macros(v, myflavor) .. "\n")
    end
end

function _python_output_description()
    local pkgname = pkgname_from_param(rpm.expand("%2"))
    print(descriptions[pkgname] .. "\n")
end

function python_exec()
    python_exec_for_flavor
    for _, flavor in ipairs(pythons) do
        python_exec_flavor(flavor, rpm.expand("%__" .. flavor .. " %**"))
    end
end

function python_build()
    for _, flavor in ipairs(pythons) do
        python_exec_flavor(flavor, rpm.expand("%" .. flavor .. "_build %**"))
    end
end

function python_install()
    for _, flavor in ipairs(pythons) do
        python_exec_flavor(flavor, rpm.expand("%" .. flavor .. "_install %**"))
    end
end
