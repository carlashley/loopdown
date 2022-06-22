# loopdown
Downloads loop packages for GarageBand, Logic Pro, MainStage 3


## Requirements
Python 3.5+

## Usage
```
[jappleseed@loopback]:loopdown # ./loopdown.py -h
usage: loopdown.py [-h] [-n] [-m] [-o] [-d [path]] -p [[file] ...]
                   [--retries [retry]] [-v]

options:
  -h, --help            show this help message and exit
  -n, --dry-run         performs a dry run (prints each URL to screen)
  -m, --mandatory       process mandatory packages, either this or
                        -o/--optional is required
  -o, --optional        process optional packages, either this or
                        -m/--mandatory is required
  -d [path], --destination [path]
                        path to download destination, folder path will be
                        created automatically if it does not exist; defaults
                        to '/tmp/loopdown' for non dry-runs
  -p [[file] ...], --property-list [[file] ...]
                        path to property list file/s to process, must be valid
                        file path and property list file; required
  --retries [retry]     maximum number of retries (default 3)
  -v, --version         show program's version number and exit
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
```
