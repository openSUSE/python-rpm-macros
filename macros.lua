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

    function lookup_table(tbl)
        local result = {}
        for _,v in ipairs(tbl) do result[v] = true end
        return result
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
            "version", "version_nodots", "bin_suffix", "prefix"}
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
            name = name .. " " .. append
        end
        return name
    end


    function pkgname_from_param(param)
        if param == modname then
            return ""
        elseif param:startswith(modname .. "%-") then
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
    local spec_name_prefix = "python"
    -- modname from name
    local name = modname
    for _,py in ipairs(pythons) do
        if name:find(py .. "%-") == 1 then
            spec_name_prefix = py
            modname = name:sub(py:len() + 2)
            break
        end
    end
    -- try to match "python-"
    if name == modname and name:find("python%-") == 1 then
        spec_name_prefix = "python"
        modname = name:sub(8)
    end
    -- if not found, modname == %name, spec_name_prefix == "python"

    system_python = rpm.expand("%system_python")
    -- is the package built for python2 as "python-foo" ?
    old_python2 = rpm.expand("%python2_prefix") == "python"
    is_called_python = spec_name_prefix == "python"

    -- `current_flavor` is set to "what should we set to evaluate macros"
    -- `flavor` should always be "what is actually intended for build"
    if is_called_python then
        if old_python2 then
            -- in old python2, %ifpython2 should be true in "python-"
            current_flavor = "python2"
            flavor         = "python2"
        else
            -- otherwise, every %if$flavor should be false in "python-",
            -- the real flavor is system_python
            current_flavor = "python"
            flavor         = system_python
        end
    else
        -- specname is something other than "python-", we use it literally
        flavor         = spec_name_prefix
        current_flavor = spec_name_prefix
    end

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

    python_files_flavor = ""

    -- assuming `%files %python_files` is present:
    if is_called_python and not old_python2 then
        -- subpackage should be called "python2-foo"
        -- files sections for "python-foo" should not exist
        -- %files %python_files is set to "%files -n python2-foo"
        python_files_flavor = flavor
    end
    -- else: not old_python2 and not is_called_python, so
    -- package is called python3-foo and we generate subpackages
    -- that don't involve "python-foo" at all.
end

