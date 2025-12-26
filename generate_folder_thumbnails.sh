#!/bin/bash
# Auto-generate folder thumbnails as collages of video thumbnails
# Supports hierarchical generation: leaf folders (seasons) + parent folders (series)

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
echo "This script generates hierarchical folder thumbnails:"
echo "  1. Leaf folders (e.g., Season 1, Season 2)"
echo "  2. Parent folders (e.g., Series name)"
echo ""

# Get list of all folders containing videos
echo "Step 1: Finding video folders..."

# Extract unique directories using bash (simpler than complex SQL)
FOLDERS=$(sqlite3 "$DB" "SELECT PATH FROM DETAILS WHERE MIME LIKE 'video/%';" | \
    while IFS= read -r filepath; do
        dirname "$filepath"
    done | sort -u)

if [ -z "$FOLDERS" ]; then
    echo "No video folders found in database."
    echo ""
    echo "Possible issues:"
    echo "  - Rescan not complete yet"
    echo "  - No videos indexed in database"
    echo "  - Database path incorrect: $DB"
    exit 0
fi

FOLDER_COUNT=$(echo "$FOLDERS" | wc -l)
echo "Found $FOLDER_COUNT folders with videos"
echo ""

# Function to create a collage from thumbnail paths
create_collage() {
    local OUTPUT_FILE="$1"
    local TEMP_DIR="$2"
    local ACTUAL_COUNT=$(ls "$TEMP_DIR"/thumb_*.jpg 2>/dev/null | wc -l)

    if [ "$ACTUAL_COUNT" -lt 2 ]; then
        return 1
    fi

    # Create collage based on number of thumbnails
    if [ "$ACTUAL_COUNT" -ge 4 ]; then
        # 2x2 grid
        convert \( "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" +append \) \
                \( "$TEMP_DIR/thumb_3.jpg" "$TEMP_DIR/thumb_4.jpg" +append \) \
                -append -resize 320x320 "$OUTPUT_FILE" 2>/dev/null
    elif [ "$ACTUAL_COUNT" -eq 3 ]; then
        # 2x2 grid with one duplicate
        convert \( "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" +append \) \
                \( "$TEMP_DIR/thumb_3.jpg" "$TEMP_DIR/thumb_1.jpg" +append \) \
                -append -resize 320x320 "$OUTPUT_FILE" 2>/dev/null
    else
        # 1x2 side-by-side
        convert "$TEMP_DIR/thumb_1.jpg" "$TEMP_DIR/thumb_2.jpg" \
                +append -resize 320x320 "$OUTPUT_FILE" 2>/dev/null
    fi

    return 0
}

