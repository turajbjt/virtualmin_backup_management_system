#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 8;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $dir = abs_path(dirname(__FILE__) . "/..");
my $script = "$dir/virtualmin-backup.pl";

ok(-f $script, "virtualmin-backup.pl exists");
ok(-x $script, "virtualmin-backup.pl is executable");

my $output = `perl -c "$script" 2>&1`;
my $exit_code = $? >> 8;
is($exit_code, 0, "Script compiles cleanly without syntax errors");
like($output, qr/syntax OK/, "Compiler reports syntax OK");

# Check required core modules are loadable
for my $module (qw(POSIX File::Path Sys::Hostname JSON)) {
    eval "require $module; 1";
    ok(!$@, "Module $module is loadable");
}
