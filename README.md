# Virtualmin Backup Management System

A fully documented, production-ready backup, restore, and cross-OS migration management system built specifically for **Virtualmin** (Webmin).

Unlike generic file-copy scripts, this system utilizes Virtualmin's native CLI export and restore engine (`virtualmin backup-domain` and `virtualmin restore-domain`). Every virtual server is exported into an isolated, self-contained archive bundling its Apache/Nginx web configurations, DNS records, SSL/TLS certificates, mailboxes, and MySQL/MariaDB databases.

---

> ## :warning: Disclaimer
>
> By using this code, you acknowledge and agree that usage is at your sole responsibility. The repository maintainers cannot be held liable for any damage, data loss, or disruptions to your systems.
>
> **Important:**
> * **Testing:** Thoroughly test the code in a safe test or sandbox environment before using it in any production systems.
> * **Backups:** Ensure that proper backups are verified before performing any restoration or migration tasks.
> * **Use this code at your own risk.**

---

# 1. Overview & Architecture

### Why Native Virtualmin CLI Export?
Raw file synchronization (`rsync /home` and `mysqldump --all-databases`) misses Virtualmin internal metadata, server plans, custom templates, and DNS zone configurations, and can corrupt live databases or break permissions. 

This system resolves those issues by executing Virtualmin's native export engine:
* **Per-Domain Archive Bundles:** Uses `virtualmin backup-domain --all-domains --all-features --newformat --dest .../%d.tar.gz` to create individual `.tar.gz` archives per domain containing web files, databases, mailboxes, SSL certificates, and DNS settings.
* **Global Configuration Preservation:** Backs up server templates, custom fields, and account plans via `virtualmin backup-domain --all-virtualmin`.
* **System Package & Core State:** Catalogs installed packages (`rpm -qa` on RHEL/Rocky, `dpkg-query` on Debian/Ubuntu) and archives core system files (`/etc/hosts`, `/etc/resolv.conf`, `/etc/fstab`, `/etc/ssh`).
* **No Database Passwords in Script:** MySQL/MariaDB authentication is handled natively through Virtualmin's internal subsystem, eliminating plain-text root database passwords from configuration.
* **Safe Remote Transport:** Rsync and SSH operations fully propagate custom SSH ports (`-p $SSH_PORT`).
* **Integrity Checksums:** Generates and verifies SHA256 checksums (`SHA256SUMS`) for all archives.
* **Safe Retention Pruning:** The remote prune command targets only dated directories (`-name "20*" -mindepth 1`), preventing accidental deletion of the base directory or manual uploads.
* **Seamless Cross-OS Portability:** Native Virtualmin archives can be restored directly between Rocky Linux / RHEL and Ubuntu / Debian servers using `--reallocate-ip` and `--skip-warnings`.

---

# 2. Supported Operating Systems

* **Rocky Linux / AlmaLinux / RHEL / CentOS 8 & 9**
* **Ubuntu 20.04 / 22.04 / 24.04 LTS**
* **Debian 10 / 11 / 12**

OS family detection and package listing commands are handled automatically.

---

# 3. Command Modes

