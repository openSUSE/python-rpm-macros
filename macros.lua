function _scan_spec()
    -- get us a list of pythons
    if _spec_is_scanned ~= nil then return end
    _spec_is_scanned = true

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

    spec, err = io.open(specpath, "r")
    local section = nil
    local section_name = nil
    local section_content = ""

    -- build section lookup structure
    local KNOWN_SECTIONS = {"package", "description", "files", "prep",
        "build", "install", "check", "clean", "pre", "post", "preun", "postun",
        "pretrans", "posttrans", "changelog"}
    local section_table = {}
    for _,v in ipairs(KNOWN_SECTIONS) do section_table[v] = true end

    function enter_section(name, param)
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

    function leave_section(name, param, content)
        if name == "description" then
            descriptions[param] = content
        end
    end

    if err then print ("bad spec " .. specpath) return end
    while true do
        local line = spec:read()
        if line == nil then break end
        -- match section delimiter
        local section_noparam = line:match("^%%(%S+)$")
        local section_withparam, param = line:match("^%%(%S+) (.*)$")
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
        else
            section_content = section_content .. "\n" .. line
            if property == "Requires" then
                -- TODO filter out version requirements
                for s in value:gmatch("%S+") do
                    if SECTION == "package" and SECTIONNAME ~= nil then
                        table.insert(requires_subpackage[SECTIONNAME], s)
                    else
                        table.insert(requires_common, s)
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

    function string.startswith(str, prefix)
        return str:find(prefix) == 1
    end

    function string.endswith(str, suffix)
        return suffix == str:sub(-suffix:len())
    end

    local mymodprefix = rpm.expand("%1")
    local packagename = rpm.expand("%2")
    local only = nil
    for _,file in ipairs(filelists[packagename]) do
        if mymodprefix == "python3" then
            file = file:gsub("python_sitelib", "python3_sitelib")
            file = file:gsub("python_sitearch", "python3_sitearch")
            file = file:gsub("py_ver", "py3_ver")
        elseif mymodprefix == "pypy" then
            file = file:gsub("python_sitelib", "pypy_sitelib")
            file = file:gsub("python_sitearch", "pypy_sitearch")
            file = file:gsub("py_ver", "pypy_ver")
        end

        if file == "%ifpython3" then
            only = "python3"
        elseif file == "%ifpython2" then
            only = "python"
        elseif file == "%ifpypy" then
            only = "pypy"
        elseif file == "%endif" then
            only = nil
        -- for some reason, rpm seems to do something bad with the following %strings
        elseif file:startswith("%%py3_only ") and mymodprefix == "python3" then
            print(file:sub(11) .. "\n")
        elseif file:startswith("%%py2_only ") and mymodprefix == "python" then
            print(file:sub(11) .. "\n")
        elseif file:startswith("%%pypy_only ") and mymodprefix == "pypy" then
            print(file:sub(12) .. "\n")
        else
            if only == nil or only == mymodprefix then print(file .. "\n") end
        end
    end
end
