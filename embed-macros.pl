#!/usr/bin/perl

use strict;
use utf8;
use warnings;

open(MACROS, "<macros.in");

my $infunction = 0;

while (<MACROS>) {
    unless (/^### LUA-MACROS ###$/) {
        print $_;
    } else {
        open(LUA, "<macros.lua");
        while (<LUA>) {
            chomp $_;
            if (/^function (\S*)$/) {
                print "%$1 %{lua: \\\n";
                $infunction = 1;
            } elsif (/^end$/) {
                print "}\n";
                $infunction = 0;
            } elsif ($infunction) {
                $_ =~ s/\\/\\\\/g;
                print $_ .  "\\\n";
            } else {
                print "\n";
            }
        }
        close LUA;
    }
}

close MACROS;
