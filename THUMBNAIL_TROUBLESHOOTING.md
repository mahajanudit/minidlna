# MiniDLNA Video Thumbnail Troubleshooting Guide

## Problem
Video thumbnails generated with ffmpegthumbnailer are not displaying on DLNA clients.

## Root Cause Analysis

Your implementation in `albumart.c` (commit ba13d34) correctly:
1. ✅ Calls `ffmpegthumbnailer` to generate thumbnails for video files
2. ✅ Stores thumbnails in the art_cache directory
3. ✅ Inserts thumbnail paths into the `ALBUM_ART` table
4. ✅ Returns the album art ID from `find_album_art()`

However, there were **three bugs** that have now been fixed:

### Issue 1: Album Art Not Linked to Videos in Database

The `find_album_art()` function returns an `album_art_id`, but the **DETAILS table must be updated** to link videos to their thumbnails. This happens during media scanning in `metadata.c`.

**Check if videos have ALBUM_ART column populated:**
```bash
sqlite3 /var/cache/minidlna/files.db \
  "SELECT COUNT(*) FROM DETAILS WHERE MIME LIKE 'video/%' AND ALBUM_ART IS NOT NULL;"
```

**If the count is 0**, you need to force a rescan after adding the ffmpegthumbnailer code:
```bash
sudo systemctl stop minidlna
sudo minidlna -R  # Force database rebuild
sudo systemctl start minidlna
```

### Issue 2: DLNA Client Compatibility

Different DLNA clients look for thumbnails in different ways:

| XML Element | Used By | When Added |
|-------------|---------|-----------|
| `<res>` with JPEG_TN profile | Most video players | Only when `FILTER_RES` flag is set |
| `<upnp:albumArtURI>` | Audio apps, some video players | Only when `FILTER_UPNP_ALBUMARTURI` flag is set |

**The problem**: Your DLNA client might not request `FILTER_RES`, so it never gets the thumbnail URL.

**The fix**: Changed `upnpsoap.c` so that both `<res>` and `<upnp:albumArtURI>` can be added to the same video item (previously mutually exclusive with `else if`).

Before:
```c
if( *mime == 'v' && (passed_args->filter & FILTER_RES) ) {
    // Add <res> element
} else if( passed_args->filter & FILTER_UPNP_ALBUMARTURI ) {
    // Add <upnp:albumArtURI> element
}
```

After:
```c
if( *mime == 'v' && (passed_args->filter & FILTER_RES) ) {
    // Add <res> element
}
if( passed_args->filter & FILTER_UPNP_ALBUMARTURI ) {
    // Add <upnp:albumArtURI> element (now for BOTH video and audio)
}
```

### Issue 3: Buffer Overflow Bug in art_cache_exists()

**The bug**: Original code assumed all video files have 3-character extensions:
```c
strcpy(strchr(*cache_file, '\0')-4, ".jpg");  // WRONG - assumes .mp4, .avi, etc.
```

This would fail or crash with:
- 4-character extensions: `.webm`, `.flac`
- 2-character extensions: `.ts`, `.qt`
- Files without extensions

**The fix**: Use `strrchr` to find the last dot safely:
```c
ext = strrchr(*cache_file, '.');
if( ext )
    strcpy(ext, ".jpg");
else
    strcat(*cache_file, ".jpg");
```

## Step-by-Step Debugging Process

### 1. Run the Debug Script

```bash
sudo ./debug_thumbnails.sh
```

This will check:
- Database integrity
- Whether videos are indexed
- Whether thumbnails exist in cache
- Whether `ffmpegthumbnailer` is installed

### 2. Verify ffmpegthumbnailer Works

Test thumbnail generation manually:
```bash
# Find a video file
VIDEO=$(sqlite3 /var/cache/minidlna/files.db \
  "SELECT PATH FROM DETAILS WHERE MIME LIKE 'video/%' LIMIT 1;")

# Generate thumbnail manually
ffmpegthumbnailer -i "$VIDEO" -o /tmp/test_thumb.jpg -s 320 -q 8 -f

# Check if it was created
ls -lh /tmp/test_thumb.jpg
```

