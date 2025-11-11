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
#
# RETENTION POLICY:
# - Daily: Retain 7 days using mtime (time-based cleanup).
# - Weekly & Monthly: Retain based on count (number of copies to keep) using file separation (MOVE).
# - Annual: Retained indefinitely (MOVED only on Day 001).

# ==============================================================================
# 1. Load Environment Variables (.env)
# ==============================================================================
ENV_FILE="$(dirname "$0")/data/.env" 

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    # CRITICAL ERROR: .env file missing. Using defaults.
    echo "CRITICAL ERROR: .env file not found at $ENV_FILE. Using defaults." >&2
    BASE_BACKUP_DIR="/opt/kabballa/apps/una-backup/data"
    WWW_DIR="/opt/una"
    RETENTION_DAILY_DAYS=7
    RETENTION_WEEKLY_COUNT=6
    RETENTION_MONTHLY_COUNT=12
fi

# Ensure all necessary retention variables are set
RETENTION_DAILY_DAYS=${RETENTION_DAILY_DAYS:-7}
RETENTION_WEEKLY_COUNT=${RETENTION_WEEKLY_COUNT:-6}
RETENTION_MONTHLY_COUNT=${RETENTION_MONTHLY_COUNT:-12}
WWW_DIR=${WWW_DIR:-/opt/una}

# ==============================================================================
# 2. Setup Directories and Date Variables
# ==============================================================================
DAILY_DIR="$BASE_BACKUP_DIR/daily"
WEEKLY_DIR="$BASE_BACKUP_DIR/weekly"
MONTHLY_DIR="$BASE_BACKUP_DIR/monthly"
ANNUAL_DIR="$BASE_BACKUP_DIR/annual"
SCRIPT_LOG="$BASE_BACKUP_DIR/logs/backup_rotation.log"

DATE=$(date +%F)
DAY_OF_WEEK=$(date +%u)   # 1 (Mon) to 7 (Sun)
DAY_OF_MONTH=$(date +%d)  # 01 to 31
DAY_OF_YEAR=$(date +%j)   # 001 to 366

mkdir -p "$DAILY_DIR/html" "$DAILY_DIR/db" \
         "$WEEKLY_DIR/html" "$WEEKLY_DIR/db" \
         "$MONTHLY_DIR/html" "$MONTHLY_DIR/db" \
         "$ANNUAL_DIR/html" "$ANNUAL_DIR/db" \
         "$(dirname "$SCRIPT_LOG")"

echo "===== Backup rotation started at $(date) =====" >> "$SCRIPT_LOG"

# ==============================================================================
# 3. Core Functions
# ==============================================================================

# Function to move daily backups to long-term retention folders
handle_retention_move() {
    local BX_DOL_URL_ROOT="$1" 
    local SOURCE_FILE="$2"
    local FILE_TYPE="$3"
    
    local TARGET_DIR=""
    local LOG_MSG=""
    
    if [ "$DAY_OF_YEAR" -eq 1 ]; then
        TARGET_DIR="$ANNUAL_DIR"
        LOG_MSG="ANNUAL"
    elif [ "$DAY_OF_MONTH" -eq 01 ]; then
        TARGET_DIR="$MONTHLY_DIR"
        LOG_MSG="MONTHLY"
    elif [ "$DAY_OF_WEEK" -eq 7 ]; then
        TARGET_DIR="$WEEKLY_DIR"
        LOG_MSG="WEEKLY"
    fi
    
    if [ -n "$TARGET_DIR" ]; then
        DEST_FILE="$TARGET_DIR/$FILE_TYPE/${BX_DOL_URL_ROOT}-$DATE.tar.gz"
        mv "$SOURCE_FILE" "$DEST_FILE"
        echo "  ➡️ Moved $FILE_TYPE for $LOG_MSG retention." >> "$SCRIPT_LOG"
    fi
}

