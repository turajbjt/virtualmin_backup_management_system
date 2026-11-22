#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $dir = abs_path(dirname(__FILE__) . "/..");
my $script = "$dir/virtualmin-backup.pl";

# 1. backup mode
{
    my $out = `"$script" backup --dry-run 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "backup --dry-run exits 0");
    like($out, qr/virtualmin backup-domain --all-domains --all-features --newformat/, "Exports all domains");
    like($out, qr/virtualmin backup-domain --all-virtualmin/, "Exports global virtualmin configs");
    like($out, qr/(?:rpm -qa|dpkg-query).*packages\.txt/, "Exports package inventory");
    like($out, qr/tar -czf .*etc-essential\.tar\.gz/, "Archives essential etc configs");
    like($out, qr/sha256sum.*SHA256SUMS/, "Generates SHA256 checksums");
    like($out, qr/ssh -p \d+ .*mkdir -p/, "Prepares remote directories");
    like($out, qr/rsync -a -e 'ssh -p \d+ .*' --dry-run/, "Pushes backups via rsync with SSH port");
    like($out, qr/find .* -name "20\*" -mtime \+\d+ -exec rm -rf/, "Executes safe retention pruning");
    like($out, qr/"status":"success"/, "Reports success status in JSON");
}

# 2. backup-update mode (alias)
{
    my $out = `"$script" backup-update --dry-run 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "backup-update --dry-run exits 0");
    like($out, qr/"mode":"backup-update"/, "JSON reports backup-update mode");
    like($out, qr/virtualmin backup-domain --all-domains/, "Executes export in backup-update");
}

# 3. restore mode with date
{
    my $out = `"$script" restore 2026-09-12_18-00-00 --dry-run 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "restore with date exits 0");
    like($out, qr/rsync .*2026-09-12_18-00-00/, "Pulls backup for specified date");
    like($out, qr/virtualmin restore-domain --source .*virtualmin-globals\.tar\.gz --all-virtualmin --skip-warnings/, "Restores globals");
    like($out, qr/virtualmin restore-domain --source .*domains\/ --all-domains --all-features --reallocate-ip --skip-warnings/, "Restores domains with reallocate-ip and skip-warnings");
}

# 4. restore-domain mode
{
    my $fail_out = `"$script" restore-domain --dry-run 2>&1`;
    my $fail_code = $? >> 8;
    isnt($fail_code, 0, "restore-domain without domain dies");
    like($fail_out, qr/Domain name required/, "Error indicates domain name required");

    my $out = `"$script" restore-domain test.com 2026-09-12_18-00-00 --dry-run 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "restore-domain test.com exits 0");
    like($out, qr/rsync .*test\.com\.tar\.gz/, "Pulls targeted domain archive");
    like($out, qr/virtualmin restore-domain --source .*test\.com\.tar\.gz --all-features --reallocate-ip --skip-warnings/, "Restores domain with all features");
}

# 5. restore-domains mode
{
    my $out = `"$script" restore-domains 2026-09-12_18-00-00 --dry-run 2>&1`;
    my $code = $? >> 8;
    is($code, 0, "restore-domains with date exits 0");
    like($out, qr/rsync .*domains\//, "Pulls domains directory");
    like($out, qr/virtualmin restore-domain --source .*domains\/ --all-domains --all-features --reallocate-ip --skip-warnings/, "Restores all domains");
    unlike($out, qr/--all-virtualmin/, "restore-domains does not overwrite global templates");
}

# 6. upload mode
{
    my $fail_out = `"$script" upload --dry-run 2>&1`;
    my $fail_code = $? >> 8;
    isnt($fail_code, 0, "upload without argument dies");
    like($fail_out, qr/Source archive or directory required/, "Error indicates source required");

    my $out1 = `"$script" upload /tmp/test.tar.gz --dry-run 2>&1`;
    is($? >> 8, 0, "upload file exits 0");
    like($out1, qr/rsync .*\/tmp\/test\.tar\.gz .*manual_uploads\//, "Defaults upload destination to manual_uploads");

    my $out2 = `"$script" upload /tmp/test.tar.gz custom_dir --dry-run 2>&1`;
    is($? >> 8, 0, "upload with custom dest exits 0");
    like($out2, qr/rsync .*\/tmp\/test\.tar\.gz .*custom_dir\//, "Uses custom destination folder");
}

# 7. import mode
{
    my $fail_out = `"$script" import --dry-run 2>&1`;
    my $fail_code = $? >> 8;
    isnt($fail_code, 0, "import without argument dies");
    like($fail_out, qr/Local archive or directory required/, "Error indicates target required");

    my $out1 = `"$script" import /tmp/test.tar.gz --dry-run 2>&1`;
    is($? >> 8, 0, "import single archive exits 0");
    like($out1, qr/virtualmin restore-domain --source \/tmp\/test\.tar\.gz --all-features --reallocate-ip --skip-warnings/, "Restores single domain archive");

    my $out2 = `"$script" import /tmp/domains_dir --all --dry-run 2>&1`;
    is($? >> 8, 0, "import directory with --all suffix exits 0");
    like($out2, qr/virtualmin restore-domain --source \/tmp\/domains_dir --all-domains --all-features --reallocate-ip --skip-warnings/, "Restores all domains from dir");

    my $out3 = `"$script" import --all /tmp/domains_dir --dry-run 2>&1`;
    is($? >> 8, 0, "import directory with --all prefix exits 0");
    like($out3, qr/virtualmin restore-domain --source \/tmp\/domains_dir --all-domains --all-features --reallocate-ip --skip-warnings/, "Restores all domains from dir with prefix flag");
}

# 8. test-restore mode
{
    my $out_dir = `"$script" test-restore 2026-09-12_18-00-00 --dry-run 2>&1`;
    is($? >> 8, 0, "test-restore with date exits 0");
    like($out_dir, qr/rsync .*--dry-run .*domains\//, "Performs rsync dry-run directory verification");

    my $out_dom = `"$script" test-restore test.com 2026-09-12_18-00-00 --dry-run 2>&1`;
    is($? >> 8, 0, "test-restore with domain and date exits 0");
    like($out_dom, qr/rsync .*test\.com\.tar\.gz/, "Pulls domain archive for testing");
    like($out_dom, qr/tar -tzf .*test\.com\.tar\.gz/, "Verifies tar archive integrity with tar -tzf");
}

# 9. migrate mode
{
    my $out = `"$script" migrate 2026-09-12_18-00-00 --dry-run 2>&1`;
    is($? >> 8, 0, "migrate with date exits 0");
    like($out, qr/CROSS-OS \/ SERVER MIGRATION MODE/, "Prints migration banner");
    like($out, qr/virtualmin restore-domain --source .*virtualmin-globals\.tar\.gz --all-virtualmin --skip-warnings/, "Restores global templates");
    like($out, qr/virtualmin restore-domain --source .*domains\/ --all-domains --all-features --reallocate-ip --skip-warnings/, "Restores domains with reallocate-ip and skip-warnings");
}

done_testing();
