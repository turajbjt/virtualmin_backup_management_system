#!/usr/bin/perl
use strict;
use warnings;
use POSIX qw(strftime);
use File::Path qw(make_path);
use Sys::Hostname;
use Fcntl ':flock';
use JSON;

# ================= CONFIG =================
my $REMOTE_USER = "backupuser";
my $REMOTE_HOST = "backup.example.com";
my $REMOTE_BASE = "/backups/virtualmin";
my $SSH_PORT    = 22;

my $MYSQL_USER  = "root";
my $MYSQL_PASS  = "MYSQL_ROOT_PASSWORD";

my $MAIL_TO   = "admin\@example.com";
my $MAIL_FROM = "backup@" . hostname();

my $LOCKFILE  = "/var/run/virtualmin-backup.lock";
my $RETENTION_DAYS = 30;

# ================= FLAGS =================
my $DRYRUN = grep { $_ eq '--dry-run' } @ARGV;
@ARGV = grep { $_ ne '--dry-run' } @ARGV;

my $MODE = shift @ARGV
  or die "Usage: $0 {backup|backup-update|restore|restore-update|restore-domain|restore-domains|test-restore|migrate} [--dry-run]\n";

my $UPDATE = ($MODE =~ /update$/) ? 1 : 0;

# ================= GLOBALS =================
my $HOST   = hostname();
my $DATE   = strftime("%Y-%m-%d_%H-%M-%S", localtime);
my $TMPDIR = "/tmp/vmin-$DATE";
my $LOG    = "$TMPDIR/run.log";

my @EXCLUDES = (
    "--exclude=/var/cache",
    "--exclude=/var/tmp",
    "--exclude=/tmp",
    "--exclude=/var/log/journal",
    "--exclude=/var/lib/dnf",
    "--exclude=**/.cache"
);

# ================= OS DETECTION =================
my ($OS_FAMILY, $OS_NAME);

if (-e "/etc/os-release") {
    open my $fh, "<", "/etc/os-release";
    while (<$fh>) {
        $OS_NAME = $1 if /^ID=(.+)/;
    }
    close $fh;
}

$OS_NAME =~ s/"//g;

if ($OS_NAME =~ /rocky|rhel|almalinux|centos/) {
    $OS_FAMILY = "rhel";
}
elsif ($OS_NAME =~ /ubuntu|debian/) {
    $OS_FAMILY = "debian";
}
else {
    die "Unsupported OS: $OS_NAME\n";
}

# ================= OS-ABSTRACTION =================
my %PKG = (
    rhel => {
        install => "dnf install -y",
        list    => "rpm -qa | sort",
        mailpkg => "mailx",
        cronpkg => "cronie",
        mysql   => "mysql",
        repos   => "/etc/yum.repos.d",
    },
    debian => {
        install => "apt-get install -y",
        list    => "dpkg-query -W -f='${Package}=${Version}\n' | sort",
        mailpkg => "mailutils",
        cronpkg => "cron",
        mysql   => "mysql-client",
        repos   => "/etc/apt",
    }
);

my %PKG_MAP = (
    rhel_to_debian => {
        httpd => 'apache2',
        mariadb-server => 'mariadb-server',
        mysql-server => 'mysql-server',
        php => 'php',
        php-cli => 'php-cli',
        php-fpm => 'php-fpm',
        bind => 'bind9',
        vsftpd => 'vsftpd',
        postfix => 'postfix',
        dovecot => 'dovecot-core',
        cronie => 'cron',
        firewalld => 'ufw',
    },
    debian_to_rhel => {
        apache2 => 'httpd',
        mariadb-server => 'mariadb-server',
        mysql-server => 'mysql-server',
        php => 'php',
        php-cli => 'php-cli',
        php-fpm => 'php-fpm',
        bind9 => 'bind',
        vsftpd => 'vsftpd',
        postfix => 'postfix',
        dovecot-core => 'dovecot',
        cron => 'cronie',
        ufw => 'firewalld',
    },
);