# Main function to perform backup for all detected UNA sites
perform_daily_backup() {
    find "$WWW_DIR" -type f -path "*/inc/header.inc.php" | while read HEADER_FILE; do
        
        SITE_DIR=$(grep "define('BX_DIRECTORY_PATH_ROOT'" "$HEADER_FILE" | cut -d"'" -f4)
        [ -z "$SITE_DIR" ] && SITE_DIR=$(dirname $(dirname "$HEADER_FILE"))

        DB_NAME=$(grep "define('BX_DATABASE_NAME'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_USER=$(grep "define('BX_DATABASE_USER'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_PASS=$(grep "define('BX_DATABASE_PASS'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_HOST=$(grep "define('BX_DATABASE_HOST'" "$HEADER_FILE" | cut -d"'" -f4)
        DB_SOCK=$(grep "define('BX_DATABASE_SOCK'" "$HEADER_FILE" | cut -d"'" -f4)
        
        BX_DOL_URL_ROOT=$(grep "define('BX_DOL_URL_ROOT'" "$HEADER_FILE" | grep -v 'isset' | cut -d"'" -f4 | sed 's|https\?://||;s|/||g')
        [ -z "$BX_DOL_URL_ROOT" ] && BX_DOL_URL_ROOT=$(basename "$SITE_DIR")

        echo "  Starting daily backup for $BX_DOL_URL_ROOT (Path: $SITE_DIR) at $(date)" >> "$SCRIPT_LOG"

        # --- 3.1. Files Backup (HTML) ---
        TAR_FILE_PATH="$DAILY_DIR/html/${BX_DOL_URL_ROOT}-$DATE.tar.gz"
        tar -czf "$TAR_FILE_PATH" -C "$SITE_DIR" . 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  ✔️ Files backup for $BX_DOL_URL_ROOT completed." >> "$SCRIPT_LOG"
            handle_retention_move "$BX_DOL_URL_ROOT" "$TAR_FILE_PATH" "html"
        else
            echo "  ❌ Files backup for $BX_DOL_URL_ROOT failed." >> "$SCRIPT_LOG"
            echo "ERROR: Files backup failed for $BX_DOL_URL_ROOT (Source Dir: $SITE_DIR)." >&2 
        fi

        # --- 3.2. Database Backup (DB) ---
        DB_FILE_PATH="$DAILY_DIR/db/${BX_DOL_URL_ROOT}.db-$DATE.sql.gz"

        if ! command -v mysqldump >/dev/null 2>&1; then
            echo "  ❌ mysqldump not found. Skipping database backup for $BX_DOL_URL_ROOT." >> "$SCRIPT_LOG"
        else
            DB_SOCKET_ARG=""
            [ -n "$DB_SOCK" ] && DB_SOCKET_ARG="--socket=$DB_SOCK"

            mysqldump --single-transaction --quick --lock-tables=false \
                      --user="$DB_USER" --password="$DB_PASS" \
                      --host="$DB_HOST" $DB_SOCKET_ARG "$DB_NAME" | gzip > "$DB_FILE_PATH" 2>/dev/null

            if [ $? -eq 0 ]; then
                echo "  ✔️ Database backup for $BX_DOL_URL_ROOT completed." >> "$SCRIPT_LOG"
                handle_retention_move "$BX_DOL_URL_ROOT" "$DB_FILE_PATH" "db"
            else
                echo "  ❌ Database backup for $BX_DOL_URL_ROOT failed." >> "$SCRIPT_LOG"
                echo "ERROR: Database backup failed for $BX_DOL_URL_ROOT (DB: $DB_NAME)." >&2 
            fi
        fi
    done
}

# Cleanup function based on file count
cleanup_by_count() {
    local DIR_PATH="$1"
    local COUNT="$2"
    local TYPE="$3"

    local FILES_TO_KEEP=$((COUNT + 1))
    
    (ls -t "$DIR_PATH/html"/*.tar.gz 2>/dev/null | tail -n +$FILES_TO_KEEP | xargs -r rm -f)
    (ls -t "$DIR_PATH/db"/*.sql.gz 2>/dev/null | tail -n +$FILES_TO_KEEP | xargs -r rm -f)
    
    echo "  🧹 Cleaned $TYPE backups, keeping the $COUNT most recent copies." >> "$SCRIPT_LOG"
}

# ==============================================================================
# 4. Execution & Cleanup
# ==============================================================================

perform_daily_backup

echo "--- Starting cleanup based on retention policy ---" >> "$SCRIPT_LOG"

# Daily cleanup (time-based)
find "$DAILY_DIR" -type f -mtime +$RETENTION_DAILY_DAYS -exec rm -f {} \;
echo "  🧹 Cleaned Daily backups older than $RETENTION_DAILY_DAYS days." >> "$SCRIPT_LOG"

# Weekly & Monthly cleanup (count-based)
cleanup_by_count "$WEEKLY_DIR" "$RETENTION_WEEKLY_COUNT" "Weekly"
cleanup_by_count "$MONTHLY_DIR" "$RETENTION_MONTHLY_COUNT" "Monthly"

# Annual backups are kept indefinitely
echo "  Annual backups are kept indefinitely." >> "$SCRIPT_LOG"

echo "===== Backup rotation completed at $(date) =====" >> "$SCRIPT_LOG"
echo "" >> "$SCRIPT_LOG"
