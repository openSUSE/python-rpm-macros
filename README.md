# Multi-Python, Single-Spec Macro System

This repository contains a work-in-progress macro system generator for the singlespec Python initiative.
The macro system can be used in spec files for building RPM packages.

The purpose of the singlespec system is to take a package for a particular flavor, and
autogenerate subpackages for all the other flavors.


### Terminology

__flavor__ is a kind of python interpreter. At this point, we recognize the following flavors:
`python2`, `python3` and `pypy3`.

For compatibility reasons you see sometimes `python`. In most places,
using `python` is either a redefinition of `python2`, or an alternative for
"flavor-agnostic". Conditionals are in place to switch `python` to mean `python3` in the future.

The name of the flavor is the name of the binary in `/usr/bin`. It is also used as a prefix
for all flavor-specific macros. Some macros are redefined with "short" flavor for compatibility
reasons, such as `py2` for `python2`. All of them have a "long" form too.

__modname__ is the PyPI name, or, if the package in question is not on PyPI, the moniker that we
chose to stand in for it.

Packages adhering to the SUSE Python module naming policy are usually called `%{flavor}-%{modname}`.
In some cases, it is only `%{modname}` though.

__pkgname__, or __subpackage name__, is internal to a spec file, and is that thing you put after the
`%package` macro. Pkgname of the package itself is an empty string. Pkgname of a `%package -n
something` is at this point `-n something`, and denotes that this subpackage should not be handled
by the generator.  
That means, if you want a subpackage to be skipped, rename it from `%package foo` to
`%package -n %{name}-foo`.

The purpose of the singlespec system is to take a package called `%{flavor}-%{modname}` for a
particular flavor, and autogenerate subpackages for all the other flavors.

Alternately, it is to take package `python-%{modname}` and generate subpackages for all flavors,
leaving the top-level package empty.

### Build Set

The default build set is listed in the __`%pythons`__ macro. Every entry in `%pythons` generates a
requirement in `%python_module`, a subpackage from `%python_subpackages` (unless the top-level spec
file is for that flavor), and an additional run of loops like `%python_build`, `_install`, `_exec`
and `_expand`.

To control the build set, you can either completely redefine `%pythons`, or exclude
particular flavor(s) by defining __`%skip_$flavor`__. For example, if you `%define skip_python2 1`,
then Python 2 will be excluded from the default build set.

Skip-macros are intended __for per-package use only__. Never define a skip-macro in prjconf or
in any other sort of global config. Instead, redefine `%pythons`.

### Macros

The following macros are considered public API:

* __`%system_python`__ - flavor that is used for generic unflavored `%python_` macros.
Currently set to `python2`.

* __`%python_for_executables`__ - flavor that is used for installing executables into `%_bindir` and
other files in non-flavor-specific locations. By default, set to `python3`.

* __`%pythons`__ - the build set. See above for details.

* __`%have_python2`, `%have_python3`, `%have_pypy3`__. Defined as 1 if the flavor is present in the
build environment. Undefined otherwise.  
_Note:_ "present in build environment" does not mean "part of build set". Under some circumstances,
you can get a Python flavor pulled in through dependencies, even if you exclude it from the build
set. In such case, `%have_$flavor` will be defined but packages will not be generated for it.

* __`%skip_python2`, `%skip_python3`, `%skip_pypy3`__. Undefined by default. Define in order to exclude
a flavor from build set.

* __`%{python_module modname [= version]}`__ expands to `$flavor-modname [= version]` for every
flavor. Intended as: `BuildRequires: %{python_module foo}`.