# ================= RSYNC =================
my $SSH = "ssh -p $SSH_PORT $REMOTE_USER\@$REMOTE_HOST";
my $RSYNC_BASE = "rsync -Aax --numeric-ids --xattrs --acls " . join(" ", @EXCLUDES);
my $RSYNC_PUSH = $RSYNC_BASE . ($UPDATE ? " --ignore-existing " : " --delete ") . ($DRYRUN ? " --dry-run " : "");
my $RSYNC_PULL = $RSYNC_BASE . ($UPDATE ? " --ignore-existing --size-only " : "") . ($DRYRUN ? " --dry-run " : "");

# ================= FUNCTIONS =================
sub run { my ($cmd)=@_; print "[RUN] $cmd\n"; return if $DRYRUN && $cmd !~ /rsync/; system("$cmd >> $LOG 2>&1")==0 or die "FAILED: $cmd\n"; }
sub lock_or_die { open my $fh, ">", $LOCKFILE or die "Cannot lock\n"; flock($fh, LOCK_EX | LOCK_NB) or die "Another run active\n"; }
sub checksum { my ($dir)=@_; run("cd $dir && sha256sum * > SHA256SUMS"); }
sub verify { my ($dir)=@_; run("cd $dir && sha256sum -c SHA256SUMS"); }
sub mailit { my ($s,$b)=@_; open my $m, "|mail -s \"$s\" -r \"$MAIL_FROM\" $MAIL_TO"; print $m $b; close $m; }
sub json_status { my ($st,$msg)=@_; print encode_json({ host=>$HOST,mode=>$MODE,update=>$UPDATE,dryrun=>$DRYRUN,status=>$st,message=>$msg,time=>time() })."\n"; }

sub list_domains {
    my @domains; open my $fh,"virtualmin list-domains --name --user --home |" or die;
    while(<$fh>){ my ($name,$user,$home)=split; push @domains,{name=>$name,user=>$user,home=>$home}; }
    close $fh;
    return @domains;
}
sub domain_info { my ($domain)=@_; for my $d(list_domains()){ return $d if $d->{name} eq $domain; } die "Domain not found: $domain\n"; }
sub skip_package { my ($pkg)=@_; return 1 if $pkg=~/kernel|firmware|grub|systemd|linux-image/; return 1 if $pkg=~/selinux|policycoreutils/; return 0; }
sub translate_packages { my ($src_os,$dst_os,$file)=@_; my @out; open my $fh,"<",$file or die; while(<$fh>){ chomp; my $pkg=$_; next if skip_package($pkg); if($src_os ne $dst_os){ my $map=$PKG_MAP{"${src_os}_to_${dst_os}"}{$pkg}; push @out,$map if $map; } else { push @out,$pkg; } } close $fh; return @out; }

# ================= PRECHECK =================
die "Must be root\n" if $> != 0;
lock_or_die();
make_path($TMPDIR) unless $DRYRUN;

