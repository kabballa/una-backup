# ----------------------------------------------------------------------------------#
#                                                                                   #
#   Copyright (C) 2009 - 2025 Coozila! Licensed under the MIT License.              #
#   Coozila! Team    lab@coozila.com                                                #
#                                                                                   #
# ----------------------------------------------------------------------------------#

#!/bin/bash

# Script: daily_backup.sh
# Location: /opt/kabballa/apps/una-backup/daily_backup.sh
# Purpose: Performs daily backups for UNA sites, handles rotation, and cleanup.

# ==============================================================================
# 1. Load Environment Variables (.env)
# ==============================================================================
# Looks for .env in the 'data' subdirectory relative to the script's location
ENV_FILE="$(dirname "$0")/data/.env" 

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    # Fallback/Error handling if .env is missing or cannot be sourced
    echo "CRITICAL ERROR: .env file not found at $ENV_FILE. Using defaults." >&2
    BASE_BACKUP_DIR="/opt/kabballa/apps/una-backup/data"
    # WWW_DIR must remain here to define where to START looking for sites
    WWW_DIR="/opt/apps/una" 
    RETENTION_DAILY_DAYS=7
    RETENTION_WEEKLY_DAYS=35
    RETENTION_MONTHLY_DAYS=365
fi

# ==============================================================================
# 2. Setup Directories and Date Variables
# ==============================================================================
DAILY_DIR="$BASE_BACKUP_DIR/daily"
WEEKLY_DIR="$BASE_BACKUP_DIR/weekly"
MONTHLY_DIR="$BASE_BACKUP_DIR/monthly"
ANNUAL_DIR="$BASE_BACKUP_DIR/annual"
SCRIPT_LOG="$BASE_BACKUP_DIR/logs/backup_rotation.log"

DATE=$(date +%F)
DAY_OF_WEEK=$(date +%u) # 1 (Mon) to 7 (Sun)
DAY_OF_MONTH=$(date +%d) # 01 to 31
DAY_OF_YEAR=$(date +%j) # 001 to 366

# Create all necessary backup directories and the log directory
mkdir -p "$DAILY_DIR/html" "$DAILY_DIR/db" \
         "$WEEKLY_DIR/html" "$WEEKLY_DIR/db" \
         "$MONTHLY_DIR/html" "$MONTHLY_DIR/db" \
         "$ANNUAL_DIR/html" "$ANNUAL_DIR/db" \
         "$(dirname "$SCRIPT_LOG")"

echo "===== Backup rotation started at $(date) =====" >> "$SCRIPT_LOG"

# ==============================================================================
# 3. Core Functions
# ==============================================================================

# Function to create hard links for long-term retention
link_backups() {
    local SITE_URL="$1"
    local SOURCE_FILE="$2"
    local FILE_TYPE="$3"

    # Check for Sunday (Day 7) for weekly retention
    if [ "$DAY_OF_WEEK" -eq 7 ]; then
        DEST_FILE="$WEEKLY_DIR/$FILE_TYPE/${SITE_URL}-$DATE.tar.gz"
        ln "$SOURCE_FILE" "$DEST_FILE"
        echo "  🔗 Hard-linked $FILE_TYPE for WEEKLY retention." >> "$SCRIPT_LOG"
    fi

    # Check for the 1st day of the month for monthly retention
    if [ "$DAY_OF_MONTH" -eq 01 ]; then
        DEST_FILE="$MONTHLY_DIR/$FILE_TYPE/${SITE_URL}-$DATE.tar.gz"
        ln "$SOURCE_FILE" "$DEST_FILE"
        echo "  🔗 Hard-linked $FILE_TYPE for MONTHLY retention." >> "$SCRIPT_LOG"
    fi

    # Check for the 1st day of the year for annual retention
    if [ "$DAY_OF_YEAR" -eq 001 ]; then
        DEST_FILE="$ANNUAL_DIR/$FILE_TYPE/${SITE_URL}-$DATE.tar.gz"
        ln "$SOURCE_FILE" "$DEST_FILE"
        echo "  🔗 Hard-linked $FILE_TYPE for ANNUAL retention." >> "$SCRIPT_LOG"
    fi
}

