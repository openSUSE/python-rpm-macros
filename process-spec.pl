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

while (<SOURCE>) {
    if (/^BuildRequires:(\s+)python-(.*)$/) {
        print DEST "BuildRequires:$1%{python_module $2}\n";
    } elsif (/^%prep/) {
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
    } else {
        print DEST $_;
    }
}

close DEST;
close SOURCE;

defined $ARGV[1] or rename $DEST, $SOURCE;
