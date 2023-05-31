#!/bin/zsh

NAME="loopdown"
BUILD_DIR=./dist/zipapp/usr/local/bin
VERSION=$(/usr/bin/awk -F ' ' '/_version: / {print $NF}' ./src/ldilib/__init__.py | /usr/bin/sed 's/"//g')
ARCHIVE_V=${BUILD_DIR}/${NAME}-${VERSION}
BUILD_OUT=./${NAME}
LOCAL_PYTHON=$(echo "/usr/bin/env python3")
INTERPRETER=$1

if [[ -z ${INTERPRETER} ]]; then
    INTERPRETER="/usr/local/bin/python3"
fi

if [[ ! -d ${BUILD_DIR} ]]; then
    mkdir -p ${BUILD_DIR}
fi

BUILD_CMD=$(echo "${LOCAL_PYTHON}" -m zipapp src --compress --output ${ARCHIVE_V} --python=\"${INTERPRETER}\")
echo ${BUILD_CMD}
eval ${BUILD_CMD}


if [[ $? == 0 ]] && [[ -f ${ARCHIVE_V} ]]; then
    /bin/cp ${ARCHIVE_V} ${BUILD_OUT}
    /bin/echo Built ${BUILD_OUT}
fi
