#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);
use File::Path qw(make_path remove_tree);
use Sys::Hostname;
use Fcntl ':flock';
use JSON;

# ================= CONFIG =================
my $REMOTE_USER    = "backupuser";
my $REMOTE_HOST    = "backup.example.com";
my $REMOTE_BASE    = "/backups/virtualmin";
my $SSH_PORT       = 22;

my $MAIL_TO        = 'admin@example.com';
my $MAIL_FROM      = "backup@" . hostname();

my $LOCKFILE       = "/var/run/virtualmin-backup.lock";
my $RETENTION_DAYS = 30;

# ================= FLAGS =================
my $DRYRUN = grep { $_ eq '--dry-run' } @ARGV;
@ARGV = grep { $_ ne '--dry-run' } @ARGV;

my $MODE = shift @ARGV;

sub show_usage {
    print "Usage: $0 {backup|backup-update|restore|restore-domain|restore-domains|upload|import|test-restore|migrate} [args...] [--dry-run]\n";
}

if (!$MODE || $MODE eq '-h' || $MODE eq '--help' || $MODE eq 'help') {
    show_usage();
    exit($MODE ? 0 : 1);
}

my %VALID_MODES = map { $_ => 1 } qw(backup backup-update restore restore-domain restore-domains upload import test-restore migrate);
if (!$VALID_MODES{$MODE}) {
    show_usage();
    die "Error: Invalid mode '$MODE'. Run '$0 --help' for usage.\n";
}

# ================= GLOBALS =================
my $HOST   = hostname();
my $DATE   = strftime("%Y-%m-%d_%H-%M-%S", localtime);
my $TMPDIR = "/tmp/vmin-$DATE";
my $LOG    = "$TMPDIR/run.log";

my $SSH        = "ssh -p $SSH_PORT -o LogLevel=ERROR $REMOTE_USER\@$REMOTE_HOST";
my $RSYNC_BASE = "rsync -a -e 'ssh -p $SSH_PORT -o LogLevel=ERROR' " . ($DRYRUN ? "--dry-run " : "");

