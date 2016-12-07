#!/usr/bin/perl

use strict;
use utf8;
use warnings;

my $SOURCE = $ARGV[0];
$SOURCE or die "Please specify source spec file.";
my $DEST = $ARGV[1] // ($SOURCE =~ s/\.spec$/.converted.spec/r);
$SOURCE eq $DEST and $DEST .= ".converted";

open (SOURCE, "<$SOURCE");
open (DEST, ">$DEST");

my $oldsuse = 0;
my $pysub_found = 0;
my $pymodule_inserted = 0;
my $macros_inserted = 0;

while (<SOURCE>) {
    if ($oldsuse == 1) {
        if (/^%else$/) {
            $oldsuse = 2;
        } elsif (/^%endif$/) {
            $oldsuse = 0;
        }
        # else nothing
    } elsif ($oldsuse == 2 && /^%endif$/) {
        $oldsuse = 0;
    } elsif ($oldsuse == 2 && /^%else$/) {
        $oldsuse = 1;
    } elsif (/^%\{\?!python_module/) {
        $pymodule_inserted = 1;
        print DEST $_;
    } elsif (!$pymodule_inserted && /^[a-zA-Z]+:/) {
        print DEST "%{?!python_module:%define python_module() python-%1 python3-%1}\n";
        print DEST $_;
        $pymodule_inserted = 1;
    } elsif (/^BuildRequires:(\s+)python-(.*)$/) {
        if ($2 eq "rpm-macros") {
            print DEST $_ unless $macros_inserted;
            $macros_inserted = 1;
        } else {
            if (!$macros_inserted) {
                print DEST "BuildRequires:$1python-rpm-macros\n";
                $macros_inserted = 1;
            }
            print DEST "BuildRequires:$1%{python_module $2}\n";
        }
    } elsif (!$macros_inserted && /^BuildRequires:(\s+)(.*)$/) {
        print DEST "BuildRequires:$1python-rpm-macros\n";
        print DEST $_;
        $macros_inserted = 1;
    } elsif (/^%description/ && !$pysub_found) {
        print DEST "%python_subpackages\n\n";
        print DEST $_;
        $pysub_found = 1;
    } elsif (/^python setup\.py build/) {
        print DEST "%python_build\n";
    } elsif (/^python setup\.py install.*/) {
        print DEST "%python_install\n";
    } elsif (/^python (.*)$/) {
        print DEST "%python_exec $1\n";
    } elsif (/^%files(.*)$/) {
        if ($1 =~ /%\{?python_files/) {
            print DEST $_;
        } else {
            print DEST "%files %{python_files$1}\n";
        }
    } elsif (/%\{!\?python_site/) {
        # pass
    } elsif (/^%if 0%\{\?suse_version\} && 0%\{\?suse_version\} <= 1110$/) {
        $oldsuse = 1;
    } elsif (/^%if 0%\{\?suse_version\} > 1110$/) {
        $oldsuse = 2;
    } elsif (/^%python_subpackages/) {
        print DEST $_ unless $pysub_found;
        $pysub_found = 1;
    } else {
        $_ =~ s/py_ver/python_version/;
        $_ =~ s/py3_ver/python3_version/;
        $_ =~ s/py([23]?)_(build|install)/python$1_$2/;
        print DEST $_;
    }
}

close DEST;
close SOURCE;

defined $ARGV[1] or rename $DEST, $SOURCE;
