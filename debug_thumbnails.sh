#!/bin/bash
# Thumbnail debugging script for MiniDLNA

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== MiniDLNA Thumbnail Debug Script ==="
echo ""

# Find database location
DB_DIR="/var/cache/minidlna"
if [ -f "/etc/minidlna.conf" ]; then
    DB_FROM_CONF=$(grep "^db_dir=" /etc/minidlna.conf | cut -d= -f2)
    if [ -n "$DB_FROM_CONF" ]; then
        DB_DIR="$DB_FROM_CONF"
    fi
fi

DB_FILE="$DB_DIR/files.db"

echo -e "${YELLOW}Database location:${NC} $DB_FILE"

if [ ! -f "$DB_FILE" ]; then
    echo -e "${RED}ERROR: Database not found at $DB_FILE${NC}"
    exit 1
fi

echo ""
echo "=== Checking for video files in database ==="
VIDEO_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM DETAILS WHERE MIME LIKE 'video/%';")
echo -e "Total video files indexed: ${GREEN}$VIDEO_COUNT${NC}"

echo ""
echo "=== Checking album art entries ==="
ART_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM ALBUM_ART;")
echo -e "Total album art entries: ${GREEN}$ART_COUNT${NC}"

echo ""
echo "=== Checking videos WITH album art assigned ==="
VIDEO_WITH_ART=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM DETAILS WHERE MIME LIKE 'video/%' AND ALBUM_ART IS NOT NULL AND ALBUM_ART != 0;")
echo -e "Videos with album art: ${GREEN}$VIDEO_WITH_ART${NC}"

echo ""
echo "=== Sample of videos without album art ==="
sqlite3 "$DB_FILE" "SELECT ID, PATH FROM DETAILS WHERE MIME LIKE 'video/%' AND (ALBUM_ART IS NULL OR ALBUM_ART = 0) LIMIT 5;" | \
    awk -F'|' '{printf "  ID: %-10s Path: %s\n", $1, $2}'

echo ""
echo "=== Sample of album art paths in database ==="
sqlite3 "$DB_FILE" "SELECT ID, PATH FROM ALBUM_ART LIMIT 10;" | \
    awk -F'|' '{printf "  ID: %-5s Path: %s\n", $1, $2}'

echo ""
echo "=== Checking art_cache directory ==="
ART_CACHE_DIR="$DB_DIR/art_cache"
if [ -d "$ART_CACHE_DIR" ]; then
    CACHE_COUNT=$(find "$ART_CACHE_DIR" -name "*.jpg" 2>/dev/null | wc -l)
    echo -e "Thumbnail files in cache: ${GREEN}$CACHE_COUNT${NC}"
    echo "Sample cache files:"
    find "$ART_CACHE_DIR" -name "*.jpg" -type f 2>/dev/null | head -5 | sed 's/^/  /'
else
    echo -e "${RED}Art cache directory not found: $ART_CACHE_DIR${NC}"
fi

echo ""
echo "=== Checking for ffmpegthumbnailer ==="
if command -v ffmpegthumbnailer >/dev/null 2>&1; then
    FFMPEG_VERSION=$(ffmpegthumbnailer -v 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} ffmpegthumbnailer found: $FFMPEG_VERSION"
else
    echo -e "${RED}✗ ffmpegthumbnailer NOT found in PATH${NC}"
    echo "  Install with: sudo apt-get install ffmpegthumbnailer"
fi

echo ""
echo "=== Detailed check: First video file ==="
FIRST_VIDEO=$(sqlite3 "$DB_FILE" "SELECT ID, PATH, ALBUM_ART FROM DETAILS WHERE MIME LIKE 'video/%' LIMIT 1;")
if [ -n "$FIRST_VIDEO" ]; then
    VIDEO_ID=$(echo "$FIRST_VIDEO" | cut -d'|' -f1)
    VIDEO_PATH=$(echo "$FIRST_VIDEO" | cut -d'|' -f2)
    VIDEO_ART=$(echo "$FIRST_VIDEO" | cut -d'|' -f3)

    echo "  Video ID: $VIDEO_ID"
    echo "  Video Path: $VIDEO_PATH"
    echo "  Album Art ID: ${VIDEO_ART:-<not set>}"

    # Check if video file exists
    if [ -f "$VIDEO_PATH" ]; then
        echo -e "  Video file exists: ${GREEN}✓${NC}"
    else
        echo -e "  Video file exists: ${RED}✗${NC}"
    fi

    # Check for expected thumbnail path
    EXPECTED_THUMB="$ART_CACHE_DIR${VIDEO_PATH%.*}.jpg"
    if [ -f "$EXPECTED_THUMB" ]; then
        echo -e "  Expected thumbnail exists: ${GREEN}✓${NC} ($EXPECTED_THUMB)"
        THUMB_SIZE=$(stat -f%z "$EXPECTED_THUMB" 2>/dev/null || stat -c%s "$EXPECTED_THUMB" 2>/dev/null)
        echo "  Thumbnail size: $THUMB_SIZE bytes"
    else
        echo -e "  Expected thumbnail exists: ${RED}✗${NC} ($EXPECTED_THUMB)"
    fi

    # Check if album art ID matches
    if [ -n "$VIDEO_ART" ] && [ "$VIDEO_ART" != "0" ]; then
        ART_PATH=$(sqlite3 "$DB_FILE" "SELECT PATH FROM ALBUM_ART WHERE ID = $VIDEO_ART;")
        echo "  Album art DB path: $ART_PATH"
        if [ -f "$ART_PATH" ]; then
            echo -e "  Album art file exists: ${GREEN}✓${NC}"
        else
            echo -e "  Album art file exists: ${RED}✗${NC}"
        fi
    fi
fi

echo ""
echo "=== Checking MiniDLNA log for errors ==="
LOG_FILE="/var/log/minidlna.log"
if [ -f "$LOG_FILE" ]; then
    echo "Recent thumbnail-related log entries:"
    grep -i "ffmpeg\|thumb\|album" "$LOG_FILE" 2>/dev/null | tail -10 | sed 's/^/  /' || echo "  No thumbnail-related entries found"
else
    echo -e "${YELLOW}Log file not found: $LOG_FILE${NC}"
fi

echo ""
echo "=== Recommendations ==="
if [ "$VIDEO_WITH_ART" -eq 0 ] && [ "$VIDEO_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ No videos have album art assigned.${NC}"
    echo ""
    echo "Try the following:"
    echo "  1. Force a database rescan: sudo minidlna -R"
    echo "  2. Check that ffmpegthumbnailer is installed and in PATH"
    echo "  3. Check file permissions on $ART_CACHE_DIR"
    echo "  4. Increase log level in /etc/minidlna.conf:"
    echo "       log_level=general,artwork,metadata=debug"
    echo "  5. Restart minidlna and check $LOG_FILE"
fi

echo ""
echo "=== Debug script complete ==="
