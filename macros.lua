function _scan_spec()
    -- get us a list of pythons
    if _spec_is_scanned ~= nil then return end
    _spec_is_scanned = true

    -- declare common functions
    function string.startswith(str, prefix)
        return str:find(prefix) == 1
    end

    function string.endswith(str, suffix)
        return suffix == str:sub(-suffix:len())
    end

    SHORT_MODNAMES = {
        python = "py",
        python3 = "py3",
        pypy = "pypy",
    }

    function replace_macros(str, targetmodprefix)
        local LONG_MACROS = { "sitelib", "sitearch",
            "alternative", "install_alternative", "uninstall_alternative" }
        local SHORT_MACROS = { "ver" }
        for _, macro in ipairs(LONG_MACROS) do
            local from = string.format("%s_%s", modprefix, macro)
            local to = string.format("%s_%s", targetmodprefix, macro)
            str = str:gsub("%%" .. from, "%%" .. to)
            str = str:gsub("%%{" .. from .. "}", "%%{" .. to .. "}")
        end
        for _, macro in ipairs(SHORT_MACROS) do
            local from = string.format("%s_%s", SHORT_MODNAMES[modprefix], macro)
            local to = string.format("%s_%s", SHORT_MODNAMES[targetmodprefix], macro)
            str = str:gsub("%%" .. from, "%%" .. to)
            str = str:gsub("%%{" .. from .. "}", "%%{" .. to .. "}")
        end
        return str
    end

    pythons = {}
    for str in string.gmatch(rpm.expand("%pythons"), "%S+") do
        table.insert(pythons, str)
    end

    modname = rpm.expand("%name")
    modprefix = "python"
    -- modname from name
    local name = modname
    for _,py in ipairs(pythons) do
        if name:find(py .. "-") == 1 then
            modprefix = py
            modname = name:sub(py:len() + 2)
            break
        end
    end
    -- if not found, modname == %name, modprefix == "python"
    rpm.define("_modname " .. modname)
    rpm.define("_modprefix " .. modprefix)

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
    requires_common = {}
    requires_subpackage = {}
    scriptlets = {}

    spec, err = io.open(specpath, "r")
    local section = nil
    local section_name = nil
    local section_content = ""

    -- build section lookup structure
    local KNOWN_SECTIONS = {"package", "description", "files", "prep",
        "build", "install", "check", "clean", "pre", "post", "preun", "postun",
        "pretrans", "posttrans", "changelog"}
    local SCRIPTLET_SECTIONS = { "pre", "post", "preun", "postun", "pretrans", "posttrans" }
    local OPERATORS = { "<", "<=", ">=", ">", "=" }
    local section_table = {}
    local scriptlet_table = {}
    local operator_table = {}
    for _,v in ipairs(KNOWN_SECTIONS) do section_table[v] = true end
    for _,v in ipairs(SCRIPTLET_SECTIONS) do scriptlet_table[v] = true end
    for _,v in ipairs(OPERATORS) do operator_table[v] = true end

    local function enter_section(name, param)
        if name == "package" then
            -- TODO "%package -n ahoj"
            table.insert(subpackages, param)
            descriptions[param] = ""
            filelists[param] = {}
            requires_subpackage[param] = {}
        end
    end

    -- create entry for main package
    enter_section("package", modname)

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
        local property, value = line:match("^([A-Z]%S-):%s*(.*)$")

        -- TODO convert parameter to modname-like

        if section_table[section_noparam] then
            if section ~= nil then leave_section(section, section_name, section_content) end
            section = section_noparam
            section_name = modname
            section_content = ""
            enter_section(section, nil)
        elseif section_table[section_withparam] then
            if section ~= nil then leave_section(section, section_name, section_content) end
            section = section_withparam
            section_name = param
            section_content = ""
            enter_section(section, param)
        elseif line == "%python_subpackages" or line == "%{python_subpackages}" then
            -- nothing
        else
            section_content = section_content .. line .. "\n"
            if property == "Requires" then
                -- TODO filter out version requirements
                local target_table = requires_common
                if SECTION == "package" and SECTIONNAME ~= nil then
                    target_table = requires_subpackage[SECTIONNAME]
                end

                local req_operator = ""
                local req_name = nil
                for s in value:gmatch("%S+") do
                    if operator_table[s] then
                        req_operator = s
                    elseif s:find("[0-9]") == 1 then
                        local full_req = string.format("%s %s %s", req_name, req_operator, s)
                        for k,v in ipairs(target_table) do
                            if v == req_name then target_table[k] = full_req end
                        end
                    else
                        req_name = s
                        table.insert(target_table, s)
                    end
                end
            elseif section == "files" then
                table.insert(filelists[section_name], line)
            end
        end
    end
end

function _output_requires()
    local mymodprefix = rpm.expand("%1")
    for _,req in ipairs(requires_common) do
        if req:match("^"..modprefix) then
            req = req:gsub("^"..modprefix, mymodprefix)
        end
        print("Requires: " .. req .. "\n")
    end
end

function _output_filelist()
    local mymodprefix = rpm.expand("%1")
    local packagename = rpm.expand("%2")

    if mymodprefix == "python" then mymodprefix = "python2" end

    local IFS_LIST = { python3=true, python2=true, pypy=true }
    local ONLY_LIST = { py3="python3", py2="python2", pypy="pypy" }

    local only = nil
    for _,file in ipairs(filelists[packagename]) do
        file = replace_macros(file, mymodprefix)
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

        -- test %py2_only etc
        -- for find, gsub etc., '%' is a special character and must be doubled
        for k,v in pairs(ONLY_LIST) do
            local only_expr = "%%" .. k .. "_only "
            if file:startswith(only_expr) then
                -- only_expr is 1 longer because of double %
                -- but string.sub counts 1-based
                -- so only_expr:len() is actually the right number
                local justfile = file:sub(only_expr:len())
                if mymodprefix == v then print(justfile) .. "\n") end
                continue = true
            end
        end

        if not continue
           and (only == nil or only == mymodprefix) then
                print(file .. "\n")
        end
    end
end

function _output_scriptlets()
    local mymodprefix = rpm.expand("%1")
    local packagename = rpm.expand("%2")
    if not scriptlets[packagename] then return end
    for k, v in pairs(scriptlets[packagename]) do
        print("%" .. k .. " -n " .. mymodprefix .. "-" .. packagename .. "\n")
        print(replace_macros(v, mymodprefix) .. "\n")
    end
end

function _output_description()
    local packagename = rpm.expand("%2")
    print(descriptions[packagename] .. "\n")
end
