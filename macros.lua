function _python_scan_spec()
    local last_python = rpm.expand("%python_for_executables")
    local insert_last_python = false

    pythons = {}
    -- make sure that last_python is the last item in the list
    for str in string.gmatch(rpm.expand("%pythons"), "%S+") do
        if str == last_python then
            insert_last_python = true
        else
            table.insert(pythons, str)
        end
    end
    -- ...but check that it is actually in the buildset
    if insert_last_python then table.insert(pythons, last_python) end

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

    -- detect `flavor`, used for evaluating %ifmacros
    if is_called_python then
        -- either system_python (if found in %pythons)
        -- or the last entry of %pythons
        for _,py in ipairs(pythons) do
            flavor = py
            if flavor == system_python then break end
        end
    else
        -- specname is something other than "python-", and it is a valid
        -- python flavor (otherwise spec_name_prefix defaults to "python"
        -- so `is_called_python` is true), so we use it literally
        flavor = spec_name_prefix
    end

    -- find the spec file
    specpath = rpm.expand("%_specfile")
end

function python_subpackages()
    rpm.expand("%_python_macro_init")
    _python_subpackages_emitted = true

    local current_flavor  = flavor
    local original_flavor = rpm.expand("%python_flavor")

    subpackage_only = rpm.expand("%{python_subpackage_only}") == "1"
    if subpackage_only then
        is_called_python = false
        modname = ""
    end

    -- line processing functions
    local function print_altered(line)
        -- set %name macro to proper flavor-name
        if not subpackage_only then
            line = line:gsub("%%{?name}?", current_flavor .. "-" .. modname)
        end
        -- print expanded
        print(rpm.expand(replace_macros(line, current_flavor)) .. "\n")
    end

    local function ignore_line(line) end

    local function files_line(line)
        -- unexpand %license at start of line
        if line:startswith("%license") then
            line = "%" .. line
        end
        return print_altered(line)
    end

    local PROPERTY_COPY_UNMODIFIED = lookup_table { "Summary:", "Version:", "BuildArch:" }
    local PROPERTY_COPY_MODIFIED = lookup_table {
        "Requires:", "Provides:",
        "Recommends:", "Suggests:",
        "Conflicts:", "Obsoletes:",
        "Supplements:", "Enhances:",
        "%requires_eq", "%requires_ge",
        "Requires(pre):", "Requires(preun):", "Requires(post):", "Requires(postun):",
        "Requires(pretrans):", "Requires(posttrans):",
    }
    local PROPERTY_COPY_DEFAULT_PROVIDER = lookup_table {
        "Conflicts:", "Obsoletes:", "Provides:", "Supplements:", "Enhances:",
    }

    local function process_package_line(line)
        -- This function processes package tags like requirements and capabilities.
        -- It supports the python- prefix for plain packages, packageand(python-a:python-b:...), and boolean dependencies.
        -- "Requires: python-foo" -> "Requires: python3-foo"
        -- "Requires: %{name} = %{version}" -> "Requires: python3-modname = %{version}"

        -- first split Property: value
        local property, value = line:match("^([A-Z%%]%S+)%s*(.*)$")

        -- split and rewrite every package value either plain or inside boolean dependencies and packageand() -- recursive
        local function replace_prefix(value, flavor)
            local function replace_prefix_r(ivalue)
                return replace_prefix(ivalue, flavor)
            end
            local function rename_package(package)
                if package == "python" or package == flavor then
                    -- specialcase plain "python"
                    package = current_flavor
                else
                    package = package:gsub("^" .. flavor .. "(%W)", current_flavor .. "%1")
                    package = package:gsub("^python(%W)", current_flavor .. "%1")
                end
                return package
            end
            local before, inner, space, remainder
            inner, space, remainder = value:match("^packageand(%b())(%s*)(.*)$")
            if inner then
                return "packageand(" .. inner:sub(2,-2):gsub("[^:]+", rename_package) .. ")" .. space .. replace_prefix_r(tostring(remainder))
            end
            before, inner, space, remainder = value:match("^([^()]*)(%b())(%s*)(.*)$")
            if inner then
                return replace_prefix_r(tostring(before)) .. "(".. replace_prefix_r(inner:sub(2, -2)) ..  ")" .. space .. replace_prefix_r(tostring(remainder))
            end
            return value:gsub("%S+", rename_package)
        end

        if PROPERTY_COPY_UNMODIFIED[property] then
            print_altered(line)
        elseif PROPERTY_COPY_MODIFIED[property] then
            -- specifically handle %name macro before expansion
            if not subpackage_only then
                line = line:gsub("%%{?name}?", current_flavor .. "-" .. modname)
            end
            local function print_property_copy_modified(value)
                value = replace_prefix(value, flavor)
                -- rely on print_altered to perform expansion on the result
                print_altered(string.format("%s %s", property, value))
            end
            if PROPERTY_COPY_DEFAULT_PROVIDER[property] then
                -- print renamed lines for all flavors which the current_flavor provides.
                for iflavor in string.gmatch(rpm.expand("%{?" .. current_flavor .. "_provides}") .. " " .. current_flavor, "%S+" ) do
                    current_flavor = iflavor -- make sure to process the main current_flavor last for final reset.
                    print_property_copy_modified(value)
                end
            else
                print_property_copy_modified(value)
            end

        end
    end

    local auto_posttrans = {}
    local auto_posttrans_current = {}
    local auto_posttrans_backslash = false

    local function expect_alternatives(line)
        if auto_posttrans_backslash then
            local apc = auto_posttrans_current
            apc[#apc] = apc[#apc] .. "\n" .. line
            auto_posttrans_backslash = line:endswith("\\")
        elseif line:startswith("%python_install_alternative")
            or line:startswith("%{python_install_alternative") -- "}"
            or line:startswith("%" .. flavor .. "_install_alternative")
            or line:startswith("%{" .. flavor .. "_install_alternative") -- "}"
            then
                table.insert(auto_posttrans_current, line)
                auto_posttrans_backslash = line:endswith("\\")
        else
            auto_posttrans_backslash = false
        end
        return print_altered(line)
    end
    -- end line processing functions

    local function print_provided_flavor(modname)
        for provided_flavor in string.gmatch(rpm.expand("%{?" .. current_flavor .. "_provides}"), "%S+" ) do
            local pkg = provided_flavor .. "-" .. modname
            print(rpm.expand("Obsoletes: " .. pkg .. " < %{?epoch:%{epoch}:}%{version}-%{release}\n"))
            print(rpm.expand("Provides: " .. pkg .. " = %{?epoch:%{epoch}:}%{version}-%{release}\n"))
        end
    end

    local function section_headline(section, flavor, param)
        if not param then param = "" end
        local subpkg = " " .. param; local flags = ""
        for flag in subpkg:gmatch("(%s%-[flp]%s+%S+)") do
            flags = flags .. flag
        end
        subpkg = subpkg:gsub("(%s%-[flp]%s+%S+)", "")
        subpkg = subpkg:gsub("^%s*(.-)%s*$", "%1")
        if section == "files" then
            local python_files = param:match("%%{?python_files}?")
            local filessubpkg = param:match("%%{python_files%s*(.-)}")
            if filessubpkg then python_files = true end
            if is_called_python and not python_files then
                -- kingly hack. but RPM's native %error does not work.
                local errmsg =
                    'error: Package with "python-" prefix must not contain unmarked "%files" sections.\n' ..
                    'error: Use "%files %python_files" or "%files %{python_files foo} instead.\n'
                io.stderr:write(errmsg)
                print(errmsg)
                error('Invalid spec file')
            end
            if python_files then subpkg = filessubpkg end
        end
        return "%" .. section .. " -n " .. package_name(flavor, modname, subpkg, flags) .. "\n"
    end

    local python2_binsuffix = rpm.expand("%python2_bin_suffix")
    local function dump_alternatives_posttrans()
        if not old_python2 and current_flavor == "python2" then
            for label, value in pairs(auto_posttrans) do
                if value ~= false then
                    print(section_headline("posttrans", current_flavor, label))
                    for _,line in ipairs(value) do
                        -- RPM needs {} characters in Lua macros to match, so
                        -- this is an opening "{" for this one: ----------v
                        firstarg = line:match("install_alternative%s+([^%s}]+)")
                        if firstarg then
                            local _,_,path = python_alternative_names(firstarg, python2_binsuffix)
                            print(string.format('if [ -e "%s" ]; then\n', path))
                            print_altered(line)
                            print("fi\n")
                        end
                    end
                end
            end
        end
        auto_posttrans = {}
    end

    local function should_expect_alternatives(section, param)
        if old_python2 or current_flavor ~= "python2" then return false end
        if param == nil then param = "" end
        if section == "posttrans" then
            auto_posttrans[param] = false
            return false
        end
        if section == "post" and auto_posttrans[param] ~= false then
            auto_posttrans_current = {}
            auto_posttrans[param] = auto_posttrans_current
            return true
        end
        return false
    end

    local function match_braces(line)
        local count = 0
        for c in line:gmatch(".") do
            if c == "{" then count = count + 1
            elseif c == "}" and count > 0 then count = count - 1
            end
        end
        return count == 0
    end

    local KNOWN_SECTIONS = lookup_table {"package", "description", "files", "prep",
        "build", "install", "check", "clean", "pre", "post", "preun", "postun",
        "pretrans", "posttrans", "changelog"}
    local COPIED_SECTIONS = lookup_table {"description", "files",
        "pre", "post", "preun", "postun", "pretrans", "posttrans"}

    -- before we start, print Provides: python2-modname
    if is_called_python and old_python2 and not subpackage_only then
        print(rpm.expand("Provides: python2-" .. modname .. " = %{?epoch:%{epoch}:}%{version}-%{release}\n"))
    end

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
        if not is_current_flavor or subpackage_only then
            local spec, err = io.open(specpath, "r")
            if err then print ("could not find spec file at path: " .. specpath) return end

            rpm.define("python_flavor " .. python)

            local section_function

            if subpackage_only then
                section_function = ignore_line
            else
                section_function = process_package_line
                print(section_headline("package", current_flavor, nil))
                print_provided_flavor(modname)
            end

            while true do
                -- collect lines until braces match. it's what rpm does, kind of.
                local eof = false
                local line = spec:read()
                if line == nil then break end
                while not match_braces(line) do
                    local nl = spec:read()
                    if nl == nil then eof = true break end
                    line = line .. "\n" .. nl
                end
                if eof then break end
                --io.stderr:write(current_flavor .. " >".. tostring(line) .."<\n")

                -- match section delimiter
                local section_noparam = line:match("^%%(%S+)(%s*)$")
                local section_withparam, param = line:match("^%%(%S+)%s+(.+)$")
                local newsection = section_noparam or section_withparam

                if KNOWN_SECTIONS[newsection] then
                    -- enter new section
                    local ignore_section = false
                    if subpackage_only then
                        ignore_section = true
                        if param then
                            local subparam
                            if newsection == "files" then
                                subparam = param:match("%%{python_files%s+(.*)}")
                            else
                                subparam = param:match("^%-n%s+python%-(.*)$")
                            end
                            if subparam then
                                local submodname, subsubparam = rpm.expand(subparam):match("^(%S+)%s*(.*)$")
                                modname = submodname
                                param = subsubparam
                                ignore_section = false
                            end
                        end
                    elseif (param and param:startswith("-n")) then
                        ignore_section = true
                    end
                    if ignore_section then
                        section_function = ignore_line
                    elseif newsection == "package" then
                        print(section_headline("package", current_flavor, param))
                        if subpackage_only then
                            print_provided_flavor(modname)
                        else
                            -- only valid param is a regular subpackage name
                            print_provided_flavor(modname .. "-" .. param)
                        end
                        section_function = process_package_line
                    elseif newsection == "files" and current_flavor == flavor then
                        section_function = ignore_line
                    elseif COPIED_SECTIONS[newsection] then
                        print(section_headline(newsection, current_flavor, param))
                        if should_expect_alternatives(newsection, param) then
                            section_function = expect_alternatives
                        elseif newsection == "files" then
                            section_function = files_line
                        else
                            section_function = print_altered
                        end
                    else
                        section_function = ignore_line
                    end
                elseif line:startswith("%python_subpackages") then
                    -- ignore
                elseif line:startswith("%if") then
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
                elseif line:startswith("%else") or line:startswith("%endif") then
                    print(line .. "\n")
                    --io.stderr:write(line .. "\n")
                else
                    section_function(line)
                end
            end

            dump_alternatives_posttrans()

            spec:close()
        end
    end

    -- restore %python_flavor for further processing
    rpm.define("python_flavor " .. original_flavor)
end

function python_exec(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=)
    local args = rpm.expand("%**")
    print(rpm.expand("%{python_expand $python "  .. args .. "}"))
end

function python_expand(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=)
    -- force spec scan
    rpm.expand("%_python_macro_init")
    local args = rpm.expand("%**")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%{_python_use_flavor " .. python .. "}\n"))
        local cmd = replace_macros(args, python)
        -- when used as call of the executable, basename only
        cmd = cmd:gsub("$python%f[%s\"\'\\%)&|;<>]", string.basename(rpm.expand("%__" .. python)))
        -- when used as flavor expansion for a custom macro
        cmd = cmd:gsub("$python", python)
        print(rpm.expand(cmd .. "\n"))
    end
end

function python_build(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=)
    rpm.expand("%_python_macro_init")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_build %**"))
    end
end

function python_install(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-=)
    rpm.expand("%_python_macro_init")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_install %**"))
    end
end

function pyproject_wheel(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-=)
    rpm.expand("%_python_macro_init")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_pyproject_wheel %**"))
    end
end

function pyproject_install(+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-=)
    rpm.expand("%_python_macro_init")
    for _, python in ipairs(pythons) do
        print(rpm.expand("%" .. python .. "_pyproject_install %**"))
    end
end

function python_files()
    rpm.expand("%_python_macro_init")
    local nparams = rpm.expand("%#")
    local param = ""
    if tonumber(nparams) > 0 then param = rpm.expand("%1") end

    if subpackage_only then
        modname = param
        param = ""
    end

    print("-n " .. package_name(flavor, modname, param))

    if not _python_subpackages_emitted then
        print("\n/%python_subpackages_macro_not_present\n")
        io.stderr:write("%python_subpackages macro not present\n"
            .. "(To get rid of this error, either add a %python_subpackages macro to preamble "
            .. "or remove %python_files.\n")
        error("%python_subpackages macro not present\n")
    end
end

function python_clone(a)
    rpm.expand("%_python_macro_init")
    local param = rpm.expand("%1")
    local link, name, path
    for _, python in ipairs(pythons) do
        local binsuffix = rpm.expand("%" .. python .. "_bin_suffix")
        link,name,path = python_alternative_names(param, binsuffix, true)
        print(rpm.expand(string.format("cp %s %s\n", param, path)))
        print(rpm.expand(string.format("sed -ri '1s@#!.*python.*@#!%s@' %s\n", "%__" .. python, path)))
    end

    -- %python_clone -a
    if rpm.expand("%{?-a}") == "-a" then
        local buildroot = rpm.expand("%{buildroot}")
        if link:startswith(buildroot) then link = link:sub(buildroot:len() + 1) end
        print(rpm.expand(string.format("%%{prepare_alternative -t %s %s}\n", link, name)))
        if rpm.expand("%{with libalternatives}") == "1" then
            for _, python in ipairs(pythons) do
                python_install_libalternative(python, link)
            end
        end
    end
end

-- called by %python_module, see buildset.in
function python_module_lua()
    rpm.expand("%_python_macro_init")
    local params = rpm.expand("%**")
    -- The Provides: tag does not support boolean dependencies, so only add parens if needed
    local lpar = ""
    local rpar = ""
    local OPERATORS = lookup_table { 'and', 'or', 'if', 'with', 'without', 'unless'}
    for p in string.gmatch(params, "%S+") do
        if OPERATORS[p] then
            lpar = "("
            rpar = ")"
            break
        end
    end
    for _, python in ipairs(pythons) do
        local python_prefix = rpm.expand("%" .. python .. "_prefix")
        print(lpar .. python_prefix .. "-" .. string.gsub(params, "%%python", python_prefix) .. rpar .. " ")
    end
end
