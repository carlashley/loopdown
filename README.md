# About
This is the last version of the Python implementation of `loopdown`. This will be migrated to Swift and will only support macOS 14+.

## Notes
- This is intended to be the last release of a Python version of this tool, future releases will be implemented in Swift.
- - New features will be sparingly added to the Swift release as the intention is to create a very basic tool to handle downloading and installing content packages.
- - There is no guarantee that there will be regular releases of the Swift implementation.
- This version no longer relies on applications existing in `/Applications`. Application installation paths are determined from the output of `system_profiler` data.
- Downloads do not rely on `curl -C -` for partial file resumption, in fact there are no attempts made at resuming incomplete downloads.
- - There are no plans to implement any partial download resumption in this release.
- Please take note of the new argument syntax as noted in the _Usage_ section below.

# Installation
1. In your preferred directory: `git clone https://github.com/carlashley/loopdown`
1. `cd loopdown/loopdown`
1. `./build.sh -h`

## Build help
```
./build.sh -h
Usage: ./build.sh [options]

Options:
  --build-python=...   Python to use for building (pip + zipapp). If omitted, uses python3 on PATH.
                       Examples:
                         --build-python=/opt/python/bin/python3
                         --build-python=/usr/local/bin/python3

  --interpreter=...    Interpreter string embedded in the zipapp shebang (default: /usr/bin/env python3)
                       Examples:
                         --interpreter=/usr/local/bin/python3
                         --interpreter="/usr/bin/env python3"

  --main=...           Zipapp entrypoint (default: loopdown.__main__:main)

  -h, --help           Show help
```

# Usage
## Primary help
```
python3 -m loopdown -h
usage: loopdown [-h] [-v] [-l [level]] [-q] [deploy,download] ...

Process additional content for installed audio applications, GarageBand, Logic Pro, and/or MainStage.

positional arguments:
  [deploy,download]     use [deploy,download] -h for further help
    deploy              deploy audio content packages locally (requires elevated permission when not performing dry-run)
    download            download audio content packages locally

options:
  -h, --help            show this help message and exit
  -v, --version         show program's version number and exit
  -l, --log-level [level]
                        override the log level; default is 'info', choices are 'critical', 'error', 'warning', 'info', 'debug', 'notset'
  -q, --quiet           all console output (stdout/stderr) is suppressed; events logged to file only

loopdown v2.0.20260120. Copyright © 2026 Carl Ashley. All rights reserved. Apache License Version 2.0 - http://www.apache.org/licenses/
```

## Download help
```
python3 -m loopdown download -h
usage: loopdown download [-h] [-n] [-a [app ...]] [-r] [-o] [-f] [-d [dir]]

Download audio content packages locally

options:
  -h, --help            show this help message and exit
  -n, --dry-run         perform a dry run; no mutating action taken
  -a, --apps [app ...]  override the default 'garageband', 'logicpro', 'mainstage' set of apps that audio content will be processed for;
                        choices are 'garageband', 'logicpro', 'mainstage'
  -r, --req             include the required audio packages
  -o, --opt             include the optional audio packages
  -f, --force           force the specified action
  -d, --dest [dir]      override the download directory path when '--download-only' used; default is '/tmp/loopdown'
```

## Deploy help
```
python3 -m loopdown deploy -h
usage: loopdown deploy [-h] [-n] [-a [app ...]] [-r] [-o] [-f] [-c [url]] [-m [[url]]]

Deploy audio content packages locally (requires elevated permission when not performing dry-run)

options:
  -h, --help            show this help message and exit
  -n, --dry-run         perform a dry run; no mutating action taken
  -a, --apps [app ...]  override the default 'garageband', 'logicpro', 'mainstage' set of apps that audio content will be processed for;
                        choices are 'garageband', 'logicpro', 'mainstage'
  -r, --req             include the required audio packages
  -o, --opt             include the optional audio packages
  -f, --force           force the specified action
  -c, --cache-server [url]
                        use a caching server; when no server is specified, attempts to auto detect; expected format is 'http://ipaddr:port'
  -m, --mirror-server [[url]]
                        local mirror server to use; expected format is 'https://example.org'
```