# ================= OS DETECTION =================
my ($OS_ID, $OS_LIKE, $OS_FAMILY);
if (-e "/etc/os-release") {
    if (open my $fh, "<", "/etc/os-release") {
        while (<$fh>) {
            if (/^ID=(.+)/) {
                $OS_ID = lc($1);
                $OS_ID =~ s/["']//g;
                $OS_ID =~ s/\s+//g;
            }
            elsif (/^ID_LIKE=(.+)/) {
                $OS_LIKE = lc($1);
                $OS_LIKE =~ s/["']//g;
                $OS_LIKE =~ s/\s+//g;
            }
        }
        close $fh;
    }
}
$OS_ID   ||= "";
$OS_LIKE ||= "";

if ("$OS_ID $OS_LIKE" =~ /rocky|rhel|almalinux|centos|fedora|ol/) {
    $OS_FAMILY = "rhel";
}
elsif ("$OS_ID $OS_LIKE" =~ /ubuntu|debian/) {
    $OS_FAMILY = "debian";
}
else {
    $OS_FAMILY = "debian";
}

my %PKG_CMD = (
    'rhel'   => 'rpm -qa | sort',
    'debian' => q(dpkg-query -W -f='${Package}=${Version}\n' | sort),
);

# ================= LOCK MANAGEMENT =================
my $LOCKED = 0;
my $LOCK_FH;

sub lock_or_die {
    open $LOCK_FH, ">", $LOCKFILE or die "Cannot open lockfile $LOCKFILE: $!\n";
    flock($LOCK_FH, LOCK_EX | LOCK_NB) or die "Another run is currently active.\n";
    $LOCKED = 1;
}

sub release_lock {
    if ($LOCKED && -e $LOCKFILE) {
        flock($LOCK_FH, LOCK_UN) if $LOCK_FH;
        close $LOCK_FH if $LOCK_FH;
        unlink $LOCKFILE;
        $LOCKED = 0;
    }
}

# ================= HELPERS =================
sub run {
    my ($cmd) = @_;
    print "[RUN] $cmd\n";
    return if $DRYRUN;
    my $res = system("$cmd >> $LOG 2>&1");
    if ($res != 0) {
        my $details = "";
        if (-f $LOG && open(my $lfh, "<", $LOG)) {
            my @lines = <$lfh>;
            close $lfh;
            my @tail = splice(@lines, -25);
            $details = join("", @tail);
        }
        my $msg = "FAILED: $cmd\n" . ($details ? "\n--- Last log output ---\n$details" : "");
        die $msg;
    }
}

sub mailit {
    my ($subj, $body) = @_;
    return if $DRYRUN;
    return unless $MAIL_TO;
    local $SIG{PIPE} = 'IGNORE';
    open my $m, "| mail -s \"$subj\" -r \"$MAIL_FROM\" \"$MAIL_TO\" 2>/dev/null" or return;
    print $m $body;
    close $m;
}

sub json_status {
    my ($status, $msg) = @_;
    print encode_json({
        host    => $HOST,
        mode    => $MODE,
        dryrun  => $DRYRUN,
        status  => $status,
        message => $msg,
        time    => time()
    }) . "\n";
}

sub get_latest_remote_date {
    my $cmd = "$SSH 'ls -1d \"$REMOTE_BASE\"/20* 2>/dev/null | sort | tail -n 1'";
    my $latest = `$cmd`;
    my $exit_code = $? >> 8;
    if ($exit_code != 0) {
        return "YYYY-MM-DD_HH-MM-SS" if $DRYRUN;
        die "Failed to connect to remote host via SSH ($SSH): exit code $exit_code\n";
    }
    $latest =~ s/\r//g if $latest;
    chomp $latest if $latest;
    if (!$latest) {
        return "YYYY-MM-DD_HH-MM-SS" if $DRYRUN;
        die "No remote backups found in $REMOTE_BASE\n";
    }
    $latest =~ s#^.*/##;
    return $latest;
}

# ================= PRECHECK =================
die "Must be run as root\n" if $> != 0 && !$DRYRUN;
lock_or_die() unless $DRYRUN;
make_path($TMPDIR) unless $DRYRUN;

eval {

    if ($MODE eq "backup" || $MODE eq "backup-update") {
        my $LOCAL_DOMAINS = "$TMPDIR/domains";
        my $LOCAL_META    = "$TMPDIR/meta";
        make_path($LOCAL_DOMAINS, $LOCAL_META) unless $DRYRUN;

        # 1. Export all virtual servers into individual archive bundles via native Virtualmin CLI
        run("virtualmin backup-domain --all-domains --all-features --newformat --dest $LOCAL_DOMAINS/%d.tar.gz");

        # 2. Export global Virtualmin server configs, templates, and server plans
        run("virtualmin backup-domain --all-virtualmin --dest $LOCAL_META/virtualmin-globals.tar.gz");

        # 3. Export system package state & core configurations
        run("$PKG_CMD{$OS_FAMILY} > $LOCAL_META/packages.txt");
        my @etc_targets = grep { -e $_ } qw(/etc/hosts /etc/resolv.conf /etc/fstab /etc/ssh);
        run("tar -czf $LOCAL_META/etc-essential.tar.gz " . join(" ", @etc_targets)) if @etc_targets || $DRYRUN;

        # 4. Generate metadata checksums
        if ($DRYRUN) {
            run("cd $LOCAL_DOMAINS && sha256sum *.tar.gz > SHA256SUMS");
            run("cd $LOCAL_META && sha256sum * > SHA256SUMS");
        } else {
            my @domain_archives = glob("$LOCAL_DOMAINS/*.tar.gz");
            run("cd $LOCAL_DOMAINS && sha256sum *.tar.gz > SHA256SUMS") if @domain_archives;
            my @meta_files = glob("$LOCAL_META/*");
            run("cd $LOCAL_META && sha256sum * > SHA256SUMS") if @meta_files;
        }

        # 5. Upload archives to remote host
        run("$SSH 'mkdir -p \"$REMOTE_BASE/$DATE/domains\" \"$REMOTE_BASE/$DATE/meta\"'");
        run("$RSYNC_BASE $LOCAL_DOMAINS/ $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$DATE/domains/\"");
        run("$RSYNC_BASE $LOCAL_META/ $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$DATE/meta/\"");

        # 6. Retention pruning: target only dated backup folders (format YYYY-MM-DD_*)
        run("$SSH 'find \"$REMOTE_BASE\" -mindepth 1 -maxdepth 1 -type d -name \"20*\" -mtime +$RETENTION_DAYS -exec rm -rf {} +'");

        json_status("success", "Virtualmin backup successfully exported and shipped");
        mailit("SUCCESS backup $HOST", "Virtualmin export backup finished successfully on $HOST.");
    }

    elsif ($MODE eq "upload") {
        my $source_file = shift @ARGV
          or die "Source archive or directory required: $0 upload /path/to/archive_or_dir [dest_folder] [--dry-run]\n";
        die "Source not found: $source_file\n" unless -e $source_file || $DRYRUN;
        my $dest_folder = shift @ARGV || "manual_uploads";

        if (-d $source_file && $source_file !~ m#/$#) {
            $source_file .= "/";
        }

        run("$SSH 'mkdir -p \"$REMOTE_BASE/$dest_folder\"'");
        run("$RSYNC_BASE $source_file $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$dest_folder/\"");

        json_status("success", "Uploaded $source_file to $REMOTE_BASE/$dest_folder/");
        mailit("SUCCESS upload $HOST", "Uploaded $source_file to $REMOTE_BASE/$dest_folder/.");
    }

    elsif ($MODE eq "import") {
        my $arg1 = shift @ARGV
          or die "Local archive or directory required: $0 import /path/to/archive_or_dir [--all] [--dry-run]\n";
        my $arg2 = shift @ARGV || "";
        my ($source_target, $is_all);
        if ($arg1 eq '--all') {
            $is_all = '--all';
            $source_target = $arg2;
        } else {
            $source_target = $arg1;
            $is_all = $arg2;
        }
        die "Local archive or directory required: $0 import /path/to/archive_or_dir [--all] [--dry-run]\n" unless $source_target;
        die "Target not found: $source_target\n" unless -e $source_target || $DRYRUN;

        if (-d $source_target || $is_all eq "--all") {
            run("virtualmin restore-domain --source $source_target --all-domains --all-features --reallocate-ip --skip-warnings");
            json_status("success", "Imported all domains from $source_target");
            mailit("SUCCESS import $HOST", "Imported all domains from $source_target.");
        } else {
            run("virtualmin restore-domain --source $source_target --all-features --reallocate-ip --skip-warnings");
            json_status("success", "Imported domain from $source_target");
            mailit("SUCCESS import $HOST", "Imported domain from $source_target.");
        }
    }

    elsif ($MODE eq "restore-domain") {
        my $domain = shift @ARGV
          or die "Domain name required: $0 restore-domain example.com [backup_date] [--dry-run]\n";
        my $target_date = shift @ARGV || get_latest_remote_date();

        my $RESTORE_DIR = "$TMPDIR/restore";
        make_path($RESTORE_DIR) unless $DRYRUN;

        # Download targeted domain archive
        run("$RSYNC_BASE $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/domains/$domain.tar.gz\" $RESTORE_DIR/");

        # Restore virtual server using Virtualmin engine
        run("virtualmin restore-domain --source $RESTORE_DIR/$domain.tar.gz --all-features --reallocate-ip --skip-warnings");

        json_status("success", "Domain $domain restored successfully from $target_date");
        mailit("SUCCESS restore-domain $domain", "Domain $domain restored successfully on $HOST.");
    }

    elsif ($MODE eq "restore-domains") {
        my $target_date = shift @ARGV || get_latest_remote_date();
        my $RESTORE_DIR = "$TMPDIR/restore";
        make_path($RESTORE_DIR) unless $DRYRUN;

        # Pull all domain archives from remote host
        run("$RSYNC_BASE $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/domains/\" $RESTORE_DIR/domains/");

        # Verify integrity if checksum file is present
        if (-f "$RESTORE_DIR/domains/SHA256SUMS") {
            run("cd $RESTORE_DIR/domains && sha256sum -c SHA256SUMS") unless $DRYRUN;
        }

        # Restore all virtual servers
        run("virtualmin restore-domain --source $RESTORE_DIR/domains/ --all-domains --all-features --reallocate-ip --skip-warnings");

        json_status("success", "All Virtualmin domains restored from $target_date");
        mailit("SUCCESS restore-domains $HOST", "All domains restored successfully on $HOST.");
    }

    elsif ($MODE eq "restore") {
        my $target_date = shift @ARGV || get_latest_remote_date();
        my $RESTORE_DIR = "$TMPDIR/restore";
        make_path($RESTORE_DIR) unless $DRYRUN;

        # Pull all domain archives and metadata from remote host
        run("$RSYNC_BASE $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/\" $RESTORE_DIR/");

        # Verify integrity
        if (-f "$RESTORE_DIR/domains/SHA256SUMS") {
            run("cd $RESTORE_DIR/domains && sha256sum -c SHA256SUMS") unless $DRYRUN;
        }

        # 1. Restore global Virtualmin configuration
        if (-f "$RESTORE_DIR/meta/virtualmin-globals.tar.gz" || $DRYRUN) {
            run("virtualmin restore-domain --source $RESTORE_DIR/meta/virtualmin-globals.tar.gz --all-virtualmin --skip-warnings");
        }

        # 2. Restore all virtual servers
        run("virtualmin restore-domain --source $RESTORE_DIR/domains/ --all-domains --all-features --reallocate-ip --skip-warnings");

        json_status("success", "Full Virtualmin server restore completed from $target_date");
        mailit("SUCCESS restore $HOST", "Full server restore completed successfully on $HOST.");
    }

    elsif ($MODE eq "test-restore") {
        my $arg1 = shift @ARGV;
        my ($domain, $target_date);
        if ($arg1 && $arg1 =~ /^\d{4}-\d{2}-\d{2}/) {
            $target_date = $arg1;
        } else {
            $domain = $arg1;
            $target_date = shift @ARGV;
        }
        $target_date ||= get_latest_remote_date();
        my $TESTDIR = "/tmp/test-restore-$DATE";
        make_path($TESTDIR) unless $DRYRUN;

        if ($domain) {
            run("$RSYNC_BASE $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/domains/$domain.tar.gz\" $TESTDIR/");
            run("tar -tzf $TESTDIR/$domain.tar.gz > /dev/null");
        } else {
            my $dry_flag = $DRYRUN ? "" : "--dry-run ";
            run("$RSYNC_BASE $dry_flag$REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/domains/\" $TESTDIR/");
        }

        remove_tree($TESTDIR) unless $DRYRUN;
        json_status("success", "Archive validation check passed for $target_date");
        mailit("SUCCESS test-restore $HOST", "Archive structure validation succeeded for $target_date.");
    }

    elsif ($MODE eq "migrate") {
        my $target_date = shift @ARGV || get_latest_remote_date();
        my $RESTORE_DIR = "$TMPDIR/restore";
        make_path($RESTORE_DIR) unless $DRYRUN;

        print "=== CROSS-OS / SERVER MIGRATION MODE ===\n";
        run("$RSYNC_BASE $REMOTE_USER\@$REMOTE_HOST:\"$REMOTE_BASE/$target_date/\" $RESTORE_DIR/");

        if (-f "$RESTORE_DIR/domains/SHA256SUMS") {
            run("cd $RESTORE_DIR/domains && sha256sum -c SHA256SUMS") unless $DRYRUN;
        }

        if (-f "$RESTORE_DIR/meta/virtualmin-globals.tar.gz" || $DRYRUN) {
            run("virtualmin restore-domain --source $RESTORE_DIR/meta/virtualmin-globals.tar.gz --all-virtualmin --skip-warnings");
        }

        run("virtualmin restore-domain --source $RESTORE_DIR/domains/ --all-domains --all-features --reallocate-ip --skip-warnings");

        json_status("success", "Cross-OS / server migration completed from $target_date");
        mailit("SUCCESS migration $HOST", "Cross-OS migration completed successfully on $HOST.");
    }

    else {
        die "Invalid mode: $MODE\n";
    }

};

if ($@) {
    my $err = $@;
    json_status("failure", $err);
    mailit("FAILED $MODE $HOST", $err);
    release_lock();
    die $err;
}

remove_tree($TMPDIR) unless $DRYRUN;
release_lock();
