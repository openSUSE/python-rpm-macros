#!/usr/bin/perl

use strict;
use utf8;
use warnings;

my $INFILE=$ARGV[0];
my $LUAFILE=$ARGV[1];

open(MACROS, "<$INFILE");

my $infunction = 0;

while (<MACROS>) {
    unless (/^### LUA-MACROS ###$/) {
        print $_;
    } else {
        open(LUA, "<$LUAFILE");
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
