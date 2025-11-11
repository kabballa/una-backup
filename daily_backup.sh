# ----------------------------------------------------------------------------------#
#                                                                                   #
#   Copyright (C) 2009 - 2025 Coozila! Licensed under the MIT License.              #
#   Coozila! Team    lab@coozila.com                                                #
#                                                                                   #
# ----------------------------------------------------------------------------------#

#!/bin/bash

# Script: daily_backup.sh
# Purpose: Perform daily backups for one or more UNA sites defined in .env,
#          handles rotation and cleanup.
#
# RETENTION POLICY:
# - Daily: Keep 7 days (time-based cleanup).
# - Weekly & Monthly: Keep N most recent copies (count-based cleanup).
# - Annual: Kept indefinitely (moved only on January 1st).

# ==============================================================================
# 1. Load Environment Variables (.env)
# ==============================================================================
ENV_FILE="$(dirname "$0")/data/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "CRITICAL ERROR: .env file not found at $ENV_FILE. Using defaults." >&2
    BASE_BACKUP_DIR="/opt/kabballa/apps/una-backup/data"
    BX_DIRECTORY_PATH_ROOT="/opt/una"  # Default single site
    RETENTION_DAILY_DAYS=7
    RETENTION_WEEKLY_COUNT=4
    RETENTION_MONTHLY_COUNT=12
fi

# Ensure defaults if variables missing
BASE_BACKUP_DIR=${BASE_BACKUP_DIR:-/opt/kabballa/apps/una-backup/data}
BX_DIRECTORY_PATH_ROOT=${BX_DIRECTORY_PATH_ROOT:-/opt/una}
RETENTION_DAILY_DAYS=${RETENTION_DAILY_DAYS:-7}
RETENTION_WEEKLY_COUNT=${RETENTION_WEEKLY_COUNT:-4}
RETENTION_MONTHLY_COUNT=${RETENTION_MONTHLY_COUNT:-12}

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

handle_retention_move() {
    local SITE_NAME="$1"
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
        DEST_FILE="$TARGET_DIR/$FILE_TYPE/${SITE_NAME}-$DATE.tar.gz"
        mv "$SOURCE_FILE" "$DEST_FILE"
        echo "  ➡️ Moved $FILE_TYPE for $LOG_MSG retention." >> "$SCRIPT_LOG"
    fi
}

perform_backup_for_site() {
    local SITE_DIR="$1"
    local HEADER_FILE="$SITE_DIR/inc/header.inc.php"

    if [ ! -f "$HEADER_FILE" ]; then
        echo "ERROR: header.inc.php not found in $SITE_DIR. Skipping." >&2
        echo "  ❌ Backup skipped for $SITE_DIR" >> "$SCRIPT_LOG"
        return
    fi

    DB_NAME=$(grep "define('BX_DATABASE_NAME'" "$HEADER_FILE" | cut -d"'" -f4)
    DB_USER=$(grep "define('BX_DATABASE_USER'" "$HEADER_FILE" | cut -d"'" -f4)
    DB_PASS=$(grep "define('BX_DATABASE_PASS'" "$HEADER_FILE" | cut -d"'" -f4)
    DB_HOST=$(grep "define('BX_DATABASE_HOST'" "$HEADER_FILE" | cut -d"'" -f4)
    DB_SOCK=$(grep "define('BX_DATABASE_SOCK'" "$HEADER_FILE" | cut -d"'" -f4)

    # Extract site URL and clean it
    RAW_URL=$(grep "define('BX_DOL_URL_ROOT'" "$HEADER_FILE" | grep -v 'isset' | cut -d"'" -f4)
    CLEAN_URL=${RAW_URL#https://}
    CLEAN_URL=${CLEAN_URL#http://}
    BX_DOL_URL_ROOT=${CLEAN_URL%/}   # remove trailing slash only

    [ -z "$BX_DOL_URL_ROOT" ] && BX_DOL_URL_ROOT=$(basename "$SITE_DIR")

    echo "  Starting backup for $BX_DOL_URL_ROOT (Path: $SITE_DIR) at $(date)" >> "$SCRIPT_LOG"

    # --- Files Backup (HTML) ---
    TAR_FILE_PATH="$DAILY_DIR/html/${BX_DOL_URL_ROOT}-$DATE.tar.gz"
    tar -czf "$TAR_FILE_PATH" -C "$SITE_DIR" . 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  ✔️ Files backup completed for $BX_DOL_URL_ROOT" >> "$SCRIPT_LOG"
        handle_retention_move "$BX_DOL_URL_ROOT" "$TAR_FILE_PATH" "html"
    else
        echo "  ❌ Files backup failed for $BX_DOL_URL_ROOT" >> "$SCRIPT_LOG"
    fi

    # --- Database Backup (DB) ---
    DB_FILE_PATH="$DAILY_DIR/db/${BX_DOL_URL_ROOT}.db-$DATE.sql.gz"

    if ! command -v mysqldump >/dev/null 2>&1; then
        echo "  ❌ mysqldump not found. Skipping DB backup for $BX_DOL_URL_ROOT" >> "$SCRIPT_LOG"
    else
        DB_SOCKET_ARG=""
        [ -n "$DB_SOCK" ] && DB_SOCKET_ARG="--socket=$DB_SOCK"

        mysqldump --single-transaction --quick --lock-tables=false \
                  --user="$DB_USER" --password="$DB_PASS" \
                  --host="$DB_HOST" $DB_SOCKET_ARG "$DB_NAME" | gzip > "$DB_FILE_PATH" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "  ✔️ Database backup completed for $BX_DOL_URL_ROOT" >> "$SCRIPT_LOG"
            handle_retention_move "$BX_DOL_URL_ROOT" "$DB_FILE_PATH" "db"
        else
            echo "  ❌ Database backup failed for $BX_DOL_URL_ROOT" >> "$SCRIPT_LOG"
        fi
    fi
}

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

# Split comma-separated sites into array
IFS=',' read -ra SITES <<< "$BX_DIRECTORY_PATH_ROOT"

for SITE_DIR in "${SITES[@]}"; do
    SITE_DIR=$(echo "$SITE_DIR" | xargs)  # Trim whitespace
    perform_backup_for_site "$SITE_DIR"
done

echo "--- Starting cleanup based on retention policy ---" >> "$SCRIPT_LOG"

# Daily cleanup (time-based)
find "$DAILY_DIR" -type f -mtime +$RETENTION_DAILY_DAYS -exec rm -f {} \;
echo "  🧹 Cleaned Daily backups older than $RETENTION_DAILY_DAYS days." >> "$SCRIPT_LOG"

# Cleanup weekly backups (keep only RETENTION_WEEKLY_COUNT most recent files)
cleanup_by_count "$WEEKLY_DIR" "$RETENTION_WEEKLY_COUNT" "Weekly"

# Cleanup monthly backups (keep only RETENTION_MONTHLY_COUNT most recent files)
cleanup_by_count "$MONTHLY_DIR" "$RETENTION_MONTHLY_COUNT" "Monthly"

# Annual backups are kept indefinitely
echo "  Annual backups are kept indefinitely." >> "$SCRIPT_LOG"

echo "===== Backup rotation completed at $(date) =====" >> "$SCRIPT_LOG"
echo "" >> "$SCRIPT_LOG"
