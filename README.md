# Zimbra / Carbonio Mailbox Restore Script

An automated bash script for restoring (importing) mailboxes from `.tgz` backup archives into a **ZCS (Zimbra Collaboration Suite)** or **Zextras Carbonio** mailbox server.

Designed for flexibility and scale, supporting two distinct operational workflows:
- **Single Account Mode**: Fast, direct restore of an individual mailbox specified directly via command-line arguments, with dedicated per-account logs stored cleanly under `/var/log/restore-mailbox/single/<account_email>.log` without batch summary overhead.
- **Batch / List Mode**: High-performance bulk restoration using a CSV list file with multi-job parallel processing (`-p` / `--parallel`), sequential batch organization (`batch-1`, `batch-2`, ...), live terminal progress monitoring, and consolidated batch summary reports.

---

## 🚀 Key Features

- **Dual Execution Modes (Single & Batch)**:
  - **Single Account**: Fast restore for an individual account directly via CLI arguments, saving logs directly to `/var/log/restore-mailbox/single/<email>.log` without batch summary overhead.
  - **Batch / List (CSV)**: Bulk restoration with multi-job parallel processing (default 5 concurrent jobs, customizable via `-p` / `--parallel`) and complete batch summary reporting.
- **Automatic Platform Detection (Zimbra / Carbonio)**: Automatically detects the mail server platform (`zimbra` in `/opt/zimbra` or `zextras` in `/opt/zextras`), executes commands under the appropriate user (`zimbra` or `zextras`), and configures the correct binary path.
- **Account Existence Pre-check**: Verifies the target account on the mail server (`zmprov ga ... zimbraAccountStatus`) before extracting the archive, skipping non-existent or closed accounts automatically.
- **Proportional Disk-Space Guard**: Automatically calculates required free space before extraction `((3 × archive_size) + 256 MB)` to prevent filling the partition during large restorations.
- **Mailbox Storage & Quota Analysis**: Compares current mailbox usage, backup data size, and account quota (`zimbraMailQuota`). Alerts if quota is exceeded and provides the exact `zmprov ma` command needed to adjust the limit.
- **Duplicate Prevention**: Inspects email `Message-ID` headers prior to importing to prevent duplicate messages in the mailbox.
- **Hierarchical Folder Structure**: Recursively recreates parent directories down to nested subfolders before importing messages (`cf -V message` for Carbonio, `createFolder` for Zimbra), while resolving folder naming conflicts.
- **Real-time Status Monitoring**: Live terminal progress display showing current active folder and processed message counter for all active jobs.
- **Unicode/ASCII Summary & Folder Breakdown Reports**: Generates formatted tabular reports in each account log detailing restored folder breakdown (total, new, duplicate) and overall batch summary for list restorations.
- **Safe Cleanup & Interrupt Handling**: Automatically cleans temporary extraction files upon finish and gracefully terminates child processes and cleans cache on interrupt (`Ctrl+C` / `SIGINT` / `SIGTERM`).
- **Sequential Batch Logging**: In batch mode, automatically detects existing batches and creates the next sequential batch directory (`batch-1`, `batch-2`, etc.) under `/var/log/restore-mailbox/`.

---

## 📋 Requirements

1. Linux server running **Zimbra Collaboration Suite (ZCS)** (user `zimbra`) or **Carbonio / Zextras** (user `zextras`).
2. **Root** privileges (required for switching to `zimbra` or `zextras` user via `su -`).
3. Standard Linux utilities: `tar`, `grep`, `awk`, `find`, `sed`, `df`, `du`.

---

## 🛠️ Usage

### 1. Grant Execute Permissions
```bash
chmod +x import-mailbox.sh
```

### 2. Mode 1: Single Account Restore
Run the script as root by passing the account email and the path to the backup archive:

```bash
sudo ./import-mailbox.sh <account_email> </path/to/backup.tgz>
```

**Example:**
```bash
sudo ./import-mailbox.sh user1@domain.com /backup/user1@domain.com.tgz
```
> **Note:** In Single Account mode, logs are stored directly at `/var/log/restore-mailbox/single/<account_email>.log` without creating batch folders or summary files.

---

### 3. Mode 2: Batch / List Restore (CSV)
Prepare a comma-separated CSV file (`account_email, /path/to/backup.tgz`):

```csv
user1@domain.com, /backup/user1@domain.com.tgz
user2@domain.com, /backup/user2@domain.com.tgz
user3@domain.com, /backup/user3@domain.com.tgz
```

Run the script by passing the path to your CSV file:
```bash
sudo ./import-mailbox.sh /path/to/input_file.csv
```

*(Optional)* Specify the number of concurrent parallel jobs (e.g., 10 parallel restorations):
```bash
sudo ./import-mailbox.sh -p 10 /path/to/input_file.csv
```

---

### 4. Optional Environment Variables

- **Override Mail User (`MAIL_USER`)**:
  Manually enforce `zimbra` or `zextras` platform user:
  ```bash
  sudo MAIL_USER=zimbra ./import-mailbox.sh user1@domain.com /backup/user1@domain.com.tgz
  ```

- **Custom Temporary Directory (`RESTORE_TEMP_BASE`)**:
  Override the temporary extraction directory (default: `/tmp/restore`), recommended when restoring large archives (e.g. 50GB–100GB+):
  ```bash
  sudo RESTORE_TEMP_BASE=/mnt/large-disk/temp ./import-mailbox.sh user1@domain.com /backup/user1@domain.com.tgz
  ```

---

## 🔧 Companion Utility: `fix-folder.sh`

This repository also includes `fix-folder.sh`, an ultra-fast in-place repair tool for corrupted or invisible `unkn` folders in Carbonio and Zimbra mailboxes using `zmsoap FolderActionRequest`.

### Usage:
```bash
chmod +x fix-folder.sh

# Mode 1: Repair folders across ALL server accounts
sudo ./fix-folder.sh

# Mode 2: Repair folders for a SINGLE account
sudo ./fix-folder.sh user1@domain.com

# Mode 3: Repair folders for accounts in a LIST file (one email per line)
sudo ./fix-folder.sh /path/to/accounts.txt
```

---

## 📊 Log & Report Locations

### Mailbox Restore (`import-mailbox.sh`)

- **Single Account Mode**:
  - **Account Log**: `/var/log/restore-mailbox/single/<account_email>.log`
  *(No summary file is generated in single mode)*

- **Batch / List Mode**:
  - **Batch Log Directory**: `/var/log/restore-mailbox/batch-X/`
  - **Summary Report**: `/var/log/restore-mailbox/batch-X/summary_report.txt`
  - **Detailed Account Logs**: `/var/log/restore-mailbox/batch-X/<account_email>.log`

### Folder Repair (`fix-folder.sh`)
- **Base Log Directory**: `/var/log/fix-folder/`
- **Main Log**: `/var/log/fix-folder/fix-folder-all.log`
- **Account Log**: `/var/log/fix-folder/<account_email>.log`

---

## 📄 License

MIT License.