echo "Step 2: Generating leaf folder thumbnails (seasons/direct video folders)..."
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

    # Get up to 4 video thumbnails from this folder (non-recursive)
    THUMBS=$(sqlite3 "$DB" "
      SELECT a.PATH
      FROM DETAILS d
      JOIN ALBUM_ART a ON d.ALBUM_ART = a.ID
      WHERE d.MIME LIKE 'video/%'
        AND d.PATH LIKE '$FOLDER/%'
        AND d.PATH NOT LIKE '$FOLDER/%/%'
        AND d.ALBUM_ART IS NOT NULL
      LIMIT 4;
    ")

    if [ -z "$THUMBS" ]; then
        ((SKIPPED++))
        continue
    fi

    THUMB_COUNT=$(echo "$THUMBS" | wc -l)

    if [ "$THUMB_COUNT" -lt 2 ]; then
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

    # Create collage
    if create_collage "$FOLDER_JPG" "$TEMP_DIR"; then
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
echo "Leaf folders: $CREATED created, $SKIPPED skipped"
echo ""

# Step 3: Generate parent folder thumbnails
echo "Step 3: Generating parent folder thumbnails (series/collections)..."

# Find all parent folders (one level up from leaf folders)
PARENT_FOLDERS=$(echo "$FOLDERS" | while IFS= read -r folder; do
    dirname "$folder"
done | sort -u)

PARENT_PROCESSED=0
PARENT_SKIPPED=0
PARENT_CREATED=0

while IFS= read -r PARENT_FOLDER; do
    [ -z "$PARENT_FOLDER" ] && continue

    PARENT_JPG="$PARENT_FOLDER/Folder.jpg"

    # Skip if Folder.jpg already exists
    if [ -f "$PARENT_JPG" ]; then
        ((PARENT_SKIPPED++))
        continue
    fi

    # Find child folders within this parent
    CHILD_FOLDERS=$(echo "$FOLDERS" | grep "^$PARENT_FOLDER/[^/]*$" || true)

    if [ -z "$CHILD_FOLDERS" ]; then
        # No child folders, skip (this is likely a top-level category folder)
        ((PARENT_SKIPPED++))
        continue
    fi

    CHILD_COUNT=$(echo "$CHILD_FOLDERS" | wc -l)

    # Skip if only 1 child folder (no point in parent thumbnail)
    if [ "$CHILD_COUNT" -lt 2 ]; then
        ((PARENT_SKIPPED++))
        continue
    fi

    # Get thumbnails distributed across child folders
    # Strategy: Get 1-2 thumbnails from each child folder up to 4 total
    TEMP_DIR=$(mktemp -d)
    INDEX=1
    THUMBS_PER_CHILD=$((4 / CHILD_COUNT))
    [ "$THUMBS_PER_CHILD" -lt 1 ] && THUMBS_PER_CHILD=1

    echo "  📂 Processing: $PARENT_FOLDER ($CHILD_COUNT child folders)"

    while IFS= read -r CHILD_FOLDER; do
        [ -z "$CHILD_FOLDER" ] && continue
        [ "$INDEX" -gt 4 ] && break

        # Get thumbnails from this child folder
        CHILD_THUMBS=$(sqlite3 "$DB" "
          SELECT a.PATH
          FROM DETAILS d
          JOIN ALBUM_ART a ON d.ALBUM_ART = a.ID
          WHERE d.MIME LIKE 'video/%'
            AND d.PATH LIKE '$CHILD_FOLDER/%'
            AND d.PATH NOT LIKE '$CHILD_FOLDER/%/%'
            AND d.ALBUM_ART IS NOT NULL
          LIMIT $THUMBS_PER_CHILD;
        ")

        while IFS= read -r THUMB_PATH; do
            [ -z "$THUMB_PATH" ] && continue
            [ "$INDEX" -gt 4 ] && break
            if [ -f "$THUMB_PATH" ]; then
                cp "$THUMB_PATH" "$TEMP_DIR/thumb_$INDEX.jpg"
                ((INDEX++))
            fi
        done <<< "$CHILD_THUMBS"

    done <<< "$CHILD_FOLDERS"

    # Create collage from collected thumbnails
    if create_collage "$PARENT_JPG" "$TEMP_DIR"; then
        echo "     ✅ Created: Folder.jpg (from $CHILD_COUNT child folders)"
        ((PARENT_CREATED++))
    else
        echo "     ⚠️  Not enough thumbnails from child folders"
        ((PARENT_SKIPPED++))
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    ((PARENT_PROCESSED++))

done <<< "$PARENT_FOLDERS"

echo ""
echo "Parent folders: $PARENT_CREATED created, $PARENT_SKIPPED skipped"
echo ""

# Summary
TOTAL_CREATED=$((CREATED + PARENT_CREATED))
TOTAL_SKIPPED=$((SKIPPED + PARENT_SKIPPED))

echo "=== Summary ==="
echo "Leaf folder thumbnails: $CREATED created"
echo "Parent folder thumbnails: $PARENT_CREATED created"
echo "Total created: $TOTAL_CREATED"
echo "Total skipped: $TOTAL_SKIPPED"
echo ""

if [ "$TOTAL_CREATED" -gt 0 ]; then
    echo "✅ Folder thumbnails created!"
    echo ""
    echo "Next steps:"
    echo "1. Force MiniDLNA to rescan: sudo minidlnad -R"
    echo "2. Restart service: sudo systemctl restart minidlna"
    echo "3. Refresh your DLNA client"
fi