| Mode | Syntax | Description |
| :--- | :--- | :--- |
| **`backup`** / **`backup-update`** | `virtualmin-backup.pl backup [--dry-run]` | Exports all virtual servers into individual `.tar.gz` bundles, exports global Virtualmin settings, records system package inventory and `/etc` network configs, generates SHA256 checksums, uploads to remote storage, and prunes old backups (`backup-update` is supported as an alias). |
| **`restore`** | `virtualmin-backup.pl restore [backup_date] [--dry-run]` | Full server restore. Downloads remote backup for the specified date (or defaults to the latest backup), verifies SHA256 checksums, restores global Virtualmin templates/plans, and restores all virtual servers. |
| **`restore-domain`** | `virtualmin-backup.pl restore-domain <domain.com> [backup_date] [--dry-run]` | Downloads and restores a single domain (web files, mailboxes, DNS, SSL, and MySQL databases) from remote storage. |
| **`restore-domains`** | `virtualmin-backup.pl restore-domains [backup_date] [--dry-run]` | Restores all virtual server domain archives from remote storage without overwriting global server templates. |
| **`upload`** | `virtualmin-backup.pl upload </path/to/archive_or_dir> [dest_folder] [--dry-run]` | Uploads a local archive file or entire directory directly to the remote backup repository (defaults to `manual_uploads` or a custom subfolder). |
| **`import`** | `virtualmin-backup.pl import </path/to/archive_or_dir> [--all] [--dry-run]` | Imports a local domain archive or an entire directory of archives into Virtualmin using native restore with `--reallocate-ip` and `--skip-warnings`. |
| **`test-restore`** | `virtualmin-backup.pl test-restore [domain.com] [backup_date] [--dry-run]` | Validates remote backup accessibility. If a domain is specified, pulls the archive and verifies its tar structure integrity (`tar -tzf`). If omitted, tests remote rsync reachability. |
| **`migrate`** | `virtualmin-backup.pl migrate [backup_date] [--dry-run]` | Cross-OS / server migration. Downloads remote archives and restores them using Virtualmin's native restore engine with automatic IP reallocation and warning tolerance. |

---

# 4. Usage Examples

### Full Backup
```bash
/usr/local/sbin/virtualmin-backup.pl backup
```

### Full Restore (Latest Backup)
```bash
/usr/local/sbin/virtualmin-backup.pl restore
```

### Full Restore from a Specific Date
```bash
/usr/local/sbin/virtualmin-backup.pl restore 2026-09-12_18-00-00
```

### Restore a Single Domain
```bash
/usr/local/sbin/virtualmin-backup.pl restore-domain example.com
```

### Restore a Single Domain from a Specific Date
```bash
/usr/local/sbin/virtualmin-backup.pl restore-domain example.com 2026-09-12_18-00-00
```

### Restore All Domains
```bash
/usr/local/sbin/virtualmin-backup.pl restore-domains
```

### Upload a Local Archive or Directory to Remote Storage
```bash
# Upload a single archive file
/usr/local/sbin/virtualmin-backup.pl upload /tmp/example.com.tar.gz

# Upload to a custom remote folder
/usr/local/sbin/virtualmin-backup.pl upload /tmp/example.com.tar.gz custom_backups

# Upload an entire directory of archives
/usr/local/sbin/virtualmin-backup.pl upload /tmp/domains_dir/ custom_backups
```

### Import a Local Domain Archive into Virtualmin
```bash
# Import a single domain archive
/usr/local/sbin/virtualmin-backup.pl import /tmp/example.com.tar.gz

# Import all domain archives within a directory
/usr/local/sbin/virtualmin-backup.pl import /tmp/domains_dir/ --all
```

### Test Restore Safely (Non-Destructive)
```bash
# Test remote connectivity and latest backup availability
/usr/local/sbin/virtualmin-backup.pl test-restore

# Test remote availability for a specific backup date
/usr/local/sbin/virtualmin-backup.pl test-restore 2026-09-12_18-00-00

# Test integrity of a specific domain archive from latest backup
/usr/local/sbin/virtualmin-backup.pl test-restore example.com

# Test integrity of a specific domain archive from a specific backup date
/usr/local/sbin/virtualmin-backup.pl test-restore example.com 2026-09-12_18-00-00
```

### Cross-OS Migration (Rocky Linux ↔ Ubuntu / Debian)
```bash
/usr/local/sbin/virtualmin-backup.pl migrate
```

### Dry-Run Mode (Simulate without Making Changes)
```bash
/usr/local/sbin/virtualmin-backup.pl backup --dry-run
/usr/local/sbin/virtualmin-backup.pl restore --dry-run
/usr/local/sbin/virtualmin-backup.pl restore-domain example.com --dry-run
```

