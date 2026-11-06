#!/usr/bin/perl
# Copyright (c) 2026 zzerfu. Loaded by the ScreenStay app to read the real
# Now Playing playback state. Requires DynaLoader and a bundled dylib.
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV;
if (!defined $library || !-e $library) {
    print "-1\n";
    exit 2;
}

my $handle = DynaLoader::dl_load_file($library, 0);
if (!$handle) {
    print "-1\n";
    exit 3;
}

my $symbol = DynaLoader::dl_find_symbol(
    $handle,
    "screenstay_now_playing_is_playing"
);
if (!$symbol) {
    print "-1\n";
    exit 4;
}

DynaLoader::dl_install_xsub("main::screenstay_probe", $symbol);
main::screenstay_probe();