If this fails, the issue is with ffmpegthumbnailer, not MiniDLNA.

### 3. Check Database Links

```bash
DB="/var/cache/minidlna/files.db"

# Show a video with its album art
sqlite3 "$DB" "
  SELECT
    d.ID as DetailID,
    d.PATH as VideoPath,
    d.ALBUM_ART as AlbumArtID,
    a.PATH as ThumbnailPath
  FROM DETAILS d
  LEFT JOIN ALBUM_ART a ON d.ALBUM_ART = a.ID
  WHERE d.MIME LIKE 'video/%'
  LIMIT 5;
" | column -t -s '|'
```

Expected output:
```
DetailID  VideoPath              AlbumArtID  ThumbnailPath
123       /media/video.mp4       45          /var/cache/minidlna/art_cache/media/video.jpg
```

If `AlbumArtID` is NULL or `ThumbnailPath` is NULL, the database linkage is broken.

### 4. Enable Debug Logging

Edit `/etc/minidlna.conf`:
```ini
log_level=general,artwork,metadata,http=debug
```

Restart MiniDLNA and watch the log:
```bash
sudo systemctl restart minidlna
tail -f /var/log/minidlna.log | grep -i "thumb\|album\|ffmpeg"
```

Look for:
- "ffmpegthumbnailer not found in PATH" → Install ffmpegthumbnailer
- "fork() failed for ffmpegthumbnailer" → Permission issue
- "Serving album art ID: X [path]" → Successful serving (check your client is requesting it)

### 5. Test with curl

If thumbnails appear in the database, test the HTTP endpoint:
```bash
# Get album art ID for a video
ALBUM_ART_ID=$(sqlite3 /var/cache/minidlna/files.db \
  "SELECT ALBUM_ART FROM DETAILS WHERE MIME LIKE 'video/%' AND ALBUM_ART IS NOT NULL LIMIT 1;")

DETAIL_ID=$(sqlite3 /var/cache/minidlna/files.db \
  "SELECT ID FROM DETAILS WHERE MIME LIKE 'video/%' AND ALBUM_ART IS NOT NULL LIMIT 1;")

# Test the AlbumArt endpoint
curl -v "http://localhost:8200/AlbumArt/$ALBUM_ART_ID-$DETAIL_ID.jpg" -o /tmp/thumbnail.jpg

# Check if valid JPEG
file /tmp/thumbnail.jpg
```

Expected: "JPEG image data"

### 6. Inspect UPnP XML Response

Use a UPnP debugging tool or packet capture to see what XML your MiniDLNA server sends:

```bash
# Install wireshark/tshark
sudo apt-get install tshark

# Capture UPnP traffic
sudo tshark -i any -f "tcp port 8200" -w /tmp/upnp_capture.pcap
# (trigger a browse from your DLNA client)
# Ctrl+C to stop

# Examine HTTP responses
tshark -r /tmp/upnp_capture.pcap -Y "http.response" -T fields -e http.file_data | \
  grep -i "albumArt\|JPEG_TN"
```

Look for:
```xml
<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN">
  http://192.168.1.100:8200/AlbumArt/45-123.jpg
</res>
```
or
```xml
<upnp:albumArtURI>http://192.168.1.100:8200/AlbumArt/45-123.jpg</upnp:albumArtURI>
```

## Build and Deploy

After making the change to `upnpsoap.c`:

```bash
# Configure
./autogen.sh
./configure

# Build
make -j$(nproc)

# Install
sudo systemctl stop minidlna
sudo make install
sudo systemctl start minidlna
```

Or if you're testing locally:
```bash
# Run in foreground with debug logging
./minidlna -f /etc/minidlna.conf -d
```

## Common Mistakes

### 1. Forgot to Rescan After Adding Code
**Symptom**: Thumbnails exist in cache, but videos have NULL ALBUM_ART in database
**Fix**: Run `sudo minidlna -R`

