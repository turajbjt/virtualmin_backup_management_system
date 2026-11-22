#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $dir = abs_path(dirname(__FILE__) . "/..");
my $script = "$dir/virtualmin-backup.pl";

open my $fh, "<", $script or die "Cannot read $script: $!";
my $content = do { local $/; <$fh> };
close $fh;

# 1. No plaintext MySQL password variables in script
unlike($content, qr/\$MYSQL_PASS\b/, "No \$MYSQL_PASS credential variable in script");
unlike($content, qr/\$MYSQL_USER\b/, "No \$MYSQL_USER credential variable in script");
unlike($content, qr/\$MYSQL_HOST\b/, "No \$MYSQL_HOST variable in script");

# 2. Virtualmin native CLI is used instead of raw mysqldump
unlike($content, qr/\bmysqldump\b/, "No raw mysqldump execution (uses native virtualmin engine)");
like($content, qr/virtualmin backup-domain/, "Uses virtualmin backup-domain");
like($content, qr/virtualmin restore-domain/, "Uses virtualmin restore-domain");

# 3. Retention pruning safety constraints
like($content, qr/find [^\n]+ -mindepth 1/, "Retention pruning enforces -mindepth 1");
like($content, qr/find [^\n]+ -maxdepth 1/, "Retention pruning enforces -maxdepth 1");
like($content, qr/find [^\n]+ -name \\?["']20\*/, "Retention pruning strictly matches dated folders only (-name '20*')");
unlike($content, qr/rm -rf \$REMOTE_BASE\s*;/i, "Never executes bare rm on REMOTE_BASE");
unlike($content, qr/rm -rf \$REMOTE_BASE\/\*/i, "Never executes wildcard deletion on REMOTE_BASE/*");

# 4. Remote path quoting
like($content, qr/mkdir -p \\?["']\$REMOTE_BASE/, "Remote mkdir quotes REMOTE_BASE path");
like($content, qr/rsync -a -e .* -o LogLevel=ERROR/, "Rsync passes LogLevel=ERROR");
like($content, qr/ssh -p \$SSH_PORT -o LogLevel=ERROR/, "SSH passes LogLevel=ERROR");

# 5. Lockfile and root privilege checks
like($content, qr/\/var\/run\/virtualmin-backup\.lock|\/run\/virtualmin-backup\.lock/, "Lockfile located in system run directory");
like($content, qr/die .*Must be run as root.* if \$\> != 0/, "Enforces root execution when not in dry-run mode");

done_testing();
