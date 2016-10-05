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
    } elsif (/^BuildRequires:(\s+)python-(.*)$/) {
        print DEST "BuildRequires:$1%{python_module $2}\n";
    } elsif (/^%prep/ && !$pysub_found) {
        print DEST "%python_subpackages\n\n";
        print DEST $_;
    } elsif (/^python setup\.py build/) {
        print DEST "%python_build\n";
    } elsif (/^python setup\.py install.*/) {
        print DEST "%python_install\n";
    } elsif (/^python (.*)$/) {
        print DEST "%python_exec $1\n";
    } elsif (/%\{!\?python_site/) {
        # pass
    } elsif (/^%if 0%\{\?suse_version\} && 0%\{\?suse_version\} <= 1110$/) {
        $oldsuse = 1;
    } elsif (/^%if 0%\{\?suse_version\} > 1110$/) {
        $oldsuse = 2;
    } elsif (/^%python_subpackages/) {
        $pysub_found = 1;
        print DEST $_;
    } else {
        print DEST $_;
    }
}

close DEST;
close SOURCE;

defined $ARGV[1] or rename $DEST, $SOURCE;
