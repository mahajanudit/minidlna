#!/bin/bash
# Quick installation and testing script for Armbian/Debian

set -e

echo "=== MiniDLNA Video Thumbnail Installation ==="
echo ""

# Check if ffmpegthumbnailer is installed
echo "Step 1: Checking for ffmpegthumbnailer..."
if ! command -v ffmpegthumbnailer &> /dev/null; then
    echo "Installing ffmpegthumbnailer..."
    sudo apt-get update
    sudo apt-get install -y ffmpegthumbnailer
else
    echo "✓ ffmpegthumbnailer already installed"
fi

# Stop minidlna if running
echo ""
echo "Step 2: Stopping minidlna service..."
sudo systemctl stop minidlna 2>/dev/null || true

# Install
echo ""
echo "Step 3: Installing minidlna..."
sudo make install

# Force database rescan
echo ""
echo "Step 4: Forcing database rescan (this will take time)..."
echo "This rebuilds the database and generates thumbnails for all videos."
sudo minidlna -R

# Start service
echo ""
echo "Step 5: Starting minidlna service..."
sudo systemctl start minidlna

echo ""
echo "Step 6: Waiting for service to initialize..."
sleep 5

# Run diagnostics
echo ""
echo "Step 7: Running diagnostics..."
sudo ./debug_thumbnails.sh

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Check the diagnostic output above. You should see:"
echo "  - Videos with album art: > 0"
echo "  - Thumbnails in cache: > 0"
echo ""
echo "If thumbnails still don't appear, check /var/log/minidlna.log"
