#!/usr/bin/perl

# Copyright (c) 2025 Jonas van den Berg
# This file is licensed under the BSD 3-Clause License.

use strict;
use warnings;
use Getopt::Long;
use DynaLoader;

# --- Autoflush STDOUT ---
# This is critical. It prevents Perl from buffering output and ensures
# that data is sent to the parent Swift process immediately.
$| = 1;

# --- Command-Line Argument Parsing ---
my $bundle_identifier;
GetOptions('id=s' => \$bundle_identifier);

# If a bundle ID is provided, set it as an environment variable.
# This allows the Objective-C code to see the filter.
if (defined $bundle_identifier) {
    $ENV{'MEDIAREMOTEADAPTER_bundle_identifier'} = $bundle_identifier;
}

# --- Script Setup ---
# This script dynamically loads the MediaRemoteAdapter dylib and executes
# a command. It's designed to be called by a parent process that provides
# the full path to the dylib.

my $usage = "Usage: $0 [--id <bundle_id>] <path_to_dylib> <loop|play|pause|...>";
die $usage unless @ARGV >= 2;

my $dylib_path = shift @ARGV;
my $command = shift @ARGV;

unless (-e $dylib_path) {
    die "Dynamic library not found at $dylib_path\n";
}

# --- Manual DynaLoader Invocation ---

# 1. Load the library file directly.
my $libref = DynaLoader::dl_load_file($dylib_path)
    or die "Can't load '$dylib_path': " . DynaLoader::dl_error();

# 2. Find and install each C function as a Perl subroutine.
# This avoids any high-level magic and gives us direct control.
sub install_xsub {
    my ($perl_name, $lib) = @_;
    # C functions are usually prefixed with an underscore by the compiler.
    my $c_name = "_" . $perl_name;

    my $symref = DynaLoader::dl_find_symbol($lib, $c_name);
    
    # If the mangled name isn't found, try the plain name as a fallback.
    unless ($symref) {
        $symref = DynaLoader::dl_find_symbol($lib, $perl_name);
    }

    die "Can't find symbol '$perl_name' or '$c_name' in '$dylib_path'" unless $symref;
    
    # Install the C function into the main:: namespace so we can call it.
    DynaLoader::dl_install_xsub("main::" . $perl_name, $symref);
}

# 3. Install all the functions we need from the library.
install_xsub("bootstrap", $libref);
install_xsub("loop", $libref);
install_xsub("play", $libref);
install_xsub("pause_command", $libref);
install_xsub("toggle_play_pause", $libref);
install_xsub("next_track", $libref);
install_xsub("previous_track", $libref);
install_xsub("stop_command", $libref);
install_xsub("set_time_from_env", $libref);
install_xsub("get", $libref);

# 4. Call the bootstrap function to initialize the C code.
bootstrap();

# 5. Execute the requested command by calling the newly installed subroutine.
if ($command eq 'loop') {
    loop();
} elsif ($command eq 'play') {
    play();
} elsif ($command eq 'pause') {
    pause_command();
} elsif ($command eq 'toggle_play_pause') {
    toggle_play_pause();
} elsif ($command eq 'next_track') {
    next_track();
} elsif ($command eq 'previous_track') {
    previous_track();
} elsif ($command eq 'stop') {
    stop_command();
} elsif ($command eq 'set_time') {
    my $time = $ARGV[0];
    die "Missing time argument for set_time\n" unless defined $time;
    $ENV{'MEDIAREMOTE_SET_TIME'} = $time;
    set_time_from_env();
} elsif ($command eq 'get') {
    get();
} else {
    die "Unknown command: $command\n";
}

# For single commands, add a tiny sleep. This gives the command time to be processed
# by the system before this script exits and the pipe closes.
if ($command ne 'loop') {
    select(undef, undef, undef, 0.01); # Sleep for 100ms
} 