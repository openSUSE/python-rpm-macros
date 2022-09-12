# Multi-Python, Single-Spec Macro System

This repository contains a work-in-progress macro system generator for the singlespec Python initiative.
The macro system can be used in spec files for building RPM packages.

The purpose of the singlespec system is to take a package for a particular flavor, and
autogenerate subpackages for all the other flavors.


### Terminology

__``<flavor>``__ is a kind of python interpreter. At this point, we recognize the following flavors:
`python2`, `python3`, `python38`, `python39`, `python310`, `python311` and `pypy3`. `python3` points to the default of
coinstallable flavors `python3<M>` where `<M>` is the minor version number. The default is
specified not by python-rpm-macros but by the obs project definition in `%primary_python`.

The flavor is used as a prefix for all flavor-specific macros.
Some macros are redefined with "short" flavor for compatibility
reasons, such as `py3` for `python3`. All of them have a "long" form too.

For compatibility reasons you see sometimes `python`. In most places,
using `python` is either a redefinition of `python2`, or an alternative for
"flavor-agnostic". Conditionals are in place to switch `python` to mean `python3` in the future.

The name of the binary in `%_bindir` (`/usr/bin`) is the name of the flavor with an addtional `.`
between the major and minor version number, in case the latter is part of the flavor name:

-  `/usr/bin/python2`
-  `/usr/bin/python3`
-  `/usr/bin/python3.8`
-  `/usr/bin/python3.10`
- ...

__modname__ is the PyPI name, or, if the package in question is not on PyPI, the moniker that we
chose to stand in for it.

Packages adhering to the SUSE Python module naming policy are usually called `<flavor>-modname`.
In some cases, it is only `modname` though.

__pkgname__, or __subpackage name__, is internal to a spec file, and is that thing you put after
the `%package` macro. Pkgname of the package itself is an empty string. Pkgname of a 
`%package -n something`  is at this point `-n something`, and denotes that this subpackage should
not be handled by the generator. That means, if you want a subpackage to be skipped, rename it
from `%package foo` to `%package -n %{name}-foo`.

The purpose of the singlespec system is to take a package called `<flavor>-modname` for a
particular flavor, and autogenerate subpackages for all the other flavors.

Alternately, it is to take package `python-modname` and generate subpackages for all flavors,
leaving the top-level package empty.

Additionally it is possible for non-Python packages which define a subpackage
`%package -n python-modname` and corresponding `%description -n python-modname` etc., 
to autogenerate all desired flavor subpackages `<flavor>-modname`.

### Build Set

The default build set is listed in the __`%pythons`__ macro. Every entry in `%pythons` generates a
requirement in `%python_module`, a subpackage from `%python_subpackages` (unless the top-level spec
file is for that flavor), and an additional run of loops like `%python_build`, `_install`, `_exec`
and `_expand`.

To control the build set, you can either completely redefine `%pythons`, or exclude
particular flavor(s) by defining __`%skip_<flavor>`__. For example, if you `%define skip_python2 1`,
then Python 2 will be excluded from the default build set. (Python 2 is not in the default
build set of Tumbleweed and SLE/Leap >= 15.4)

Skip-macros are intended __for per-package use only__. Never define a skip-macro in prjconf or
in any other sort of global config. Instead, redefine `%pythons`.

### Macros

The following macros are considered public API:

* __`%system_python`__ - flavor that is used for generic unflavored `%python_` macros.
Currently set to `python2`.

* __`%python_for_executables`__ - flavor that is used for installing executables into `%_bindir` and
other files in non-flavor-specific locations. By default, set to `python3`.

* __`%pythons`__ - the build set. See above for details.

* __`%have_<flavor>`__. Defined as 1 if the flavor is present in the build environment.
  Undefined otherwise.

  _Note:_ "present in build environment" does not mean "part of build set". Under some
  circumstances, you can get a Python flavor pulled in through dependencies, even if you exclude it 
  from the build set. In such case, `%have_<flavor>` will be defined but packages will not be 
  generated for it.

* __`%skip_<flavor>`__. Undefined by default. Define in order to exclude a flavor from build set.

  _Note:_ You do not need to define `%skip_python2` for Tumbleweed. Only define, if you need to skip it
  for older distributions.