function _python_emit_subpackages()
    _python_subpackages_emitted = true

    -- line processing functions
    local function print_altered(line)
        -- set %name macro to proper flavor-name
        line = line:gsub("%%{?name}?", current_flavor .. "-" .. modname)
        -- print expanded
        print(rpm.expand(replace_macros(line, current_flavor)) .. "\n")
    end

    local function ignore_line(line) end

    local PROPERTY_COPY_UNMODIFIED = lookup_table { "Summary", "Version", "BuildArch" }
    local PROPERTY_COPY_MODIFIED = lookup_table {
        "Requires", "Provides",
        "Recommends", "Suggests",
        "Conflicts", "Obsoletes",
        "Supplements", "Enhances",
    }

    local function process_package_line(line)
        -- TODO implement %$flavor_only support here?
        local property, value = line:match("^([A-Z]%S-):%s*(.*)$")

        local function rename_package(package, flavor)
            if package == "python" or package == flavor then
                package = current_flavor
            else
                package = package:gsub("^" .. flavor .. "(%W)", current_flavor .. "%1")
                package = package:gsub("^python(%W)", current_flavor .. "%1")
            end
            return package
        end

        local function fix_packageand(packageand, flavor)
            local inner = packageand:match("^packageand%((.*)%)$")
            if not inner then return packageand end
            local eat = inner
            local result = "packageand("
            while eat do
                local idx = eat:find(":")
                local n = ""
                if idx then
                    n = eat:sub(1, idx)
                    eat = eat:sub(idx+1)
                else
                    n = eat
                    eat = nil
                end
                n = n:gsub("^%s*", "")
                result = result .. rename_package(n, flavor)
            end
            return result .. ")"
        end

        if PROPERTY_COPY_UNMODIFIED[property] then
            print_altered(line)
        elseif PROPERTY_COPY_MODIFIED[property] then
            if value:startswith("packageand") then
                value = fix_packageand(value, flavor)
            else
                value = rename_package(value, flavor)
            end
            local expanded = rpm.expand(value)
            print_altered(string.format("%s: %s", property, expanded))
        end
    end
    -- end line processing functions

    local function print_obsoletes(modname)
        if current_flavor == "python2" then
            print(rpm.expand("Obsoletes: python-" .. modname .. " < %{version}-%{release}\n"))
            print(rpm.expand("Provides: python-" .. modname .. " = %{version}-%{release}\n"))
        end
    end

    local function files_headline(flavor, param)
        if not param then param = "" end
        local append = param:match("(%-f%s+%S+)")
        local nof = param:gsub("%-f%s+%S+%s*", "")
        local python_files = param:match("%%{?python_files}?")
        local subpkg = param:match("%%{python_files%s*(.-)}")
        if subpkg then python_files = true end

        if is_called_python and not python_files then
            -- kingly hack. but RPM's native %error does not work.
            local errmsg =
                'error: Package with "python-" prefix must not contain unmarked "%files" sections.\n' ..
                'error: Use "%files %python_files" or "%files %{python_files foo} instead.\n'
            io.stderr:write(errmsg)
            print(errmsg)
            error('Invalid spec file')
        end

        local mymodname = nof
        if python_files then mymodname = subpkg end
        return "%files -n " .. package_name(flavor, modname, mymodname, append) .. "\n"
    end


    local function section_headline(section, flavor, param)
        if section == "files" then
            return files_headline(flavor, param)
        else
            return "%" .. section .. " -n " .. package_name(flavor, modname, param) .. "\n"
        end
    end

    local KNOWN_SECTIONS = lookup_table {"package", "description", "files", "prep",
        "build", "install", "check", "clean", "pre", "post", "preun", "postun",
        "pretrans", "posttrans", "changelog"}
    local COPIED_SECTIONS = lookup_table {"description", "files",
        "pre", "post", "preun", "postun", "pretrans", "posttrans"}

    local current_flavor_toplevel = current_flavor

    for _,python in ipairs(pythons) do
        local is_current_flavor = python == flavor
        -- "python-foo" case:
        if is_called_python then
            if old_python2 then
                -- if we're in old-style package, "python" == "python2"
                is_current_flavor = python == "python2"
            else
                -- else nothing is current flavor, always generate
                is_current_flavor = false
            end
        end

        current_flavor = python

        -- rescan spec for each flavor
        if not is_current_flavor then
            local spec, err = io.open(specpath, "r")
            if err then print ("bad spec " .. specpath) return end

            local section_function = process_package_line
            print(section_headline("package", current_flavor, nil))
            print_obsoletes(modname)

            while true do
                line = spec:read()
                --io.stderr:write(current_flavor .. " >".. tostring(line) .."<\n")
                if line == nil then break end

                -- match section delimiter
                local section_noparam = line:match("^%%(%S+)(%s*)$")
                local section_withparam, param = line:match("^%%(%S+)%s+(.+)$")
                local newsection = section_noparam or section_withparam

                if KNOWN_SECTIONS[newsection] then
                    -- enter new section
                    if param and param:startswith("%-n") then
                        -- ignore named section
                        section_function = ignore_line
                    elseif newsection == "package" then
                        print(section_headline("package", current_flavor, param))
                        print_obsoletes(modname .. "-" .. param)
                        section_function = process_package_line
                    elseif newsection == "files" and current_flavor == python_files_flavor then
                        section_function = ignore_line
                    elseif COPIED_SECTIONS[newsection] then
                        print(section_headline(newsection, current_flavor, param))
                        section_function = print_altered
                    else
                        section_function = ignore_line
                    end
                elseif line:startswith("%%python_subpackages") then
                    -- ignore
                elseif line:startswith("%%if") then
                    -- RPM handles %if on top level, whole sections can be conditional.
                    -- We must copy the %if declarations always, even if they are part
                    -- of non-copied sections. Otherwise we miss this:
                    -- %files A
                    -- /bin/something
                    -- %if %condition
                    -- %files B
                    -- /bin/otherthing
                    -- %endif
                    print_altered(line)
                    -- We are, however, copying expanded versions. This way, specifically,
                    -- macros like %ifpython3 are evaluated differently in the top-level spec
                    -- itself and in the copied sections.
                    --io.stderr:write(rpm.expand(line) .. "\n")
                elseif line:startswith("%%else") or line:startswith("%%endif") then
                    print(line .. "\n")
                    --io.stderr:write(line .. "\n")
                else
                    section_function(line)
                end
            end

            spec:close()
        end
    end

    -- restore current_flavor for further processing
    current_flavor = current_flavor_toplevel
end

function python_exec()
    local args = rpm.expand("%**")
    print(rpm.expand("%{python_expand %__$python " .. args .. "}"))
end

function python_expand()
    -- force spec scan
    rpm.expand("%_python_scan_spec")
    local args = rpm.expand("%**")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%{_python_use_flavor " .. python .. "}\n"))
        local cmd = replace_macros(args, python)
        cmd = cmd:gsub("$python", python)
        print(rpm.expand(cmd .. "\n"))
    end
end

function python_build()
    rpm.expand("%_python_scan_spec")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_build %**"))
    end
end

function python_install()
    rpm.expand("%_python_scan_spec")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_install %**"))
    end
end

function python_files()
    local nparams = rpm.expand("%#")
    local param = ""
    if tonumber(nparams) > 0 then param = rpm.expand("%1") end

    -- for "re" command, all these things are nil because scan_spec doesn't seem to run?
    -- checking for validity of python_files_flavor seems to fix this.
    if _python_subpackages_emitted
        and python_files_flavor and python_files_flavor ~= "" then
        print("-n " .. package_name(python_files_flavor, modname, param))
        current_flavor = python_files_flavor
    else
        print(param)
    end
end
