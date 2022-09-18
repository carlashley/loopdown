#!/bin/zsh

NAME=loopdown
VERSION=$(/usr/bin/awk '/VERSION = / {print $NF}' ${NAME}.py | /usr/bin/sed 's/"//g')
NUITKA=$(which nuitka3)

if [ ! -z {$NUITKA} ]; then
    eval ${NUITKA} \
        --macos-app-name=${NAME} \
        --macos-app-version=${VERSION} \
        --standalone \
        --onefile \
        --remove-output \
        --macos-target-arch=x86_64 \
        -o ./dist/x86_64/${NAME} \
        ${NAME}.py

    eval ${NUITKA} \
        --macos-app-name=${NAME} \
        --macos-app-version=${VERSION} \
        --standalone \
        --onefile \
        --remove-output \
        --macos-target-arch=arm64 \
        -o ./dist/arm64/${NAME} \
        ${NAME}.py
else
    echo "Build tool nuitka3 is missing, please install it."
fi