* __`%{python_module modname args}`__ expands to `(<flavor>-modname args)` for every
  flavor. Intended as: `BuildRequires: %{python_module foo >= version}`. Supports 
  [rpm boolean dependencies](https://rpm.org/user_doc/boolean_dependencies.html).
  If the package needs a module only for a specific Python version, you can use the special pseudo-macro
  `%python` for expansion of the python-flavor within the requirement, e.g.
  `BuildRequires: %{python_module python-aiocontextvars >= 0.2.2 if %python-base < 3.7}`.
  (Don't define `%python` anywhere else.)

* __`%{python_dist_name modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format.

* __`%{python2_dist modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format, and evaluates to python2.Ydist(CANONICAL_NAME), which is useful
when listing dependencies. Intended as `(Build)Requires: %{python2_dist foo}`.

* __`%{python3_dist modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format, and evaluates to python3.Ydist(CANONICAL_NAME), which is useful
when listing dependencies. Intended as `(Build)Requires: %{python3_dist foo}`.

* __`%python_flavor`__ expands to the `%pythons` entry that is currently being processed.
Does not apply in `%prep`, `%build`, `%install` and `%check` sections. For those, check for the
pseudo-shell variable expansion of `$python` and `$python_flavor` inside the `%python_expand` macro
(see [Flavor expansion](#flavor-expansion)).

* __`%python_subpackages`__ expands to the autogenerated subpackages. This should go at the end of the
main headers section.

* __`%python_subpackage_only`__. Undefined by default. If you want to generate `<flavor>-modname`
subpackages for a non-python main package, make sure to `%define python_subpackage_only 1` before
`%python_subpackages` and use `-n python-modname` for section headers (except for `%files`, see below).

* __`%python_enable_dependency_generator`__ expands to a define to enable automatic requires generation
of Python module dependencies using egg-info/dist-info metadata. This should go above the
`%python_subpackages` macro, preferably closer to the top of the spec. Intended usage:
`%{?python_enable_dependency_generator}`. This macro will eventually be removed when the generator
is configured to automatically run, hence the `?` at the beginning of the macro invocation.


#### Conditionals

These are shortcuts for `%if "%python_flavor" == "<flavor>"`. Due to how RPM evaluates the
shortcuts, they will fail when nested with other `%if` conditions. If you need to nest your
conditions, use the full `%if "%python_flavor"` spelling.

* __`%if<flavor>`__: applies the following section only to subpackages of that particular flavor.

* __`%ifpycache`__: applies the following section only to subpackages of flavors that generate a
`__pycache__` directory.

* __`%<flavor>_only`__: applies the contents of the line only to subpackages of that particular flavor.

* __`%pycache_only`__: applies the contents of the line only to subpackages of flavors that generate
`__pycache__` directories. Useful in filelists: `%pycache_only %{python_sitelib}/__pycache__/*`


#### Flavor expansion

The following macros expand to command lists for all flavors and move around the distutils-generated
`build` directory so that you are never running a `python39` command with a python310-generated `build`
and vice versa.

##### General command expansion macros

* __`%python_exec something.py`__ expands to `$python something.py` for all flavors, where `$python`
is the basename of the flavor executable. Make sure it is in `$PATH`.

* __`%python_expand something`__ is a more general form of the above. It performs rpm macro expansion
  of its arguments for every flavor. Importantly, `$python` is not expanded by the shell, but replaced
  beforehand for the current flavor, even in macros:

  - When used as command delimited by space or one of `"'\)&|;<>`, it is replaced by the path to the executable.
  - When used as part of a macro name or other string, it is replaced by the current flavor name.

  So:
  `%python_expand $python generatefile.py %{$python_sitelib}`
  expands to:

  ```
  python3.8 generatefile.py /usr/lib/python3.8/site-packages
  python3.9 generatefile.py /usr/lib/python3.9/site-packages
  python3.10 generatefile.py /usr/lib/python3.10/site-packages
  ```

  etc. (plus the moving around of the `build` directory in between).

  If you want to check for the current python flavor inside `%python_expand`, either use the shell variale
  `${python_flavor}` (not `$python_flavor`, `%{python_flavor}` or `%{$python_flavor}`), or append a suffix,
  which is not one of the recognized delimiters listed above:

  ```spec
  %{python_expand # expanded-body:
  if [ ${python_flavor} = python310 ]; then
    $python command-for-py-310-only
  fi
  echo "We have version %{$python_version}, because we are in $python_flavor."
  echo "Cannot use %{$python_flavor} because it has not enough levels of expansion."
  echo "And %{python_flavor} is expanded early to the global default."
  if [ $python_ = python310_ ]; then
    echo "A suffix_ works as intended."
  fi
  }
  ```

  which expands during the python39 flavor iteration to

  ```sh
  # (.. moving build dirs ..)
  python_flavor=python39

  # expanded-body:
  if [ ${python_flavor} = python310 ]; then
    python3.9 command-for-py-310-only
  fi
  echo "We have version 3.9, because we are in python39_flavor."
  echo "Cannot use %{python39_flavor} because it has not enough levels of expansion."
  echo "And python310 is expanded early to the global default."
  if [ python39_ = python310_ ]; then
    echo "A suffix_ works as intended."
  fi
  ```

  and so on for all flavors.

##### Install macros

* __`%pyproject_wheel`__ expands to 
  [PEP517](https://www.python.org/dev/peps/pep-0517)/[PEP518](https://www.python.org/dev/peps/pep-0518/)
  build instructions for all flavors, creates wheels and places them into the flavor's `./build/` directories
  (specified by `%_pyproject_wheeldir`). In case of pure wheels only one wheel is created by the first flavor,
  placed into `./dist/` (`%_pyproject_anywheeldir`) and copied over to `%_pyproject_wheeldir` for all other
  flavors.

* __`%pyproject_install [wheelfile]`__ expands to install instructions for all flavors to install the created wheels.
  You can also use this without `%pyproject_wheel`, if you place a pre-existing wheel into the current working dir
  (deprecated), the `build/` directory of the current flavor (what `%pyproject_wheel` does), or specify
  the path to the wheel file explicitly as argument to the macro (preferred), e.g `%pyproject_install %{SOURCE0}`.

* __`%python_compileall`__ precompiles all python source files in `%{python_sitelib}` and `%{python_sitearch}`
for all flavors. Generally Python 2 creates the cached byte-code `.pyc` files directly in the script directories, while
newer flavors generate `__pycache__` directories. Use this if you have modified the source files in `%buildroot` after
`%python_install` or `%pyproject_install` has compiled the files the first time.

* __`%python_build`__ expands to distutils/setuptools build instructions for all flavors using `setup.py`.

* __`%python_install`__ expands to legacy distutils/setuptools install instructions for all flavors using `setup.py`.
  Note that `python setup.py install` has been deprecated by setuptools and distutils is deprecated entirely.
  Consider using the PEP517 install procedure using the `%pyproject_*` macros if the package sources support it.

* __`%python_clone filename`__ creates a copy of `filename` under a flavor-specific name for every
flavor. This is useful for packages that install unversioned executables: `/usr/bin/foo` is copied
to `/usr/bin/foo-%{python_bin_suffix}` for all flavors, and the shebang is modified accordingly.  
__`%python_clone -a filename`__ will also invoke __`%prepare_alternative`__ with the appropriate
arguments or create the libalternative configuration if `--with libalternatives` is specified.

* __`%python_find_lang foo`__ calls `%find_lang foo` for all flavors and creates flavor specific
  files `%{python_prefix}-foo.lang`. Additional arguments of `%find_lang` are supported. The filelist
  can then be used as `%files %{python_files} -f %{python_prefix}-foo.lang` in the `%files` section header.


##### Unit testing

* __`%pytest`__ runs `pytest` in all flavors with appropriate environmental variables
(namely, it sets `$PYTHONPATH` to ``%{$python_sitelib}``). All paramteres to this macro are
passed without change to the pytest command. Explicit `BuildRequires` on `%{python_module pytest}`
is still required.

* __`%pytest_arch`__ the same as the above, except it sets ``$PYTHONPATH`` to ``%{$python_sitearch}``.

* __`%pyunittest`__ and __`%pyunittest_arch`__ run `$python -m unittest` on all flavors with
appropriate environmental variables very similar to `%pytest` and `%pytest_arch`.


#### Alternative-related, general:

* __`%prepare_alternative [-t <targetfile> ] <name>`__  replaces `<targetfile>` with a symlink to
`/etc/alternatives/<name>`, plus related housekeeping. If no `<targetfile>` is given, it is
`%{_bindir}/<name>`.

* __`%install_alternative [-n ]<name> [-s <sourcefile>] [-t ]<targetfile> [-p ]<priority>`__  runs the
`update-alternative` command, configuring `<sourcefile>` alternative to be `<targetfile>`, with a
priority `<priority>`. If no `<sourcefile>` is given, it is `%{_bindir}/<name>`.  Can be followed by
additional arguments to `update-alternatives`, such as `--slave`.

* __`%uninstall_alternative [-n ]<name> [-t ]<targetfile>`__  if uninstalling (not upgrading) the
package, remove `<targetfile>` from a list of alternatives under `<name>`

* __`%alternative_to <file>`__ generates a filelist entry for `<file>` and a ghost entry for
`basename <file>` in `/etc/alternatives`


#### Alternative-related, for Python:

* __`%python_alternative <file>`__: expands to filelist entries for `<file>`, its symlink in
`/etc/alternatives`, and the target file called `<file>-%python_bin_suffix`.  
In case the file is a manpage (`file.1.gz`), the target is called `file-%suffix.1.gz`.

* __`%python_install_alternative <name> [<name> <name>...]`__: runs `update-alternatives`
for `<name>-%{python_bin_suffix}` (unless `--with libalternatives` is enabled).
If more than one argument is present, the remaining ones are converted to `--slave` arguments.
If a `name` is in the form of `something.1` or `something.4.gz` (any number applies), it is
handled as a manpage and assumed to live in the appropriate `%{_mandir}` subdirectory, otherwise
it is handled as a binary and assumed to live in `%{_bindir}`. You can also supply a full path
to override this behavior.

* __`%python_uninstall_alternative <name>`__: reverse of the preceding.
Note that if you created a group by specifying multiple arguments to `install_alternative`, only
the first one applies for `uninstall_alternative`.

Each of these has a flavor-specific spelling: `%python2_alternative` etc.


#### Libalternatives-related:

[Libalternatives](https://github.com/openSUSE/libalternatives) provides another way for settings alternative.
Instead of symlinks, the preferred executable is executed directly. Which executable is executed
depends on the available alternatives installed on the system and the system and/or user configuration files.
These configuration files will also be generated by the macros described above **AND** following settings in the
spec file:

* Enable *libalternative* by making __`--with libalternatives`__ the default:
  ```spec
  %if 0%{?suse_version} > 1500
  %bcond_without libalternatives
  %else
  %bcond_with libalternatives
  %endif
  ```
  This example shows that *libalternatives* is available for TW only.

* Require the `alts` package during build and runtime:
  ```spec
  %if %{with libalternatives}
  Requires:       alts
  BuildRequires:  alts
  %else
  Requires(post): update-alternatives
  Requires(postun):update-alternatives
  %endif
  ```

* Group entries using __`%python_group_libalternatives`__
  (similar to what would have been installed as master and slaves in %python_install_alternatives,
  but without the manuals, as these do not go into group= entries)
  ```spec
  %install
  ...
  %python_clone -a %{buildroot}/%{_bindir}/cmd1
  %python_clone -a %{buildroot}/%{_binddir}/cmd2
  %python_clone -a %{buildroot}/%{_mandir}/man1/cmd1.1
  %python_group_libalternatives cmd1 cmd2
  ```

* Cleanup old update-alternatives entries during a transition update to libalternatives:
  ```spec
  %pre
  # removing old update-alternatives entries
  %python_libalternatives_reset_alternative <name>
  ```
  The argument *\<name\>* is the same used for calling *%python_uninstall_alternative*.

#### Building and testing with flavored alternatives

* __`%python_flavored_alternatives`__: If a build tool or a test
  suite calls commands, which exist in several alternatives, and
  you need them to call the command in the alternative of the
  current flavor within an `%python_expand` block, this macro

  - creates the appropriate update-alternatives symlinks in the
    shuffled `build/flavorbin` directory and sets `$PATH`
    accordingly, and
  - selects the libalternatives priority of all installed commands
    with a `libalternatives.conf` in
    `XDG_CONFIG_HOME=$PWD/build/xdgflavorconfig`.

  The `%pytest(_arch)` and `%pyunittest(_arch)` macros include a call
  of this macro before expanding to the test suite execution.

#### Flavor-specific macros  

In addition, the following flavor-specific macros are known and supported by the configuration:

* __`%__<flavor>`__: path to the ``<flavor>`` executable.

* __`%<flavor>_pyproject_wheel`__ expands to PEP517 instructions to build a wheel using the particular flavor.

* __`%<flavor>_pyproject_install`__ expands to PEP517 install instructions for the particular flavor.

* __`%<flavor>_build`__ expands to `setup.py` build instructions for the particular flavor.

* __`%<flavor>_install`__ expands to legacy `setup.py` install instructions for the particular flavor.

* __`%<flavor>_sitelib`, `%<flavor>_sitearch`__: path to noarch and arch-dependent `site-packages`
directory.

* __`%<flavor>_version`__: dotted major.minor version. `2.7` for CPython 2.7.

* __`%<flavor>_version_nodots`__: concatenated major.minor version. `27` for CPython 2.7.

* __`%<flavor>_bin_suffix`__: what to put after
a binary name. Binaries for CPython are called `binary-%{python_version}`, for PyPy the name
is `binary-pp%{pypy3_version}`

* __`%<flavor>_prefix`__: prefix of the package name. `python` for old-style distros, `python2` for
new-style. For other flavors, the value is the same as flavor name.

For reasons of preferred-flavor-agnosticity, aliases `python_*` are available for all of these. 

We recognize `%py_ver`, `%py2_ver` and `%py3_ver` as deprecated spellings of `%<flavor>_version`. No
such shortcut is in place for `pypy3`. Furthermore, `%py2_build`, `_install` and `_shbang_opts`, as
well as `py3` variants, are recognized for Fedora compatibility.

### `%files` section

* __`%files %{python_files}`__ expands the `%files` section for all generated flavor packages of
  `<flavor>-modname`.

* __`%files %{python_files foo}`__ expands the `%files` section for all generated flavor subpackages
  of `<flavor>-modname-foo`.

For subpackages of non-python packages with `%python_subpackage_only`and
 `%package -n %{python_flavor}-modname`, also use `%files %{python_files modname}`.

Always use the flavor-agnostic macro versions `%python_*` inside `%python_files` marked `%files` sections.

See also the Filelists section of the 
[openSUSE:Packaging Python](https://en.opensuse.org/openSUSE:Packaging_Python#Filelists)
guidelines

### Files in Repository

* __`macros` directory__: contains a list of files that are concatenated to produce the resulting
`macros.python_all` file. This directory is incomplete, files `020-flavor-$flavor` and
`040-automagic` are generated by running the compile script.

* __`macros/001-alternatives`__: macro definitions for alternatives handling. These are not
Python-specific and might find their way into `update-alternatives`.

* __`macros/010-common-defs`__: setup for macro spelling templates, common handling, preferred flavor
configuration etc.

* __`macros/030-fallbacks`__: compatibility and deprecated spellings for some macros.

* __`apply-macros.sh`__: compile macros and run `rpmspec` against first argument. Useful for examining
what is going on with your spec file.

* __`buildset.in`__: template to generate `macros/040-buildset` for the `%pythons`, `%skip_<flavor>` and
  `%python_module` macros.

* __`compile-macros.sh`__: the compile script. Builds flavor-specific macros, Lua script definition,
and concatenates all of it into `macros.python_all`.

* __`flavor.in`__: template for flavor-specific macros. Generates `macros/020-flavor-<flavor>` for
every flavor listed in `compile-macros.sh`.

* __`functions.lua`__: Lua function definitions used in `macros.lua` and elsewhere. In the compile
step, these are converted to a RPM macro `%_python_definitions`, which is evaluated as part of
`%_python_macro_init`. This can then be called anywhere that we need a ready-made Lua environment.

* __`macros.in`__: pure-RPM-macro definitions for the single-spec generator. References and uses the
private Lua macros.  The line `### LUA-MACROS ###` is replaced with inlined Lua macro definitions.

* __`macros.lua`__: Lua macro definitions for the single-spec generator.  
This is actually pseudo-Lua: the top-level functions are not functions, and are instead converted to
Lua macro snippets. (That means that you can't call the top-level functions from Lua. For defining
pure Lua functions that won't be available as Lua macros, use the `functions.lua` file.)

* __`macros-default-pythons`__: macro definitions for `%have_python2` and `%have_python3` for systems
where this is not provided by your Python installation. The spec file uses this for SUSE <= Leap 42.3.
`apply-macros` also uses it implicitly (for now).

* __`README.md`__: This file. As if you didn't know.
