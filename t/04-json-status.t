#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use JSON qw(decode_json);

my $dir = abs_path(dirname(__FILE__) . "/..");
my $script = "$dir/virtualmin-backup.pl";

my @test_cases = (
    { cmd => "backup --dry-run", mode => "backup" },
    { cmd => "backup-update --dry-run", mode => "backup-update" },
    { cmd => "restore 2026-09-12_18-00-00 --dry-run", mode => "restore" },
    { cmd => "restore-domain test.com 2026-09-12_18-00-00 --dry-run", mode => "restore-domain" },
    { cmd => "restore-domains 2026-09-12_18-00-00 --dry-run", mode => "restore-domains" },
    { cmd => "upload /tmp/test.tar.gz --dry-run", mode => "upload" },
    { cmd => "import /tmp/test.tar.gz --dry-run", mode => "import" },
    { cmd => "test-restore 2026-09-12_18-00-00 --dry-run", mode => "test-restore" },
    { cmd => "migrate 2026-09-12_18-00-00 --dry-run", mode => "migrate" },
);

for my $tc (@test_cases) {
    my $cmd_str = "$script " . $tc->{cmd};
    my $out = `$cmd_str 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "$tc->{cmd} exited 0");

    # Find the JSON line in output
    my ($json_line) = grep { /^\{.*\}$/ } split(/\n/, $out);
    ok($json_line, "$tc->{cmd} printed a JSON object line");

    my $data;
    eval { $data = decode_json($json_line); };
    ok(!$@ && $data, "$tc->{cmd} emitted valid JSON: " . ($@ || ""));

    if ($data) {
        is($data->{status}, "success", "status is success");
        is($data->{mode}, $tc->{mode}, "mode is $tc->{mode}");
        is($data->{dryrun}, 1, "dryrun flag is 1");
        ok($data->{time} && $data->{time} =~ /^\d+$/, "time is integer timestamp");
        ok($data->{message} && length($data->{message}) > 0, "message is non-empty");
        ok($data->{host} && length($data->{host}) > 0, "host is set");
    }
}

done_testing();
