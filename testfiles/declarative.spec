#
# spec file for package declarative-01
#
# Copyright (c) 2025 SUSE LLC and contributors
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via https://bugs.opensuse.org/
#

%bcond_without libalternatives
Name:           declarative
Version:        1.0
Release:        0
Summary:        Declarative
License:        MIT
URL:            http://example.com
Source0:        declarative.tar.gz
BuildRequires:  python-rpm-macros
BuildRequires:  pytest
BuildRequires:  alts
Requires:       alts

BuildSystem:    pyproject

%python_subpackages

%description
Declarative test

%install -a
%python_clone -a %{buildroot}/%{_bindir}/cmd1

%files %{python_files}
%license LICENSE
%doc README.md
%python_alternative %{_bindir}/cmd1
%{python_sitelib}/test
%{python_sitelib}/test-%{version}*-info

%changelog

