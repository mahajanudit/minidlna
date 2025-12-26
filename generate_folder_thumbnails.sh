#!/bin/bash
# Auto-generate folder thumbnails as collages of video thumbnails

set -e

DB="/var/cache/minidlna/files.db"
CACHE_DIR="/var/cache/minidlna/art_cache"

# Check dependencies
if ! command -v convert &> /dev/null; then
    echo "Error: ImageMagick 'convert' not found"
    echo "Install with: sudo apt-get install imagemagick"
    exit 1
fi

echo "=== MiniDLNA Folder Thumbnail Generator ==="
echo ""
echo "This script generates folder thumbnails as 2x2 collages"
echo "of video thumbnails from each folder."
echo ""

# Get list of all folders containing videos
echo "Step 1: Finding video folders..."
FOLDERS=$(sqlite3 "$DB" "
  SELECT DISTINCT SUBSTR(PATH, 1, LENGTH(PATH) - LENGTH(REPLACE(REPLACE(REPLACE(PATH, '/', '|'), '|' || REPLACE(PATH, '/', '|') || '|', ''), '|', '/'))) as folder_path
  FROM DETAILS
  WHERE MIME LIKE 'video/%'
  ORDER BY folder_path;
")

if [ -z "$FOLDERS" ]; then
    echo "No video folders found in database."
    exit 0
fi

FOLDER_COUNT=$(echo "$FOLDERS" | wc -l)
echo "Found $FOLDER_COUNT folders with videos"
echo ""

PROCESSED=0
SKIPPED=0
CREATED=0

while IFS= read -r FOLDER; do
    [ -z "$FOLDER" ] && continue

    FOLDER_JPG="$FOLDER/Folder.jpg"

    # Skip if Folder.jpg already exists
    if [ -f "$FOLDER_JPG" ]; then
        ((SKIPPED++))
        continue
    fi

    # Get up to 4 video thumbnails from this folder
    THUMBS=$(sqlite3 "$DB" "
      SELECT a.PATH
      FROM DETAILS d
      JOIN ALBUM_ART a ON d.ALBUM_ART = a.ID
      WHERE d.MIME LIKE 'video/%'
        AND d.PATH LIKE '$FOLDER/%'
        AND d.ALBUM_ART IS NOT NULL
      LIMIT 4;
    ")

    if [ -z "$THUMBS" ]; then
        echo "  ⏭️  Skipping $FOLDER (no thumbnails generated yet)"
        ((SKIPPED++))
        continue
    fi

    THUMB_COUNT=$(echo "$THUMBS" | wc -l)

    if [ "$THUMB_COUNT" -lt 2 ]; then
        echo "  ⏭️  Skipping $FOLDER (only $THUMB_COUNT thumbnail)"
        ((SKIPPED++))
        continue
    fi

    echo "  📁 Processing: $FOLDER ($THUMB_COUNT thumbnails)"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)

    # Copy thumbnails to temp directory
    INDEX=1
    while IFS= read -r THUMB_PATH; do
        [ -z "$THUMB_PATH" ] && continue
        if [ -f "$THUMB_PATH" ]; then
            cp "$THUMB_PATH" "$TEMP_DIR/thumb_$INDEX.jpg"
            ((INDEX++))
        fi
    done <<< "$THUMBS"

    # Count actual thumbnails copied
    ACTUAL_COUNT=$(ls "$TEMP_DIR"/thumb_*.jpg 2>/dev/null | wc -l)

    if [ "$ACTUAL_COUNT" -lt 2 ]; then
        echo "     ⚠️  Not enough valid thumbnails ($ACTUAL_COUNT)"
        rm -rf "$TEMP_DIR"
        ((SKIPPED++))
        continue
    fi

    # Create collage based on number of thumbnails
    if [ "$ACTUAL_COUNT" -ge 4 ]; then
        # 2x2 grid
        convert \( "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" +append \) \
                \( "$TEMP_DIR/thumb_3.jpg" "$TEMP_DIR/thumb_4.jpg" +append \) \
                -append -resize 320x320 "$FOLDER_JPG" 2>/dev/null
    elif [ "$ACTUAL_COUNT" -eq 3 ]; then
        # 2x2 grid with one duplicate
        convert \( "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" +append \) \
                \( "$TEMP_DIR/thumb_3.jpg" "$TEMP_DIR/thumb_1.jpg" +append \) \
                -append -resize 320x320 "$FOLDER_JPG" 2>/dev/null
    else
        # 1x2 side-by-side
        convert "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" \
                +append -resize 320x320 "$FOLDER_JPG" 2>/dev/null
    fi

    if [ -f "$FOLDER_JPG" ]; then
        # Add a folder icon overlay (optional - comment out if you don't want it)
        # This adds a semi-transparent folder icon in the corner
        # convert "$FOLDER_JPG" \
        #   \( -size 80x80 xc:none -fill 'rgba(0,0,0,0.6)' \
        #      -draw 'roundrectangle 10,10 70,70 5,5' \
        #      -fill white -pointsize 48 -gravity center -annotate +0+0 '📁' \) \
        #   -gravity northwest -geometry +10+10 -composite "$FOLDER_JPG"

        echo "     ✅ Created: Folder.jpg"
        ((CREATED++))
    else
        echo "     ❌ Failed to create collage"
        ((SKIPPED++))
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    ((PROCESSED++))

done <<< "$FOLDERS"

echo ""
echo "=== Summary ==="
echo "Total folders: $FOLDER_COUNT"
echo "Processed: $PROCESSED"
echo "Created: $CREATED"
echo "Skipped: $SKIPPED"
echo ""

if [ "$CREATED" -gt 0 ]; then
    echo "✅ Folder thumbnails created!"
    echo ""
    echo "Next steps:"
    echo "1. Force MiniDLNA to rescan: sudo minidlnad -R"
    echo "2. Restart service: sudo systemctl restart minidlna"
    echo "3. Refresh your DLNA client"
fi