# Main function to perform backup for all detected UNA sites
perform_daily_backup() {
    # Find all UNA header files to detect sites within WWW_DIR
    find "$WWW_DIR" -type f -path "*/inc/header.inc.php" | while read HEADER_FILE; do
        
        # --- Extract Site Path (BX_DIRECTORY_PATH_ROOT) ---
        # NOTE: If BX_DIRECTORY_PATH_ROOT is not explicitly defined in header.inc.php, 
        # the fallback extraction logic (dirname $(dirname "$HEADER_FILE")) is used, 
        # which generally points to the site's root directory.
        SITE_DIR=$(grep "define('BX_DIRECTORY_PATH_ROOT'" "$HEADER_FILE" | cut -d"'" -f4)
        [ -z "$SITE_DIR" ] && SITE_DIR=$(dirname $(dirname "$HEADER_FILE"))


        # Extract DB details
        DB_NAME=$(grep "define('BX_DATABASE_NAME'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_USER=$(grep "define('BX_DATABASE_USER'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_PASS=$(grep "define('BX_DATABASE_PASS'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_HOST=$(grep "define('BX_DATABASE_HOST'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_SOCK=$(grep "define('BX_DATABASE_SOCK'" "$HEADER_FILE" | cut -d"'" -f4)
        
        # --- Extract and clean site URL (BX_DOL_URL_ROOT) for file naming ---
        SITE_URL=$(grep "define('BX_DOL_URL_ROOT'" "$HEADER_FILE" | grep -v 'isset' | cut -d"'" -f4 | sed 's|https\?://||;s|/||g')

        # Fallback for site URL if extraction fails
        [ -z "$SITE_URL" ] && SITE_URL=$(basename "$SITE_DIR")

        echo "  Starting daily backup for $SITE_URL (Path: $SITE_DIR) at $(date)" >> "$SCRIPT_LOG"

        # --- 3.1. Files Backup (HTML) ---
        TAR_FILE_PATH="$DAILY_DIR/html/${SITE_URL}-$DATE.tar.gz"
        # Use SITE_DIR (BX_DIRECTORY_PATH_ROOT) as the source directory
        tar -czf "$TAR_FILE_PATH" -C "$SITE_DIR" . 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  ✔️ Files backup for $SITE_URL completed." >> "$SCRIPT_LOG"
            link_backups "$SITE_URL" "$TAR_FILE_PATH" "html"
        else
            echo "  ❌ Files backup for $SITE_URL failed." >> "$SCRIPT_LOG"
            # Output error to stderr for cron email alert
            echo "ERROR: Files backup failed for $SITE_URL (Source Dir: $SITE_DIR)." >&2 
        fi

        # --- 3.2. Database Backup (DB) ---
        DB_FILE_PATH="$DAILY_DIR/db/${SITE_URL}.db-$DATE.sql.gz"
        mysqldump --single-transaction --quick --lock-tables=false \
                  --user="$DB_USER" --password="$DB_PASS" \
                  --host="$DB_HOST" --socket="$DB_SOCK" "$DB_NAME" | gzip > "$DB_FILE_PATH" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  ✔️ Database backup for $SITE_URL completed." >> "$SCRIPT_LOG"
            link_backups "$SITE_URL" "$DB_FILE_PATH" "db"
        else
            echo "  ❌ Database backup for $SITE_URL failed." >> "$SCRIPT_LOG"
            # Output error to stderr for cron email alert
            echo "ERROR: Database backup failed for $SITE_URL (DB: $DB_NAME)." >&2 
        fi
    done
}

# ==============================================================================
# 4. Execution & Cleanup
# ==============================================================================

perform_daily_backup

echo "--- Starting cleanup based on retention policy ---" >> "$SCRIPT_LOG"

# Cleanup Daily backups
find "$DAILY_DIR" -type f -mtime +$RETENTION_DAILY_DAYS -exec rm -f {} \;
echo "  🧹 Cleaned Daily backups older than $RETENTION_DAILY_DAYS days." >> "$SCRIPT_LOG"

# Cleanup Weekly backups
find "$WEEKLY_DIR" -type f -mtime +$RETENTION_WEEKLY_DAYS -exec rm -f {} \;
echo "  🧹 Cleaned Weekly backups older than $RETENTION_WEEKLY_DAYS days." >> "$SCRIPT_LOG"

# Cleanup Monthly backups
find "$MONTHLY_DIR" -type f -mtime +$RETENTION_MONTHLY_DAYS -exec rm -f {} \;
echo "  🧹 Cleaned Monthly backups older than $RETENTION_MONTHLY_DAYS days." >> "$SCRIPT_LOG"

echo "===== Backup rotation completed at $(date) =====" >> "$SCRIPT_LOG"
echo "" >> "$SCRIPT_LOG"