# MiniDLNA (ReadyMedia) Workspace Summary

## Project Overview

**MiniDLNA** (also known as ReadyMedia) is a lightweight UPnP-A/V and DLNA media server daemon that serves multimedia content (audio, video, images) to compatible clients on a network. It's designed to be a simple, efficient DLNA/UPnP-AV server for personal media streaming.

**Version:** 1.3.3 (Debian patched from upstream 1.1.3)
**License:** GPL-2.0 and BSD-3-Clause
**Primary Language:** C (ANSI C)

## Workspace Structure

```
minidlna/
├── Core Application (Root)
│   ├── Main: minidlna.c
│   ├── Media Scanning: scanner.c, metadata.c, playlist.c
│   ├── UPnP Protocol: upnp*.c, minissdp.c
│   ├── Media Handling: albumart.c, icons.c, image_utils.c
│   ├── Database: sql.c (SQLite)
│   ├── Monitoring: monitor_inotify.c, monitor_kqueue.c
│   └── Logging: log.c, log.h
├── tagutils/          - Audio metadata parsers (AAC, FLAC, MP3, Ogg, WAV, etc.)
├── buildroot/         - Buildroot embedded Linux integration
├── debian/            - Debian/Ubuntu packaging with systemd service
└── linux/             - Linux compatibility headers (inotify)
```

## Programming Languages & Standards

- **Primary:** C (ANSI C with some C99 features)
- **Shell:** Bash (for build scripts)
- **Build Tools:** GNU Autotools (Autoconf + Automake)

## Build System

### Build Tools
- **GNU Autotools** (primary build system)
  - `autogen.sh` - Generates build configuration (runs `autoreconf -vfi`)
  - `configure.ac` - Autoconf configuration
  - `Makefile.am` - Automake build rules
- **Buildroot** - Cross-compilation for embedded systems
- **Debian Packaging** - Native .deb package support

### Standard Build Process

```bash
# Bootstrap (first time or after git pull)
./autogen.sh

# Configure
./configure [options]

# Build
make -j$(nproc)

# Test
make check

# Install
sudo make install
```

### Build Requirements
- autoconf
- automake
- pkg-config
- C compiler (gcc/clang)
- Required libraries (see Dependencies section)

## Dependencies

### Required Libraries
- **libsqlite3** - Media library database
- **libavformat/libavcodec/libavutil** (FFmpeg) - Media format detection and metadata
- **libjpeg** - JPEG image handling
- **libexif** - EXIF metadata from images
- **libid3tag** - ID3 tag parsing for MP3
- **libFLAC** - FLAC audio support
- **libvorbis/libvorbisfile/libogg** - Ogg Vorbis support
- **pthread** - POSIX threads

### Optional Libraries
- **libavahi-client** - Bonjour/Zeroconf network discovery
- **libffmpegthumbnailer** - Video thumbnail generation (Debian patch)

### Amazon Internal Dependencies
**None** - This is a standard open-source project with no Brazil, Peru, or AWS SDK dependencies.

## Code Style Guidelines

### Indentation & Formatting
- **Tabs for indentation** (8-character tab width, K&R style)
- **No strict line length limit** (most lines under 80-100 characters)
- **K&R brace placement:**
  ```c
  int
  function_name(void)
  {
      if (condition) {
          statement;
      }
  }
  ```

### Naming Conventions
- **Functions:** `lowercase_with_underscores` (snake_case)
  - Examples: `log_init`, `get_next_available_id`, `trim`
- **Variables:** `lowercase_with_underscores` (snake_case)
- **Constants/Macros:** `UPPERCASE_WITH_UNDERSCORES`
  - Examples: `E_WARN`, `L_GENERAL`, `DPRINTF`
- **Enum types:** `_prefixed_lowercase` or `enum _name`
- **Pointer declarations:** Asterisk with variable: `char *str` (not `char* str`)

### Function Declaration Style
```c
int
function_name(type param1, type param2)
{
    // implementation
}
```
- Return type on its own line
- Function name starts at column 0
- Opening brace on next line for functions

### Header Guards
```c
#ifndef __FILENAME_H__
#define __FILENAME_H__
// ...
#endif
```