eval {

if($MODE=~/^backup/){
    run("mysqldump -u$MYSQL_USER -p$MYSQL_PASS --all-databases --single-transaction --routines --events > $TMPDIR/db.sql");
    run("$PKG{$OS_FAMILY}{list} > $TMPDIR/packages.txt");
    open my $os,">","$TMPDIR/os.txt"; print $os "$OS_FAMILY\n"; close $os;
    run("tar --xattrs --acls -czf $TMPDIR/etc.tar.gz /etc @EXCLUDES");
    run("tar -czf $TMPDIR/repos.tar.gz $PKG{$OS_FAMILY}{repos}");
    checksum($TMPDIR) unless $DRYRUN;
    run("$SSH 'mkdir -p $REMOTE_BASE/$DATE'");
    run("$RSYNC_PUSH $TMPDIR/ $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/$DATE/meta/");
    run("$RSYNC_PUSH /home/ $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/");
    run("$RSYNC_PUSH /root/ $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/root/");
    run("$SSH 'find $REMOTE_BASE -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \\;'") unless $UPDATE;
    json_status("success","backup complete");
    mailit("SUCCESS backup $HOST","Backup finished");
}

elsif($MODE=~/^restore/){
    if($MODE eq "restore-domain"){
        my $domain=shift @ARGV or die "Domain required\n"; my $d=domain_info($domain);
        run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/$d->{user}/ $d->{home}/");
        run("$SSH 'grep \"CREATE DATABASE .*${domain}\" $REMOTE_BASE/*/meta/db.sql' > $TMPDIR/${domain}.sql");
        run("mysql -u$MYSQL_USER -p$MYSQL_PASS < $TMPDIR/${domain}.sql");
        json_status("success","domain restored: $domain");
        mailit("SUCCESS domain restore $domain","Domain $domain restored");
    } elsif($MODE eq "restore-domains"){
        for my $d(list_domains()){ run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/$d->{user}/ $d->{home}/"); }
        run("mysql -u$MYSQL_USER -p$MYSQL_PASS < $TMPDIR/db.sql");
        json_status("success","all domains restored");
    } else {
        run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/ /home/");
        run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/root/ /root/");
        unless($UPDATE){
            run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/*/meta/ $TMPDIR/");
            verify($TMPDIR) unless $DRYRUN;
            if($OS_FAMILY eq 'rhel'){ run("dnf install -y \$(cat $TMPDIR/packages.txt)"); }
            else{ run("apt-get update"); run("xargs -a $TMPDIR/packages.txt apt-get install -y"); }
            run("tar -xzf $TMPDIR/etc.tar.gz -C /");
            run("tar -xzf $TMPDIR/repos.tar.gz -C /");
            run("mysql -u$MYSQL_USER -p$MYSQL_PASS < $TMPDIR/db.sql");
        }
        json_status("success","restore complete");
        mailit("SUCCESS restore $HOST","Restore finished");
    }
}

elsif($MODE eq "test-restore"){
    my $domain=shift @ARGV; my $TESTDIR="/tmp/restore-test-$DATE"; make_path($TESTDIR);
    if($domain){ my $d=domain_info($domain); run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/$d->{user}/ $TESTDIR/$d->{user}/"); run("mysql -u$MYSQL_USER -p$MYSQL_PASS < <(grep \"$domain\" $REMOTE_BASE/*/meta/db.sql)"); }
    else{ run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/ $TESTDIR/"); }
    die "Restore test failed" unless -d $TESTDIR;
    system("rm -rf $TESTDIR");
    json_status("success","restore test passed");
    mailit("SUCCESS restore test $HOST","Restore test passed");
}

elsif($MODE eq "migrate"){
    die "Migration must not be --dry-run only\n" if $DRYRUN;
    print "=== CROSS-OS MIGRATION MODE ===\n";
    open my $osf,"<","$TMPDIR/os.txt" or die; my $SRC_OS=<$osf>; chomp $SRC_OS; close $osf;
    my @pkgs=translate_packages($SRC_OS,$OS_FAMILY,"$TMPDIR/packages.txt");
    if(@pkgs){ if($OS_FAMILY eq 'rhel'){ run("dnf install -y @pkgs"); } else { run("apt-get update"); run("apt-get install -y @pkgs"); } }
    run("tar -xzf $TMPDIR/etc.tar.gz -C / etc/ssh etc/cron* etc/php*");
    run("mysql -u$MYSQL_USER -p$MYSQL_PASS < $TMPDIR/db.sql");
    for my $d(list_domains()){ run("$RSYNC_PULL $REMOTE_USER\@$REMOTE_HOST:$REMOTE_BASE/current/home/$d->{user}/ $d->{home}/"); }
    json_status("success","cross-OS migration complete");
    mailit("SUCCESS migration $HOST","Cross-OS migration completed");
}

else { die "Invalid mode\n"; }

};

if($@){ json_status("failure",$@); mailit("FAILED $MODE $HOST",$@); die $@; }
system("rm -rf $TMPDIR") unless $DRYRUN;
unlink $LOCKFILE;

