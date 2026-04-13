# About
This is the last version of the Python implementation of `loopdown`. Future releases will be Swift implementations and will only support macOS 14+.

## Notes
- Not tested against the version of Logic Pro in the Apple Creator Suite
- This has been tested on Python 3.13, it should work for Python 3.11+ but no testing has been done for older Python releases.
- The `zipapp` build should install the two requirements when `./build.sh` is run.
- - See _Build help_ below for usage.
- This is intended to be the last release of a Python version of this tool, future releases will be implemented in Swift.
- - New features will be sparingly added to the Swift release as the intention is to create a very basic tool to handle downloading and installing content packages.
- - There is no guarantee that there will be regular releases of the Swift implementation.
- This version no longer relies on applications existing in `/Applications`. Application installation paths are determined from the output of `system_profiler` data.
- Downloads do not rely on `curl -C -` for partial file resumption, in fact there are no attempts made at resuming incomplete downloads.
- - There are no plans to implement any partial download resumption in this release.
- Please take note of the new argument syntax as noted in the _Usage_ section below.

## Important Note About Logic Pro 12+ and MainStage 4+
Rudimentary support for the new method used to install audio content packs has been added for Logic Pro 12+ and MainStage 4+.

How this deployment process works when the apps are updated is as yet unknown; the way in which content is considered as installed and what version the content is has changed as Apple no longer ships the content in a traditional `pkg` format. Using `-f/--force` may be required to ensure content remains updated.

The testing of this deployment process has only been done against "clean" installs of macOS and respective audio apps; the new versions of Logic Pro and MainStage appear to do a migration of existing content packages, so it's not known how this deployment process will work in scenarios where legacy content packs have been installed.

If deploying GarageBand + either/all of the new apps, there is a significant amount of space consumed; in my testing of this scenario, there is at least 200GB of data installed (most likely a large amount of this is duplication of legacy content). This is worth keeping in mind if using `loopdown` to deploy content packs for these apps.

### Before Deployment of Logic Pro 12+ and/or MainStage 4+
Apple has changed the way their additional content packs are installed for Logic Pro 12+ and MainStage 4+; when "core" and "essential" packs are installed on the first run, they are installed to the users Music directory, specifically `/Users/<user>/Music/Logic Pro Library.bundle`.

For lab deployments or where many users will login to the Mac, this has the potential to waste disk space as the contents get duplicated for each user logging in and using either of the Logic Pro/MainStage apps.


It is possible for this library directory to be placed in a centralised location and a symlink created in the `~/Music` directory to point to this location, so you will need to decide where this directory will be located; by default, `loopdown` will install this content to `/Users/Shared/Logic Pro Library.bundle`.

if you change this default directory value, it is essential that any time you do a deployment run that you specify the `-b/--library-dest` argument with the path to the directory you've chosen, otherwise all the audio content packs will be re-deployed as if they were never installed.

There are additional steps after deploying the content that you will need to do to ensure that Logic Pro/MainStage will correctly detect the centralised location of the library. They are documented below.