### Include Order
1. System headers: `#include <stdlib.h>`
2. Local headers: `#include "config.h"`

### Comments
- Block comments for file headers and copyright: `/* ... */`
- Multi-line comments with aligned asterisks:
  ```c
  /* MiniDLNA project
   *
   * http://sourceforge.net/projects/minidlna/
   */
  ```
- Inline comments: `//` (less common)

### No Automated Linting
The project does not use `.clang-format`, `.clang-tidy`, or `.editorconfig`. Follow patterns observed in existing code.

## Testing Framework

### Current Testing Infrastructure
- **No dedicated testing framework** (no Check, CMocka, Unity, etc.)
- **Single test program:** `testupnpdescgen.c`
  - Tests UPnP description generation
  - Manual verification of XML output
  - Run with: `make check` or `./testupnpdescgen`

### Running Tests
```bash
make check
```

### Test Writing Conventions
When adding new tests:
1. Create standalone test program: `test<component>.c`
2. Define mock/stub functions for dependencies
3. Use global constants for test fixtures
4. Print clear output for manual verification
5. Add to `check_PROGRAMS` in `Makefile.am`:
   ```makefile
   check_PROGRAMS = testupnpdescgen testmynewfeature
   testmynewfeature_SOURCES = testmynewfeature.c component.c
   testmynewfeature_LDADD = $(required_libs)
   ```
6. Return 0 for success, non-zero for failure

### Continuous Integration
**None** - No CI/CD configuration files present.

## Logging Framework

MiniDLNA uses a **custom built-in logging system** (`log.c` / `log.h`) with no third-party dependencies.

### Log Levels
```c
E_OFF      (0) - Logging disabled
E_FATAL    (1) - Fatal errors (exits program)
E_ERROR    (2) - Error conditions
E_WARN     (3) - Warning messages
E_INFO     (4) - Informational messages
E_DEBUG    (5) - Debug messages
E_MAXDEBUG (6) - Maximum verbosity
```

### Log Facilities
```c
L_GENERAL  - General application logging
L_ARTWORK  - Album artwork processing
L_DB_SQL   - Database/SQL operations
L_INOTIFY  - File system monitoring
L_SCANNER  - Media scanning
L_METADATA - Metadata extraction
L_HTTP     - HTTP server
L_SSDP     - SSDP/UPnP discovery
L_TIVO     - TiVo integration
```

### Logging API

**Primary Interface (use this):**
```c
#include "log.h"

// Recommended macro for all logging
DPRINTF(level, facility, fmt, arg...)

// Examples
DPRINTF(E_ERROR, L_METADATA, "Failed to parse file: %s\n", filename);
DPRINTF(E_WARN, L_SCANNER, "Skipping invalid entry\n");
DPRINTF(E_INFO, L_GENERAL, "Server started on port %d\n", port);
DPRINTF(E_DEBUG, L_HTTP, "Processing request from %s\n", ip_addr);
```

**Initialization:**
```c
int log_init(const char *debug);  // Initialize with debug string
void log_close(void);              // Close log file
void log_reopen(void);             // Reopen (for log rotation)
```

**Configuration:**
- Debug string format: `"general=info,scanner=debug"` or just `"debug"`
- Log file location: Global variable `log_path` (from `upnpglobalvars.h`)
- Log filename: `minidlna.log`
- Default level: `E_WARN`

**Log Output Format:**
```
[YYYY/MM/DD HH:MM:SS] filename.c:line: level: message
```

### Metrics/Monitoring
**No metrics framework** - The project does not use performance counters, StatsD, Prometheus, or custom metrics emission. The `monitor.*` files are for file system change detection (inotify/kqueue), not application metrics.

## Key Features

- **Media Types:** Audio, Video, Images
- **Protocols:** DLNA, UPnP-A/V, TiVo HMO
- **Media Discovery:** inotify-based automatic scanning (Linux) or kqueue (BSD)
- **Database:** SQLite for media library indexing
- **Album Art:** Automatic extraction and caching
- **Transcoding:** Via FFmpeg libraries
- **Network Discovery:** SSDP broadcast + optional Avahi/Bonjour
- **Configuration:** `/etc/minidlna.conf`