---

# 5. Remote Storage Directory Structure

```text
$REMOTE_BASE/
├── 2026-09-12_18-00-00/
│   ├── domains/
│   │   ├── domain1.com.tar.gz
│   │   ├── domain2.com.tar.gz
│   │   └── SHA256SUMS
│   └── meta/
│       ├── virtualmin-globals.tar.gz
│       ├── packages.txt
│       ├── etc-essential.tar.gz
│       └── SHA256SUMS
├── 2026-09-13_18-00-00/
│   ├── domains/
│   └── meta/
└── manual_uploads/
    └── custom-domain.tar.gz
```

* **Dated Snapshots:** Each backup run creates a dedicated `$DATE` directory containing isolated `domains/` and `meta/` subdirectories.
* **Automatic Retention:** The pruning routine deletes dated directories matching `-name "20*"` that are older than `$RETENTION_DAYS`. Subfolders such as `manual_uploads/` are never deleted by the retention cleaner.

---

# 6. Installation & Configuration

### 1. Place and Secure the Script
```bash
sudo cp virtualmin-backup.pl /usr/local/sbin/
sudo chmod 700 /usr/local/sbin/virtualmin-backup.pl
sudo chown root:root /usr/local/sbin/virtualmin-backup.pl
```

### 2. Prerequisites
Ensure required tools and Perl modules are installed:
* **CLI Tools:** `virtualmin`, `rsync`, `ssh`, `tar`, `sha256sum`, `mail` (`mailx` or `mailutils`)
* **Perl Modules:** `JSON`, `POSIX`, `File::Path`, `Sys::Hostname`, `Fcntl`

On RHEL / Rocky Linux:
```bash
sudo dnf install -y rsync openssh-clients tar perl-JSON mailx
```

On Ubuntu / Debian:
```bash
sudo apt-get update
sudo apt-get install -y rsync openssh-client tar libjson-perl mailutils
```

### 3. Configure Variables
Edit the configuration block at the top of `/usr/local/sbin/virtualmin-backup.pl`:

```perl
# ================= CONFIG =================
my $REMOTE_USER    = "backupuser";
my $REMOTE_HOST    = "backup.example.com";
my $REMOTE_BASE    = "/backups/virtualmin";
my $SSH_PORT       = 22;

my $MAIL_TO        = 'admin@example.com';
my $MAIL_FROM      = "backup@" . hostname();

my $LOCKFILE       = "/var/run/virtualmin-backup.lock";
my $RETENTION_DAYS = 30;
```

> **Note on Database Passwords:** Root database credentials are not needed in this configuration. Virtualmin securely authenticates with MySQL/MariaDB through its internal subsystem.

### 4. Setup SSH Key Authentication
Ensure root on the Virtualmin server has passwordless SSH access to `$REMOTE_USER@$REMOTE_HOST`:
```bash
ssh-copy-id -p 22 backupuser@backup.example.com
```

---

# 7. Automated Scheduling (Cron)

Edit root's crontab (`sudo crontab -e`):

```cron
# Run daily Virtualmin backup at 02:00 AM
0 2 * * * /usr/local/sbin/virtualmin-backup.pl backup

# Run weekly backup test on Sunday at 04:00 AM
0 4 * * 0 /usr/local/sbin/virtualmin-backup.pl test-restore
```

---

# 8. Monitoring & Safety Features

* **File Locking:** Prevents overlapping backup or restore jobs via `/var/run/virtualmin-backup.lock`. Locks are released on normal exit or failure.
* **JSON Status Output:** Emits machine-readable JSON status objects (`host`, `mode`, `status`, `message`, `time`, `dryrun`) to stdout for integration with centralized log management (ELK, Grafana Loki, Datadog).
* **Email Alerts:** Sends detailed email notifications on success and failure with the specific command and host information.
* **Integrity Validation:** Every domain archive and metadata bundle is checksummed with SHA256 and checked prior to restoration.
