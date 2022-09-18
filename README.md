# loopdown
Download or print out the URL to the additional content packages that Apple provides for the GarageBand, Logic Pro, and MainStage audio programs.
Intended as a generic replacement for `appleloops` to facilitate _downloading_ content packages from the aforementioned apps.

## Requirements
Python 3.5+ (Python3 3.9 recommended).

Note: Standalone versions are available in the `./dist` directory for either the `x86_64` or `arm64` platforms. A Python framework should not be required to use these versions.
 - These are built using `nuitka3` and have only had basic testing done on macOS 12, support is provided _as is_.

## Usage
```
[jappleseed@loopback]:loopdown # ./loopdown.py -h
usage: loopdown [-h] [-n] [-m] [-o] [-d [path]] [-p [[file] ...] | -t [file]] [--retries [retry]] [-v]

loopdown v1.0.20220918 is a utility to download the audio content packages
from Apple so they can be deployed with third party app management tools
such as 'munki' or 'JAMF'.
 
Basic usage example:
  loopdown -p garageband1021.plist -m -d ~/Desktop/appleaudiocontent
 
If a specified property list file is not found at the specified path, then
loopdown will fallback to a remote version of that property list file, if
available.
 
The specific property list files are usually found in the app bundle:
  /Applications/[app]/Contents/Resources/[appname]NNNN.plist
'NNNN' represents a 'version' number.
 
For example:
 
  /Applications/GarageBand.app/Contents/Resources/garageband1021.plist
 
Note: The property list file does not always get updated with each audio app
release.
 
For the most recent version of loopdown:
  git: https://github.com/carlashley/loopdown

options:
  -h, --help            show this help message and exit
  -n, --dry-run         performs a dry run (prints each URL to screen)
  -m, --mandatory       process mandatory packages, either this or -o/--optional is required
  -o, --optional        process optional packages, either this or -m/--mandatory is required
  -d [path], --destination [path]
                        path to download destination, folder path will be created
                        automatically if it does not exist; defaults to '/tmp/loopdown'
                        for non dry-runs
  -p [[file] ...], --property-list [[file] ...]
                        path to property list file/s to process, must be valid file path
                        and property list file; required
  -t [file], --text-file [file]
                        download audio content packages from URLs in a text file
  --retries [retry]     maximum number of retries (default 3)
  -v, --version         show program's version number and exit
[jappleseed@loopback]:loopdown #
[jappleseed@loopback]:loopdown #
[jappleseed@loopback]:loopdown #
[jappleseed@loopback]:loopdown # ./loopdown.py -n -p ~/Downloads/ms.plist -m -o
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/GarageBandBasicContent.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/JamPack1.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/JamPack4_Instruments.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacy1.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacyRemix.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacyRhythm.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacySymphony.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacyVoices.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2013/MAContent10_AppleLoopsLegacyWorld.pkg
...
https://audiocontentdownload.apple.com/lp10_ms3_content_2016/MAContent10_AssetPack_0557_IRsSharedAUX.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2016/MAContent10_AssetPack_0558_GBLogicAlchemyEssentials.pkg
https://audiocontentdownload.apple.com/lp10_ms3_content_2016/MAContent10_AssetPack_0559_LogicAlchemyEssentials.pkg
[jappleseed@loopback]:loopdown #./loopdown.py -p ~/Downloads/ms.plist -m -o 
Downloading GarageBandBasicContent.pkg (1.46GB, 1 of 564):
#################################################################################### 100%
...
Downloading (298.21 MB, 564 of 564:
#################################################################################### 100%
Loop content downloaded to '/tmp/loopdown'
[jappleseed@loopback]:loopdown #
```
