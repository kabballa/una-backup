<p align="center">
  <a href="https://github.com/kabballa/una-backup/blob/master/LICENSE" target="_blank">
    <img src="https://img.shields.io/badge/license-MIT-1c7ed6" alt="License" />
  </a>
</p>

> If you enjoy the project, please consider giving us a GitHub star ⭐️. Thank you!

## 💖 Sponsors

If you want to support our project and help us grow it, you can [become a sponsor on GitHub](https://github.com/sponsors/olariuromeo).

<p align="center">
  <a href="https://github.com/sponsors/olariuromeo">
    <img src="https://img.shields.io/badge/Sponsor%20me%20on-GitHub-blue?logo=github" alt="Sponsor on GitHub" />
  </a>
</p>

# 🧩 KABBALLA – UNA APP Automated Backup & Retention System

> Automated backup rotation, retention, and alert system for UNA CMS.

![una-backupv](assets/backup.png)

This document describes how to configure and automate daily, weekly, monthly, and annual backups for UNA-based sites using **Coozila! KABBALLA Backup System**.

## 📁 1. Directory Structure & Files

| **Path** | **Description** |
| :--- | :--- |
| `/opt/kabballa/apps/una-backup/` | **Base application directory** |
| `/opt/kabballa/apps/una-backup/data/` | **Directory containing all generated backups and configurations** |
| `/opt/kabballa/apps/una-backup/data/.env` | Environment configuration file |
| `/opt/una` | Root directory containing UNA sites |
| `/opt/kabballa/apps/una-backup/daily_backup.sh` | Main backup automation script |
| `/opt/kabballa/apps/una-backup/data/logs/backup_rotation.log` | Backup log file |



### Initial Setup & Installation

To deploy the **UNA Backup** system, follow these steps to clone the repository and set up the directory structure.

### Clone the Repository

Navigate to the `/opt/kabballa/apps/` directory and clone the project:

```bash
mkdir -p /opt/kabballa
mkdir -p /opt/kabballa/apps
cd /opt/kabballa/apps/
git clone https://github.com/kabballa/una-backup.git
```

### Create Data Directory

The backup system requires a dedicated directory for configuration and log files:

```bash
mkdir -p /opt/kabballa/apps/una-backup/data/
```

## ⚙️ 2. Environment Configuration (`.env`)

#### Prepare the Environment Variables

Copy the example environment file and configure it:

```bash
cp .env.example .env
````

Edit the `.env` file to set the required variables for your setup.

## 🧠 3. Main Script (`daily_backup.sh`)

Path to the main script:

```
/opt/kabballa/apps/una-backup/daily_backup.sh
```

Make it executable:

```bash
chmod +x /opt/kabballa/apps/una-backup/daily_backup.sh
```

## ⏰ 4. Automate the Script with Cron

Edit your crontab:

```bash
crontab -e
```

Add this section:

```cron
# ----------------------------------------------------------------------------------#
#   Copyright (C) 2009 - 2025 Coozila! Licensed under the MIT License.              #
#   Coozila! Team    lab@coozila.com                                                #
# ----------------------------------------------------------------------------------#

# The email address to receive alerts
MAILTO="your.email@example.com"

# CRON Schedule Examples for daily_backup.sh
# ------------------------------------------------
# 1. Daily backup at 03:00 AM
#    - STDOUT is discarded (success messages)
#    - STDERR is emailed automatically to $MAILTO
0 3 * * * /opt/kabballa/apps/una-backup/daily_backup.sh >> /dev/null

# 2. Daily backup at 02:00 AM, log output to a file
#    - Keeps a daily log at /var/log/una_backup.log
#0 2 * * * /opt/kabballa/apps/una-backup/daily_backup.sh >> /var/log/una_backup.log 2>&1

# 3. Weekly backup on Sundays at 04:00 AM
#    - Combines both STDOUT and STDERR in one log
#0 4 * * 0 /opt/kabballa/apps/una-backup/daily_backup.sh >> /var/log/una_backup_weekly.log 2>&1

# Notes:
# - Adjust the PATH to daily_backup.sh if installed in a different location
# - Make sure the user running the cron has execution permissions
# - MAILTO must be set for email alerts on errors
```

## 📧 5. Email Alert Behavior

| **Type**  | **Behavior**                                                       |
| :-------- | :----------------------------------------------------------------- |
| ✅ Success | All logs written to `$SCRIPT_LOG`. No stdout/stderr → no email.    |
| ⚠️ Error  | Script writes to `stderr` → cron sends an alert email to `MAILTO`. |

## 🔍 6. Verification

After execution, check:

```bash
cat /opt/kabballa/apps/una-backup/data/logs/backup_rotation.log
```

Expected output:

```
===== Backup rotation completed at YYYY-MM-DD HH:MM:SS =====
```

## Summary

| **Task**               | **Command**                                                       |
| :--------------------- | :---------------------------------------------------------------- |
| Make script executable | `chmod +x /opt/kabballa/apps/una-backup/daily_backup.sh`          |
| Test manually          | `/opt/kabballa/apps/una-backup/daily_backup.sh`                   |
| View logs              | `cat /opt/kabballa/apps/una-backup/data/logs/backup_rotation.log` |
| Edit cron              | `crontab -e`                                                      |
| Edit .env              | `nano /opt/kabballa/apps/una-backup/data/.env`                    |

> 🧠 **Tip:** Extend the backup system with `rclone` or `rsync` to replicate backups to remote storage (e.g., S3, Google Drive, Ceph Object Gateway).

## 🤝 7. Contributing

We welcome contributions to this project!
Please refer to our [Contributing Guidelines](CONTRIBUTING.md) for detailed instructions on how to contribute.

For questions or contributions, feel free to contact the **Backup Developer** at [lab@coozila.com](mailto:lab@coozila.com).


## 🧭 8. Code of Conduct

We are committed to fostering an inclusive and respectful environment.
Please review our [Code of Conduct](CODE_OF_CONDUCT.md) for guidelines on acceptable behavior.

## 🏷️ 9, Trademarks and Copyright

This software listing is packaged by Romulus.
All trademarks mentioned are the property of their respective owners, and their use does not imply any affiliation or endorsement.

### Copyright

Copyright (C) 2009–2025 **Coozila!**
Licensed under the [MIT License](https://github.com/kabballa/una-backup/blob/master/LICENSE).

## Installation Assistance

If you would like assistance with the installation of **KABBALLA – UNA APP Automated Backup & Retention System**, please contact **Romulus** at [lab@coozila.com](mailto:lab@coozila.com).  
I will be happy to help you with the installation process and ensure a smooth setup.

Based on the size and complexity of your UNA project, we will provide you with a tailored pricing quote.

If you prefer, you can also directly pay for professional installation assistance via this product page:  
[Purchase KABBALLA Installation](https://unacms.com/view-product/-kabballa-backup-for-una-cms)

You can also check out my profile for more information and other UNA-related solutions:  
[Romulus](https://unacms.com/u/olariu-romeo-vicentiu)

### After Purchase Notes

After your purchase, please provide the following information via email:

- Server login credentials  
- An SSH key for secure access  
- Details about the UNA site(s) you wish to integrate  
- Preferred backup frequency (daily / weekly / monthly)

> 💡 *All installations are handled securely and in full compliance with the MIT License terms.*


## ⚖️ 10. Disclaimer

This product is provided "as is," without any guarantees or warranties regarding its functionality, performance, or reliability.
By using this product, you acknowledge that you do so at your own risk.
Romulus and its contributors are not liable for any issues, damages, or losses that may arise from the use of this product.
We recommend thoroughly testing the product in your own environment before deploying it in a production setting.

**Happy coding! 🚀**