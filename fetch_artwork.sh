#!/bin/bash
# Fetch series/movie artwork from TheMovieDB (TMDB)
# Downloads official posters and saves as Folder.jpg

set -e

# TMDB API Configuration
TMDB_API_KEY="f5687aa66f6db8631c4085add136a59d"
TMDB_BASE_URL="https://api.themoviedb.org/3"
TMDB_IMAGE_BASE="https://image.tmdb.org/t/p/w500"

# Default media root (change this to your media location)
DEFAULT_MEDIA_ROOT="/srv/dev-disk-by-uuid-ba86fbb4-886a-464c-a325-61453022d206"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
DOWNLOADED=0
SKIPPED=0
NOT_FOUND=0
ERRORS=0

# Options
DRY_RUN=false
FORCE=false
VERBOSE=false
FETCH_SEASONS=false

usage() {
    echo "Usage: $0 [OPTIONS] [MEDIA_ROOT]"
    echo ""
    echo "Fetch series/movie artwork from TMDB and save as Folder.jpg"
    echo ""
    echo "Arguments:"
    echo "  MEDIA_ROOT    Root directory containing media folders (default: $DEFAULT_MEDIA_ROOT)"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run     Show what would be done without downloading"
    echo "  -f, --force       Overwrite existing Folder.jpg files"
    echo "  -s, --seasons     Also fetch season-specific artwork"
    echo "  -v, --verbose     Show detailed output"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Use default media root"
    echo "  $0 /path/to/media            # Specify media root"
    echo "  $0 --dry-run                 # Preview without downloading"
    echo "  $0 --force --seasons         # Overwrite existing + fetch season art"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -s|--seasons)
            FETCH_SEASONS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            MEDIA_ROOT="$1"
            shift
            ;;
    esac
done

MEDIA_ROOT="${MEDIA_ROOT:-$DEFAULT_MEDIA_ROOT}"

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        echo "Install with: sudo apt-get install ${missing[*]}"
        exit 1
    fi
}

# Clean title for search (remove year, special chars, etc.)
clean_title() {
    local title="$1"

    # Remove year in parentheses: "Movie (2020)" -> "Movie"
    title=$(echo "$title" | sed 's/ *([0-9]\{4\})$//')

    # Remove year at end: "Movie 2020" -> "Movie" (only if 4 digits at end)
    title=$(echo "$title" | sed 's/ [0-9]\{4\}$//')

    # Remove common suffixes
    title=$(echo "$title" | sed 's/ - Complete Series$//i')
    title=$(echo "$title" | sed 's/ Complete$//i')
    title=$(echo "$title" | sed 's/ Collection$//i')

    # Trim whitespace
    title=$(echo "$title" | xargs)

    echo "$title"
}

# URL encode a string
urlencode() {
    local string="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$string'''))"
}

# Search TMDB for TV show
search_tv() {
    local query="$1"
    local encoded_query=$(urlencode "$query")

    local response=$(curl -s "${TMDB_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&query=${encoded_query}")

    # Get first result's poster path
    local poster_path=$(echo "$response" | jq -r '.results[0].poster_path // empty')
    local name=$(echo "$response" | jq -r '.results[0].name // empty')
    local id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$poster_path" ] && [ "$poster_path" != "null" ]; then
        echo "tv|$id|$name|$poster_path"
    fi
}

# Search TMDB for movie
search_movie() {
    local query="$1"
    local encoded_query=$(urlencode "$query")

    local response=$(curl -s "${TMDB_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&query=${encoded_query}")

    # Get first result's poster path
    local poster_path=$(echo "$response" | jq -r '.results[0].poster_path // empty')
    local name=$(echo "$response" | jq -r '.results[0].title // empty')
    local id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$poster_path" ] && [ "$poster_path" != "null" ]; then
        echo "movie|$id|$name|$poster_path"
    fi
}

# Search TMDB for collection
search_collection() {
    local query="$1"
    local encoded_query=$(urlencode "$query")

    local response=$(curl -s "${TMDB_BASE_URL}/search/collection?api_key=${TMDB_API_KEY}&query=${encoded_query}")

    # Get first result's poster path
    local poster_path=$(echo "$response" | jq -r '.results[0].poster_path // empty')
    local name=$(echo "$response" | jq -r '.results[0].name // empty')
    local id=$(echo "$response" | jq -r '.results[0].id // empty')

    if [ -n "$poster_path" ] && [ "$poster_path" != "null" ]; then
        echo "collection|$id|$name|$poster_path"
    fi
}

# Get season poster for a TV show
get_season_poster() {
    local tv_id="$1"
    local season_num="$2"

    local response=$(curl -s "${TMDB_BASE_URL}/tv/${tv_id}/season/${season_num}?api_key=${TMDB_API_KEY}")

    local poster_path=$(echo "$response" | jq -r '.poster_path // empty')

    if [ -n "$poster_path" ] && [ "$poster_path" != "null" ]; then
        echo "$poster_path"
    fi
}

# Download image to destination
download_image() {
    local poster_path="$1"
    local destination="$2"

    local url="${TMDB_IMAGE_BASE}${poster_path}"

    if [ "$DRY_RUN" = true ]; then
        echo -e "     ${BLUE}Would download:${NC} $url"
        return 0
    fi

    if curl -s -o "$destination" "$url"; then
        return 0
    else
        return 1
    fi
}

