#
# spec file for package python-rpm-macros
#
# Copyright (c) 2016 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#

Name:           python-rpm-macros
Version:        1.0.0
Release:        0
License:        WTFPL
Summary:        RPM macros for building of Python modules
Url:            https://github.com/opensuse/multipython-macros
Source:         multipython-macros-%{version}.tar.bz2
BuildRequires:  perl

%description
This package contains SUSE RPM macros for Python build automation.
You should BuildRequire this package unless you are sure that you
are only building for distros newer than Leap 42.2

%prep
%setup -q -n multipython-macros

%build
/usr/bin/perl embed-macros.pl > macros.out
cat macros.out common-defs > macros.pythons

%install
install -m 644 macros.pythons %{buildroot}%{_sysconfdir}/rpm

%files
%defattr(-,root,root)
%{_sysconfdir}/rpm/macros.pythons
