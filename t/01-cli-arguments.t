#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 27;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $dir = abs_path(dirname(__FILE__) . "/..");
my $script = "$dir/virtualmin-backup.pl";

# 1. No arguments: exit code != 0, prints usage
{
    my $out = `"$script" 2>&1`;
    my $code = $? >> 8;
    isnt($code, 0, "No arguments exits with non-zero code");
    like($out, qr/Usage: .*backup/i, "No arguments prints usage message");
}

# 2. Help flags: exit code == 0, prints usage
for my $flag ('-h', '--help', 'help') {
    my $out = `"$script" $flag 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "Flag '$flag' exits with code 0");
    like($out, qr/Usage: .*backup/i, "Flag '$flag' prints usage message");
}

# 3. Invalid mode: exit code != 0, prints error
for my $bad ('invalid_mode', 'foo', '--unknown') {
    my $out = `"$script" $bad 2>&1`;
    my $code = $? >> 8;
    isnt($code, 0, "Invalid mode '$bad' exits with non-zero code");
    like($out, qr/Invalid mode|Usage:/i, "Invalid mode '$bad' outputs error or usage");
}

# 4. Dry-run positioning: should not fail as invalid mode
{
    my $out1 = `"$script" --dry-run backup 2>&1`;
    my $code1 = $? >> 8;
    is($code1, 0, "--dry-run before mode succeeds");
    like($out1, qr/"mode":"backup"/, "--dry-run before mode correctly identified mode");

    my $out2 = `"$script" backup --dry-run 2>&1`;
    my $code2 = $? >> 8;
    is($code2, 0, "--dry-run after mode succeeds");
    like($out2, qr/"mode":"backup"/, "--dry-run after mode correctly identified mode");
}

# 5. Valid modes acceptance
for my $mode (qw(backup backup-update restore restore-domain restore-domains upload import test-restore migrate)) {
    # Test that mode name itself is recognized and not rejected as 'Invalid mode'
    my $out = `"$script" $mode --invalid-test-trigger 2>&1`;
    unlike($out, qr/Error: Invalid mode/, "Mode '$mode' is recognized as a valid mode");
}
