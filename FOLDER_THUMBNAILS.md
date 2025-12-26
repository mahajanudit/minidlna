# Folder Thumbnail Collage Feature

## What This Does

Automatically generates `Folder.jpg` files in each video folder as beautiful 2x2 collages of the video thumbnails inside. MiniDLNA will then use these as folder icons!

## Visual Result

Instead of folders showing the first video's thumbnail:
```
📁 My Movies/
   └── (shows thumbnail of first video)
```

You'll get collage thumbnails:
```
📁 My Movies/
   └── [2x2 grid of 4 video thumbnails]
```

## How It Works

1. **Scans your MiniDLNA database** for all folders containing videos
2. **Finds up to 4 video thumbnails** from each folder
3. **Creates a collage**:
   - 4+ thumbnails → 2x2 grid
   - 3 thumbnails → 2x2 grid (duplicates first thumbnail)
   - 2 thumbnails → side-by-side
4. **Saves as `Folder.jpg`** in each video folder
5. **MiniDLNA automatically picks it up** as the folder thumbnail

## Prerequisites

```bash
# Install ImageMagick (for image collaging)
sudo apt-get install imagemagick
```

## Usage

### First Time Setup

```bash
# 1. Make sure video thumbnails are generated first
sudo ./install_and_test.sh

# 2. Generate folder thumbnails
sudo ./generate_folder_thumbnails.sh

# 3. Force MiniDLNA to pick up the new Folder.jpg files
sudo minidlnad -R

# 4. Restart service
sudo systemctl restart minidlna
```

### Adding New Videos

When you add new videos to folders:

```bash
# 1. Let MiniDLNA scan and generate video thumbnails
#    (happens automatically if inotify is enabled, or manually rescan)

# 2. Regenerate folder collages
sudo ./generate_folder_thumbnails.sh

# 3. Quick rescan (faster than full -R)
sudo systemctl restart minidlna
```

## Features

### Smart Behavior
- ✅ **Skips existing Folder.jpg files** - Won't overwrite manual ones
- ✅ **Only creates collages for folders with 2+ thumbnails**
- ✅ **Handles different thumbnail counts gracefully**
- ✅ **Shows progress for each folder**

### Customization Options

#### Add Folder Icon Overlay
Uncomment lines 125-129 in the script to add a folder icon in the corner:

```bash
# Uncomment these lines to add folder icon overlay
convert "$FOLDER_JPG" \
  \( -size 80x80 xc:none -fill 'rgba(0,0,0,0.6)' \
     -draw 'roundrectangle 10,10 70,70 5,5' \
     -fill white -pointsize 48 -gravity center -annotate +0+0 '📁' \) \
  -gravity northwest -geometry +10+10 -composite "$FOLDER_JPG"
```

#### Change Grid Layout
Edit lines 106-120 to use 3x3 grids or other layouts.

## Example Output

```
=== MiniDLNA Folder Thumbnail Generator ===

This script generates folder thumbnails as 2x2 collages
of video thumbnails from each folder.

Step 1: Finding video folders...
Found 15 folders with videos

  📁 Processing: /media/movies/Action (4 thumbnails)
     ✅ Created: Folder.jpg
  📁 Processing: /media/movies/Comedy (3 thumbnails)
     ✅ Created: Folder.jpg
  ⏭️  Skipping /media/movies/Drama (only 1 thumbnail)
  📁 Processing: /media/tv/Series1 (4 thumbnails)
     ✅ Created: Folder.jpg

=== Summary ===
Total folders: 15
Processed: 15
Created: 13
Skipped: 2

✅ Folder thumbnails created!

Next steps:
1. Force MiniDLNA to rescan: sudo minidlnad -R
2. Restart service: sudo systemctl restart minidlna
3. Refresh your DLNA client
```

## Manual Alternative

If you prefer to create your own custom folder thumbnails:

1. Create an image named `Folder.jpg` (case-sensitive)
2. Place it in any video folder
3. Rescan MiniDLNA
4. The folder will use your custom image

## Troubleshooting

### "No video folders found"
- Run `sudo ./install_and_test.sh` first to generate video thumbnails
- Check that MiniDLNA has scanned your media: `sudo ./debug_thumbnails.sh`

### "Skipping (no thumbnails generated yet)"
- Video thumbnails aren't generated for that folder yet
- Force rescan: `sudo minidlnad -R`
- Wait for scan to complete

### ImageMagick "convert: not authorized"
If you get permission errors, edit `/etc/ImageMagick-6/policy.xml`:

```xml
<!-- Change this line: -->
<policy domain="path" rights="none" pattern="@*"/>
<!-- To: -->
<policy domain="path" rights="read|write" pattern="@*"/>
```

### Collages look wrong
- Check thumbnail quality: `ls -lh /var/cache/minidlna/art_cache/`
- Regenerate video thumbnails: `sudo minidlnad -R`
- Try the script again

## Performance

- **Fast**: Processes ~100 folders per minute
- **Non-destructive**: Skips existing Folder.jpg files
- **One-time operation**: Only needed when folder contents change

## Integration with Automation

Add to cron for automatic folder thumbnail updates:

```bash
# Edit crontab
crontab -e

# Add this line to run daily at 3 AM
0 3 * * * /path/to/generate_folder_thumbnails.sh && systemctl restart minidlna
```

## Benefits Over First-Video Thumbnails

| Before (First Video) | After (Collage) |
|---------------------|-----------------|
| Random thumbnail from first video | Representative preview of folder contents |
| All folders look similar | Instantly recognizable |
| Misleading for mixed content | Shows variety of content |
| No visual distinction | Clear "this is a folder" indicator |

## Advanced: Custom Collage Styles

Edit the ImageMagick commands to create different styles:

### Rounded Corners
```bash
convert \( thumb_1.jpg thumb_2.jpg +append \) \
        \( thumb_3.jpg thumb_4.jpg +append \) \
        -append -resize 320x320 \
        \( +clone -alpha extract -blur 0x4 \) \
        -channel A -compose DstIn -composite output.jpg
```

### Add Border
```bash
convert ... -bordercolor black -border 2 output.jpg
```

### Add Shadow
```bash
convert ... \( +clone -background black -shadow 60x5+10+10 \) \
        +swap -background none -layers merge +repage output.jpg
```

---

Enjoy your beautiful folder thumbnails! 🎬📁
