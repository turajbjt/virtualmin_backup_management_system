#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use Fcntl qw(:flock);
use File::Temp qw(tempdir);

my $tempdir = tempdir(CLEANUP => 1);
my $lockfile = "$tempdir/test.lock";

# Test 1: First process acquires lock
open my $fh1, ">", $lockfile or die "Cannot open: $!";
my $res1 = flock($fh1, LOCK_EX | LOCK_NB);
ok($res1, "Process 1 successfully acquires lock");

# Test 2: Second process cannot acquire while first holds it
open my $fh2, ">", $lockfile or die "Cannot open: $!";
my $res2 = flock($fh2, LOCK_EX | LOCK_NB);
ok(!$res2, "Process 2 is blocked from acquiring exclusive lock");

# Test 3: Release process 1 lock
flock($fh1, LOCK_UN);
close $fh1;

# Test 4: Process 2 can now acquire lock
my $res3 = flock($fh2, LOCK_EX | LOCK_NB);
ok($res3, "Process 2 successfully acquires lock after Process 1 releases");

# Clean up
flock($fh2, LOCK_UN);
close $fh2;
unlink $lockfile;

ok(!-e $lockfile, "Lockfile is unlinked after clean release");

done_testing();