### After Deployment of Logic Pro 12+ and/or MainStage 4+
After deploying the content for Logic Pro 12+ and/or MainStage 4+ to a centralised location, you will need to do the following (thanks to ElliotD in the MacAdmins `musicsupport`` channel for working this out):
1. Ensure a symlink exists in `~/Music` that points to the centralised directory; the mechanism through which this is handled is up to you
1. Create a LaunchAgent (either in `/Library/LaunchAgents` or in `~/Library/LaunchAgents`) that runs a script that copies `~/Library/Application Support/com.apple.musicapps.content/Logic Pro Library.bookmark` into the same directory the content was installed to
1. If you do not want the content to be deleted by anyone, add an ACL to the directory the content was installed to (deleting the content at a later date will require this to be removed)

A basic example of configuring things after deployment, presuming the default `-b/--library-dest` value of `/Users/Shared/Logic Pro Library.bundle`:
```
# /bin/ln -s /Users/Shared/Logic\ Pro\ Library.bundle ~/Music/
# /bin/cat > /Library/LaunchAgents/com.github.carlashley.loopdown.copy_bookmark.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.github.carlashley.loopdown.copy_bookmark</string>
    <key>ProgramArguments</key>
    <array>
      <string>/path/to/script/copy_library_bookmark.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
EOF
# /bin/chmod +a "everyone deny delete,delete_child" /Users/Shared/Logic\ Pro\ Library.bundle
```
The LaunchAgent should be installed as a _system_ level agent (`/Library/LaunchAgent`) so it can automatically be run during that users login, alternatively you could use `outset` to run the script on every login.


# Building
1. In your preferred directory: `git clone https://github.com/carlashley/loopdown`
1. `cd loopdown/loopdown`
1. `./build.sh -h`
1. `./build.sh [your chosen options]`

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
./loopdown -h
Warning: this Python implementation of loopdown has been deprecated and will move to a Swift based implementation in the future.
usage: loopdown [-h] [-v] [-l [level]] [-q] [--no-proxy] [--skip-signature-check] [deploy,download] ...

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
  --no-proxy            ignore proxies for '*' in all curl subprocess calls
  --skip-signature-check
                        skip the signature check after downloads (this is off by default in 'deploy' mode and in dry-runs)

package selection:
  at least one of -e/--esn, -r/--core, or -o/--opt is required

loopdown v2.0.3.b2. Copyright © 2026 Carl Ashley. All rights reserved. Apache License Version 2.0 - http://www.apache.org/licenses/
```

## Download help
```
./loopdown download -h
Warning: this Python implementation of loopdown has been deprecated and will move to a Swift based implementation in the future.
usage: loopdown download [-h] [-n] [-a [app ...]] [-f] [-e] [-r] [-o] [-d [dir]]

Download audio content packages locally

options:
  -h, --help            show this help message and exit
  -n, --dry-run         perform a dry run; no mutating action taken
  -a, --apps [app ...]  override the default 'garageband', 'logicpro', 'mainstage' set of apps that audio content will be processed for;
                        choices are 'garageband', 'logicpro', 'mainstage'
  -f, --force           force the specified action
  -d, --dest [dir]      override the download directory path when '--download-only' used; default is '/tmp/loopdown'

package selection:
  at least one of -e/--esn, -r/--core, or -o/--opt is required

  -e, --esn             include the essential audio packages (Logic Pro 12+ and MainStage 4+ only)
  -r, --core            include the core audio packages (equivalent to '-r/--req' for legacy audio applications)
  -o, --opt             include the optional audio packages
```

## Deploy help
```
./loopdown deploy -h  
Warning: this Python implementation of loopdown has been deprecated and will move to a Swift based implementation in the future.
usage: loopdown deploy [-h] [-b [dir]] [-n] [-a [app ...]] [-f] [-e] [-r] [-o] [-c [url]] [-m [url]]

Deploy audio content packages locally (requires elevated permission when not performing dry-run)

options:
  -h, --help            show this help message and exit
  -b, --library-dest [dir]
                        the destination where modern Logic Pro 12+ and MainStage 4+ content is deployed to; default is '/Users/Shared/Logic Pro Library.bundle'
  -n, --dry-run         perform a dry run; no mutating action taken
  -a, --apps [app ...]  override the default 'garageband', 'logicpro', 'mainstage' set of apps that audio content will be processed for;
                        choices are 'garageband', 'logicpro', 'mainstage'
  -f, --force           force the specified action
  -c, --cache-server [url]
                        use a caching server; when no server is specified, attempts to auto detect; expected format is 'http://ipaddr:port'
  -m, --mirror-server [url]
                        local mirror server to use; expected format is 'https://example.org'

package selection:
  at least one of -e/--esn, -r/--core, or -o/--opt is required

  -e, --esn             include the essential audio packages (Logic Pro 12+ and MainStage 4+ only)
  -r, --core            include the core audio packages (equivalent to '-r/--req' for legacy audio applications)
  -o, --opt             include the optional audio packages
```