## Platform Support

- **Linux** (primary) - Uses inotify for file monitoring
- **BSD variants** - Uses kqueue for file monitoring
- **Embedded systems** - Via Buildroot integration

## Common Development Tasks

### Building the Project
```bash
# Clean build
make clean && make -j$(nproc)

# Verbose build
make V=1

# Static build (embedded systems)
./configure --enable-static --enable-tivo --enable-lto
make
```

### Code Analysis
```bash
# Compiler warnings
make CFLAGS='-Wall -Wextra -Wpedantic -Werror'

# Static analysis with cppcheck
cppcheck --enable=all --inconclusive --suppress=missingIncludeSystem .

# Find potential issues
grep -r "TODO\|FIXME\|XXX\|HACK" *.c *.h
```

### Running the Server
```bash
# Development mode (foreground, verbose)
./minidlna -f /path/to/config -d

# Production (daemon mode)
./minidlna -f /path/to/config

# Force rescan
./minidlna -f /path/to/config -R
```

## Configuration

### Main Configuration File
`/etc/minidlna.conf` - Primary configuration

Key settings:
- `media_dir=A,/path/to/audio` - Audio directory
- `media_dir=V,/path/to/video` - Video directory
- `media_dir=P,/path/to/pictures` - Pictures directory
- `db_dir=/var/cache/minidlna` - Database location
- `log_dir=/var/log` - Log file location
- `inotify=yes` - Enable automatic scanning
- `friendly_name=My DLNA Server` - Server name
- `log_level=general,artwork,database,inotify,scanner,metadata,http,ssdp,tivo=warn`

### Systemd Service
`/etc/systemd/system/minidlna.service` - Service definition (from `debian/minidlna.service`)

## Recent Changes (Git)

Latest commit: `ba13d34` (4 days ago) - "Fix escaping and add ffmpegthumbnailer thumbs"

Recent development focus:
- FFmpeg thumbnail generation improvements
- Filename sanitization and escaping
- Debian packaging updates

## Development Tools Available

### Via Wasabi's LocalAmazonRun
All build and development tasks use standard shell commands:

```bash
# Build commands
LocalAmazonRun "make clean && make -j$(nproc)"
LocalAmazonRun "./autogen.sh && ./configure"

# Testing
LocalAmazonRun "make check"
LocalAmazonRun "./testupnpdescgen"

# Static analysis
LocalAmazonRun "cppcheck --enable=all ."
LocalAmazonRun "make CFLAGS='-Wall -Wextra -Werror'"

# Code search
LocalAmazonRun "grep -r 'pattern' *.c *.h"
```

**No custom Wasabi tools** - The project's build and test operations are straightforward and don't require custom tool wrappers.

## Important Notes for Code Modifications

1. **Always use tabs** for indentation (never spaces)
2. **Include GPL license header** at the top of new files
3. **Use DPRINTF macro** for all logging with appropriate facility
4. **Follow K&R style** with return type on separate line for functions
5. **Test with multiple media types** (audio, video, images) when modifying scanner/metadata code
6. **Check for memory leaks** - The daemon runs long-term
7. **Consider platform differences** (inotify vs kqueue)
8. **Update man page** (`minidlna.conf.5`) if adding configuration options
9. **Test with real DLNA clients** (Smart TVs, game consoles, mobile apps)

## Resources

- **Project Homepage:** http://sourceforge.net/projects/minidlna/
- **Manual Page:** `man minidlna.conf` (configuration reference)
- **Log Files:** Check `/var/log/minidlna.log` for runtime issues
- **Database:** SQLite at `/var/cache/minidlna/files.db`

## Troubleshooting

### Build Issues
- Run `./autogen.sh` if configure doesn't exist
- Install missing dependencies via package manager
- Check `config.log` for configuration errors

### Runtime Issues
- Increase log level: `log_level=general,scanner,metadata=debug`
- Force database rebuild: `minidlna -R`
- Check file permissions on media directories
- Verify network connectivity for UPnP/SSDP

### Test Failures
- Inspect `testupnpdescgen` XML output manually
- Verify UPnP service descriptors are well-formed XML