# Process a single folder
process_folder() {
    local folder_path="$1"
    local folder_name=$(basename "$folder_path")
    local folder_jpg="$folder_path/Folder.jpg"

    # Skip if Folder.jpg exists and not forcing
    if [ -f "$folder_jpg" ] && [ "$FORCE" = false ]; then
        if [ "$VERBOSE" = true ]; then
            echo -e "  ${YELLOW}⏭ Skipping:${NC} $folder_name (Folder.jpg exists)"
        fi
        ((SKIPPED++))
        return
    fi

    local clean_name=$(clean_title "$folder_name")

    echo -e "  ${BLUE}🔍 Searching:${NC} $folder_name"
    if [ "$VERBOSE" = true ] && [ "$clean_name" != "$folder_name" ]; then
        echo -e "     ${BLUE}Clean title:${NC} $clean_name"
    fi

    # Try TV show first, then movie, then collection
    local result=$(search_tv "$clean_name")

    if [ -z "$result" ]; then
        result=$(search_movie "$clean_name")
    fi

    if [ -z "$result" ]; then
        result=$(search_collection "$clean_name")
    fi

    if [ -z "$result" ]; then
        echo -e "     ${RED}❌ Not found on TMDB${NC}"
        ((NOT_FOUND++))
        return
    fi

    # Parse result
    local type=$(echo "$result" | cut -d'|' -f1)
    local id=$(echo "$result" | cut -d'|' -f2)
    local matched_name=$(echo "$result" | cut -d'|' -f3)
    local poster_path=$(echo "$result" | cut -d'|' -f4)

    echo -e "     ${GREEN}✓ Found:${NC} $matched_name (${type})"

    # Download poster
    if download_image "$poster_path" "$folder_jpg"; then
        if [ "$DRY_RUN" = false ]; then
            echo -e "     ${GREEN}✅ Saved:${NC} Folder.jpg"
        fi
        ((DOWNLOADED++))
    else
        echo -e "     ${RED}❌ Download failed${NC}"
        ((ERRORS++))
        return
    fi

    # Process seasons if enabled and it's a TV show
    if [ "$FETCH_SEASONS" = true ] && [ "$type" = "tv" ]; then
        process_seasons "$folder_path" "$id"
    fi
}

# Process season folders for a TV show
process_seasons() {
    local series_path="$1"
    local tv_id="$2"

    # Find season folders
    for season_dir in "$series_path"/Season\ *; do
        [ -d "$season_dir" ] || continue

        local season_name=$(basename "$season_dir")
        local season_jpg="$season_dir/Folder.jpg"

        # Skip if exists and not forcing
        if [ -f "$season_jpg" ] && [ "$FORCE" = false ]; then
            if [ "$VERBOSE" = true ]; then
                echo -e "     ${YELLOW}⏭ Skipping:${NC} $season_name (exists)"
            fi
            continue
        fi

        # Extract season number
        local season_num=$(echo "$season_name" | grep -oE '[0-9]+')

        if [ -z "$season_num" ]; then
            continue
        fi

        echo -e "     ${BLUE}🔍 Fetching:${NC} $season_name poster"

        local season_poster=$(get_season_poster "$tv_id" "$season_num")

        if [ -n "$season_poster" ]; then
            if download_image "$season_poster" "$season_jpg"; then
                if [ "$DRY_RUN" = false ]; then
                    echo -e "        ${GREEN}✅ Saved:${NC} $season_name/Folder.jpg"
                fi
                ((DOWNLOADED++))
            fi
        else
            if [ "$VERBOSE" = true ]; then
                echo -e "        ${YELLOW}⚠ No season poster available${NC}"
            fi
        fi
    done
}

# Main execution
main() {
    echo "=== TMDB Artwork Fetcher ==="
    echo ""

    check_dependencies

    if [ ! -d "$MEDIA_ROOT" ]; then
        echo -e "${RED}Error: Media root not found: $MEDIA_ROOT${NC}"
        exit 1
    fi

    echo "Media root: $MEDIA_ROOT"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN MODE - No files will be downloaded${NC}"
    fi
    if [ "$FORCE" = true ]; then
        echo -e "${YELLOW}FORCE MODE - Existing Folder.jpg will be overwritten${NC}"
    fi
    if [ "$FETCH_SEASONS" = true ]; then
        echo -e "${BLUE}Season artwork fetching enabled${NC}"
    fi
    echo ""

    # Find top-level category folders
    for category_dir in "$MEDIA_ROOT"/*/; do
        [ -d "$category_dir" ] || continue

        local category_name=$(basename "$category_dir")

        # Skip hidden folders and common non-media folders
        case "$category_name" in
            .*|lost+found|"@"*|"#"*|'$'*)
                continue
                ;;
        esac

        echo -e "${GREEN}📁 Category: $category_name${NC}"

        # Process each series/movie folder within the category
        for series_dir in "$category_dir"/*/; do
            [ -d "$series_dir" ] || continue

            local series_name=$(basename "$series_dir")

            # Skip hidden folders
            [[ "$series_name" == .* ]] && continue

            process_folder "$series_dir"

            # Rate limiting - be nice to TMDB API
            sleep 0.25
        done

        echo ""
    done

    # Summary
    echo "=== Summary ==="
    echo -e "Downloaded: ${GREEN}$DOWNLOADED${NC}"
    echo -e "Skipped:    ${YELLOW}$SKIPPED${NC}"
    echo -e "Not found:  ${RED}$NOT_FOUND${NC}"
    echo -e "Errors:     ${RED}$ERRORS${NC}"
    echo ""

    if [ "$DOWNLOADED" -gt 0 ] && [ "$DRY_RUN" = false ]; then
        echo "✅ Artwork download complete!"
        echo ""
        echo "Next steps:"
        echo "1. Force MiniDLNA to rescan: sudo minidlnad -R"
        echo "2. Restart service: sudo systemctl restart minidlna"
    fi
}

main