### 2. ffmpegthumbnailer Not Installed
**Symptom**: Log shows "ffmpegthumbnailer not found in PATH"
**Fix**: `sudo apt-get install ffmpegthumbnailer`

### 3. Permission Issues
**Symptom**: Thumbnails not created despite ffmpegthumbnailer being installed
**Fix**: Check `art_cache` directory permissions:
```bash
sudo chown -R minidlna:minidlna /var/cache/minidlna/art_cache
sudo chmod 755 /var/cache/minidlna/art_cache
```

### 4. Client Doesn't Support Thumbnails
**Symptom**: Everything works in debug, but client still doesn't show thumbnails
**Fix**: Test with a different DLNA client (VLC, Kodi, etc.) to verify server-side works

### 5. Wrong URL Format
**Symptom**: Client requests thumbnails but gets 404 errors
**Fix**: Check the log for "ALBUM_ART ID XXX not found" - indicates mismatch between XML URL and database

## Expected Behavior

When working correctly:

1. **During scan**: MiniDLNA calls `ffmpegthumbnailer` for each video
2. **Thumbnail created**: `/var/cache/minidlna/art_cache/path/to/video.jpg`
3. **Database updated**: `ALBUM_ART` table gets new entry, `DETAILS.ALBUM_ART` points to it
4. **Client browses**: MiniDLNA includes `<res>` and/or `<upnp:albumArtURI>` in XML
5. **Client requests thumbnail**: HTTP GET to `/AlbumArt/{id}-{detailid}.jpg`
6. **MiniDLNA serves**: Reads from cache and returns JPEG

## Alternative: Check if Problem is Client-Side

Create a minimal test to verify the HTTP endpoint works:

```bash
# Manually insert a known thumbnail into the database
THUMB_PATH="/tmp/test_thumbnail.jpg"
ffmpegthumbnailer -i "/path/to/video.mp4" -o "$THUMB_PATH" -s 320

# Copy to art_cache
sudo cp "$THUMB_PATH" "/var/cache/minidlna/art_cache/test.jpg"

# Insert into database
sqlite3 /var/cache/minidlna/files.db <<EOF
INSERT INTO ALBUM_ART (PATH) VALUES ('/var/cache/minidlna/art_cache/test.jpg');
UPDATE DETAILS SET ALBUM_ART = last_insert_rowid()
  WHERE ID = (SELECT ID FROM DETAILS WHERE MIME LIKE 'video/%' LIMIT 1);
EOF

# Get the IDs
ALBUM_ART_ID=$(sqlite3 /var/cache/minidlna/files.db \
  "SELECT ALBUM_ART FROM DETAILS WHERE MIME LIKE 'video/%' LIMIT 1")
DETAIL_ID=$(sqlite3 /var/cache/minidlna/files.db \
  "SELECT ID FROM DETAILS WHERE MIME LIKE 'video/%' LIMIT 1")

# Test with curl
curl "http://localhost:8200/AlbumArt/$ALBUM_ART_ID-$DETAIL_ID.jpg" -o /tmp/served_thumb.jpg
```

If this works but your automatic generation doesn't, the issue is in the scanning/generation phase.

## Files Changed

1. **albumart.c** (commit ba13d34)
   - Added `generate_ffmpeg_thumb()` function
   - Added video thumbnail generation to `find_album_art()`

2. **upnpsoap.c** (new change)
   - Modified album art XML generation to add `<upnp:albumArtURI>` for videos
   - Ensures broader DLNA client compatibility

## Next Steps

1. Run `./debug_thumbnails.sh` to identify the specific issue
2. Follow the debugging steps above based on what the script reports
3. Rebuild and reinstall MiniDLNA with the updated `upnpsoap.c`
4. Force a rescan: `sudo minidlna -R`
5. Test with your DLNA client

If you still have issues, share the output of:
- `./debug_thumbnails.sh`
- Relevant log entries from `/var/log/minidlna.log`
- What DLNA client you're using
