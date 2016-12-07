function _python_scan_spec()
    -- make sure this is only included once.
    -- for reasons.
    -- (we're defining some globals here. we can do that multiple times, but
    -- it's rather ugly, esp. seeing as we will be invoking _scan_spec rather often
    -- because we *need* it to run at start and we don't want to burden the user
    -- with including it manually)
    rpm.define("_python_scan_spec %{nil}")
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
            "version", "version_nodots", "bin_suffix"}
        local SHORT_MACROS = { "ver" }
        for _, srcflavor in ipairs({flavor, "python"}) do
            str = str:gsub("%%__" .. srcflavor, "%%__" .. targetflavor)
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
            return param:sub(modname:len() + 2)
        else
            return "-n " .. param
        end
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
        if name:find(py .. "%-") == 1 then
            flavor = py
            modname = name:sub(py:len() + 2)
            break
        end
    end
    -- try to match "python-"
    if name == modname and name:find("python%-") == 1 then
        flavor = "python"
        modname = name:sub(8)
    end
    -- if not found, modname == %name, flavor == "python"

    system_python = rpm.expand("%system_python")
    -- is the package built for python2 as "python-foo" ?
    old_python2 = rpm.expand("%_python2_package_prefix") == "python"
    is_called_python = flavor == "python"
    -- flavor must NEVER be "python". Handling old_python2 must be done locally.
    if is_called_python then flavor = system_python end

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

    python_files_flavor = ""

    -- assuming `%files %python_files` is present:
    if old_python2 and is_called_python then
        -- everything is all right
    elseif old_python2 and not is_called_python then
        -- this case covers package named "python2(3)-foo" attempting
        -- to generate "python-foo" subpackage. This should not happen
        -- in practice and is probably broken anyway.
        python_files_flavor = "python"
    elseif not old_python2 and is_called_python then
        -- the expected case: subpackage should be called "python2-foo"
        -- and files sections for "python-foo" should be left empty
        -- python-foo is empty, python2-foo is python_files
        python_files_flavor = flavor
    end
    -- else: not old_python2 and not is_called_python, so
    -- package is called python3-foo and we generate subpackages
    -- that don't involve "python-foo" at all.

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
        elseif name == "files" and is_called_python and not param:find("%%{?python_files") then -- }
            -- kingly hack. but RPM's native %error does not work.
            io.stderr:write('error: Package with "python-" prefix must not contain unmarked "%files" sections.\n')
            io.stderr:write('error: Use "%files %python_files" or "%files %{python_files foo} instead.\n')
            os.exit(1)
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
            -- handle %python_files
            if section == "files" then
                section_name = section_name:gsub("%%{python_files%s+(.*)}", "%1")
                section_name = section_name:gsub("%%{?python_files}?", "")
            end
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
        -- base case: generating for "python3-foo" in "python3-foo"
        local is_current_flavor = python == flavor
        -- "python-foo" case:
        if is_called_python then
            -- if we're in old-style package
            if old_python2 then is_current_flavor = python == "python2"
            -- else nothing is current flavor, always generate
            else is_current_flavor = false end
        end

        if not is_current_flavor then
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

    -- emit empty %files
    if python_files_flavor ~= "" then
        for _,subpkg in ipairs(subpackages) do
            print("%files " .. subpkg .. "\n")
        end
    end
end

function _python_output_requires()
    local myflavor = rpm.expand("%1")
    local label = rpm.expand("%2")
    local pkgname = pkgname_from_param(label)
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

    if myflavor == "python2" then
        print(rpm.expand("Obsoletes: python-" .. label .. " < %{version}-%{release}\n"))
        print(rpm.expand("Provides: python-" .. label .. " = %{version}-%{release}\n"))
    end
end

function _python_output_filelist()
    local myflavor = rpm.expand("%1")
    local label = rpm.expand("%2")
    local pkgname = pkgname_from_param(label)

    if myflavor == python_files_flavor then return end

    if myflavor == "python2" and old_python2 then
        print("%files -n python-" .. label .. "\n")
    else
        print("%files -n " .. myflavor .. "-" .. label .. "\n")
    end

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
        if myflavor == "python2" and old_python2 then
            print("%" .. k .. " -n python-" .. label .. "\n")
        else
            print("%" .. k .. " -n " .. myflavor .. "-" .. label .. "\n")
        end
        print(replace_macros(v, myflavor) .. "\n")
    end
end

function _python_output_description()
    local pkgname = pkgname_from_param(rpm.expand("%2"))
    print(descriptions[pkgname] .. "\n")
end

function python_exec()
    local args = rpm.expand("%**")
    print(rpm.expand("%{python_expand %__python " .. args .. "}"))
end

function python_expand()
    local args = rpm.expand("%**")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%{_python_use_flavor " .. python .. "}\n"))
        local cmd = replace_macros(args, python)
        cmd = cmd:gsub("$python", python)
        print(rpm.expand(cmd .. "\n"))
    end
end

function python_build()
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_build %**"))
    end
end

function python_install()
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_install %**"))
    end
end

function python_files()
    local nparams = rpm.expand("%#")
    local param = ""
    local fparam = ""
    if tonumber(nparams) > 0 then
        param = rpm.expand("%1")
        fparam = "-" .. param
    end
    if python_files_flavor ~= "" then
        print(string.format("-n %s-%s%s", python_files_flavor, modname, fparam))
    else
        print(param)
    end
end