* __`%{python_dist_name modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format.

* __`%{python2_dist modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format, and evaluates to python2.Ydist(CANONICAL_NAME), which is useful
when listing dependencies. Intended as `(Build)Requires: %{python2_dist foo}`.

* __`%{python3_dist modname}`__. Given a standardized name (i.e. dist name, name on PyPI) of `modname`,
it will convert it to a canonical format, and evaluates to python3.Ydist(CANONICAL_NAME), which is useful
when listing dependencies. Intended as `(Build)Requires: %{python3_dist foo}`.

* __`%python_flavor`__ expands to the `%pythons` entry that is currently being processed.  
Does not apply in `%prep`, `%build`, `%install` and `%check` sections, except when evaluated
as `%{$python_flavor}` in `%python_expand`.

* __`%ifpython2`, `%ifpython3`, `%ifpypy3`__: applies the following section only to subpackages of
that particular flavor.  
__`%ifpycache`__: applies the following section only to subpackages of flavors that generate a
`__pycache__` directory.  
_Note:_ These are shortcuts for `%if "%python_flavor" == "$flavor"`. Due to how RPM evaluates the
shortcuts, they will fail when nested with other `%if` conditions. If you need to nest your
conditions, use the full `%if %python_flavor` spelling.

* __`%python2_only`, `%python3_only`, `%pypy3_only`__: applies the contents of the line only to
subpackages of that particular flavor.
* __`%pycache_only`__: applies the contents of the line only to subpackages of flavors that generate
`__pycache__` directories. Useful in filelists: `%pycache_only %{python_sitelib}/__pycache__/*`

* __`%python_build`__ expands to build instructions for all flavors.

* __`%python_install`__ expands to install instructions for all flavors.

* __`%python_exec something.py`__ expands to `$flavor something.py` for all flavors, and moves around
the distutils-generated `build` directory so that you are never running `python2` script with a
python3-generated `build`. This is only useful for distutils/setuptools.

* __`%python_expand something`__ is a more general form of the above. Performs the moving-around for
distutils' `build` directory, and performs rpm macro expansion of its argument for every flavor.  
Importantly, `$python` is replaced by current flavor name, even in macros. So:  
`%{python_expand $python generatefile.py %$python_bin_suffix}`  
expands to:  
`python2 generatefile.py %python2_bin_suffix`  
`python3 generatefile.py %python3_bin_suffix`
etc.

* __`%python_compileall`__ precompiles all python macros in `%{python_sitelib}` and `%{python_sitearch}`
for all flavors. Generally Python 2 create `.pyc` files directly in the script directories, while
newer flavors generate `__pycache__` directories.

* __`%pytest`__ runs `pytest` in all flavors with appropriate environmental variables
(namely, it sets `$PYTHONPATH` to ``%{python_sitelib}``). All paramteres to this macro are
passed without change to the pytest command. Explicit `BuildRequires` on `%{python_module pytest}`
is still required.

* __`%pytest_arch`__ the same as the above, except it sets ``$PYTHONPATH`` to ``%{$python_sitearch}``

* __`%python_clone filename`__ creates a copy of `filename` under a flavor-specific name for every
flavor. This is useful for packages that install unversioned executables: `/usr/bin/foo` is copied
to `/usr/bin/foo-%{python_bin_suffix}` for all flavors, and the shebang is modified accordingly.  
__`%python_clone -a filename`__ will also invoke __`%prepare_alternative`__ with the appropriate
arguments.

* __`%python2_build`, `%python3_build`, `%pypy3_build`__ expands to build instructions for the
particular flavor.

* __`%python2_install`, `%python3_install`, `%pypy3_install`__ expands to install
instructions for the particular flavor.

* __`%python_subpackages`__ expands to the autogenerated subpackages. This should go at the end of the
main headers section.

* __`%python_enable_dependency_generator`__ expands to a define to enable automatic requires generation
of Python module dependencies using egg-info/dist-info metadata. This should go above the
`%python_subpackages` macro, preferably closer to the top of the spec. Intended usage:
`%{?python_enable_dependency_generator}`. This macro will eventually be removed when the generator
is configured to automatically run, hence the `?` at the beginning of the macro invocation.

Alternative-related, general:

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

Alternative-related, for Python:

* __`%python_alternative <file>`__: expands to filelist entries for `<file>`, its symlink in
`/etc/alternatives`, and the target file called `<file>-%python_bin_suffix`.  
In case the file is a manpage (`file.1.gz`), the target is called `file-%suffix.1.gz`.

* __`%python_install_alternative <name> [<name> <name>...]`__: runs `update-alternatives`
for `<name>-%{python_bin_suffix}`. If more than one argument is present, the remaining ones are
converted to `--slave` arguments. 
If a `name` is in the form of `something.1` or `something.4.gz` (any number applies), it is
handled as a manpage and assumed to live in the appropriate `%{_mandir}` subdirectory, otherwise
it is handled as a binary and assumed to live in `%{_bindir}`. You can also supply a full path
to override this behavior.

* __`%python_uninstall_alternative <name>`__: reverse of the preceding.  
Note that if you created a group by specifying multiple arguments to `install_alternative`, only
the first one applies for `uninstall_alternative`.

  Each of these has a flavor-specific spelling: `%python2_alternative` etc.

In addition, the following flavor-specific macros are known and supported by the configuration:

* __`%__python2`__: path to the $flavor executable.
This exists mostly for Fedora compatibility. In SUSE code, it is preferable to use `$flavor`
directly, as it is specified to be the name in `/usr/bin`, and we don't support multiple competing
binaries (in the OBS environment at least).

* __`%python2_sitelib`, `%python2_sitearch`__: path to noarch and arch-dependent `site-packages`
directory.

* __`%python2_version`__: dotted major.minor version. `2.7` for CPython 2.7.

* __`%python2_version_nodots`__: concatenated major.minor version. `27` for CPython 2.7.

* __`%python2_bin_suffix`, `%python3_bin_suffix`, `%pypy3_bin_suffix`__: what to put after
a binary name. Binaries for CPython are called `binary-%{python_version}`, for PyPy the name
is `binary-pp%{pypy3_version}`

* __`%python2_prefix`__: prefix of the package name. `python` for old-style distros, `python2` for
new-style. For other flavors, the value is the same as flavor name.

  For reasons of preferred-flavor-agnosticity, aliases `python_*` are available for all of these.

  We recognize `%py_ver`, `%py2_ver` and `%py3_ver` as deprecated spellings of `%flavor_version`. No
such shortcut is in place for `pypy3`. Furthermore, `%py2_build`, `_install` and `_shbang_opts`, as
well as `py3` variants, are recognized for Fedora compatibility.


### Files in Repository

* __`macros` directory__: contains a list of files that are concatenated to produce the resulting
`macros.python_all` file. This directory is incomplete, files `020-flavor-$flavor` and
`040-automagic` are generated by running the compile script.

* __`macros/001-alternatives`__: macro definitions for alternatives handling. These are not
Python-specific and might find their way into `update-alternatives`.

* __`macros/010-common-defs`__: setup for macro spelling templates, common handling, preferred flavor
configuration etc.

* __`macros/030-fallbacks`__: compatibility and deprecated spellings for some macros.

* __`compile-macros.sh`__: the compile script. Builds flavor-specific macros, Lua script definition,
and concatenates all of it into `macros.python_all`.

* __`apply-macros.sh`__: compile macros and run `rpmspec` against first argument. Useful for examining
what is going on with your spec file.

* __`flavor.in`__: template for flavor-specific macros. Generates `macros/020-flavor-$flavor` for
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

* __`embed-macros.pl`__: takes care of slash-escaping and wrapping the Lua functions and inserting
them into the `macros.in` file in order to generate the resulting macros.

* __`python-rpm-macros.spec`__: spec file for the `python-rpm-macros` package generated from this
GitHub repository.

* __`process-spec.pl`__: Simple regexp-based converter into the singlespec format.

* __`README.md`__: This file. As if you didn't know.
