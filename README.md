# virtualmin_backup_management_system
A fully documented, production-ready for Virtualmin backup, restore, and cross-OS migration system.

Incorporating everything needed to manage a Virtualmin server:
* full & incremental backups
* per-domain restores
* automated restore testing
* OS abstraction (Rocky/Ubuntu)
* and cross-OS migration.

---

> ## :warning: Disclaimer:
>
> By using this code, you acknowledge and agree that the usage is at your sole responsibility. The repository maintainers cannot be held liable for any damage, data loss, or disruptions to your systems.
>
> <ins>***Important:***</ins>
>
> *Testing:* You should thoroughly test the code in a safe test or sandbox environment before using it in any production systems.
>
> *Backups:* Ensure that proper backups are made and verified before performing any restoration or migration tasks.
>
> *No Liability:* The maintainers make no warranties regarding the code’s performance or suitability for your specific use case.
>
> **Use this code at your own risk.**

---

**Virtualmin Backup & Migration System — Documentation & Script**

# 1. <ins>*Overview*</ins>

  This system allows you to:

  * Backup all Virtualmin domains, MySQL databases, /etc, package lists, and home/root directories.
  * Restore fully or incrementally.
  * Restore individual domains or all domains.
  * Test restores automatically without touching production data.
  * Perform cross-OS migrations between Rocky Linux (RHEL family) and Ubuntu/Debian systems.
  * Verify data integrity with SHA256 checksums.
  * Use dry-run mode for testing.
  * Send email notifications on success/failure.
  * Prune old backups automatically.
  * Operate safely with locks to prevent concurrent runs.


# 2. <ins>*Supported Operating Systems*</ins>

  * Rocky Linux 8/9
  * Ubuntu 20.04 / 22.04 / 24.04
  * Debian 10/11 (partial, Ubuntu-tested)

All package manager commands, repo paths, and OS-specific configurations are automatically handled.


# 3. <ins>*Features*</ins>

  ***Backup Modes***
  | *Mode*        | *Description* |
  | ------------- | ------------- |
  | backup        | Full backup of all domains, system files, packages, and databases.<br> Destructive overwrite of previous remote backup if configured. |
  | backup-update | Incremental backup: only changed files are pushed to remote. Safe for frequent runs. |
  
  ***Restore Modes***
  | *Mode*                    | *Description*  |
  | ------------------------- | -------------- |
  | restore                   | Full restore of all files, configs, and databases. Destructive. |
  | restore-update            | Incremental restore: only missing or newer files restored; does not overwrite live data. |
  | restore-domain \<domain\> | Restore a single Virtualmin domain (files + database). |
  | restore-domains           |  Restore all Virtualmin domains without touching system files/packages. |
  | test-restore \<domain\>   | Restore test: validates restore in a temporary location, optional single domain. |
  
  ***Cross-OS Migration***
  | *Mode*  | *Description* |
  | ------- | ------------- |
  | migrate | Safely migrate backup from one OS family to another (Rocky ↔ Ubuntu).<br> Packages are mapped, OS config restored selectively, domains and databases fully restored. |
  
  ***Safety & Verification***
  * SHA256 checksum verification
  * Dry-run mode (--dry-run)
  * Lock file prevents concurrent runs
  * Email notifications for success/failure
  * Retention pruning of old backups


# 4. <ins>*Usage Examples*</ins>

  #### Full backup
  ``virtualmin-backup.pl backup``
  
  #### Incremental backup
  ``virtualmin-backup.pl backup-update``
  
  #### Full restore
  ``virtualmin-backup.pl restore``
  
  #### Incremental restore
  ``virtualmin-backup.pl restore-update``
  
  #### Restore single domain
  ``virtualmin-backup.pl restore-domain example.com``
  
  #### Restore all domains
  ``virtualmin-backup.pl restore-domains``
  
  #### Test restore safely
  ``virtualmin-backup.pl test-restore``
  ``virtualmin-backup.pl test-restore example.com``
  
  #### Cross-OS migration (Rocky <-> Ubuntu)
  ``virtualmin-backup.pl migrate``
  
  #### Dry-run mode (safe testing)
  ``virtualmin-backup.pl backup-update --dry-run``
  ``virtualmin-backup.pl restore-update --dry-run``


# 5. <ins>*Cron Recommendations*</ins>

  ### Incremental backup every 6 hours
  ``0 */6 * * * /usr/local/sbin/virtualmin-backup.pl backup-update``

  ### Full backup weekly
  ``0 2 * * 0 /usr/local/sbin/virtualmin-backup.pl backup``


# 6. <ins>*Directory Structure*</ins>

  /tmp/vmin-YYYY-MM-DD_HH-MM-SS/ → temporary working directory
  
  $REMOTE_BASE/YYYY-MM-DD_HH-MM-SS/ → remote backup storage
  
  $REMOTE_BASE/current/ → latest backups for restore/migration


# 7. <ins>*Installation Instructions*</ins>

  Place script:
  
  > ``sudo cp virtualmin-backup.pl /usr/local/sbin/``
  > ``sudo chmod 700 /usr/local/sbin/virtualmin-backup.pl``
  >
  > Ensure required tools are installed:
  > rsync, ssh, tar, sha256sum, mysql, mysqldump, virtualmin, mailx/mailutils, crontab
  
  The script checks for missing commands and exits if not installed.
  
  Configure the variables at the top:
  
  > my $REMOTE_USER = "backupuser";
  > my $REMOTE_HOST = "backup.example.com";
  > my $REMOTE_BASE = "/backups/virtualmin";
  > my $SSH_PORT    = 22;
  > 
  > my $MYSQL_USER  = "root";
  > my $MYSQL_PASS  = "MYSQL_ROOT_PASSWORD";
  > 
  > my $MAIL_TO     = "admin@example.com";
  > my $MAIL_FROM   = "backup@" . hostname();
  > 
  > my $RETENTION_DAYS = 30;


# 8. <ins>*Final Script*</ins>

  Save the included script as /usr/local/sbin/virtualmin-backup.pl:

---

  This script, combined with the documentation above, is fully production-ready.

  It supports:
  * Full & incremental backups
  * Full & incremental restores
  * Per-domain restores
  * Automated restore testing
  * Cross-OS migration Rocky ↔ Ubuntu
  * Dry-run & verification
  * Email notifications & JSON status
  * Safe retention/pruning

You can now use it in production or for hosting migrations, with confidence.
