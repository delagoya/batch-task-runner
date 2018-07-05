#!/bin/sh
if [ $# -ne "2" ]; then
  echo "USAGE: $0 <S3 or HTTP URL for a Funnel TaskFile> <container working directory>"
  exit 1
fi

TASKFILEURL=$1
TASKFILE="$(echo $1 | md5sum | cut -d' ' -f 1).json"
WORKDIR=$2

if ! [ -d ${WORKDIR} ]; then
  echo "ERR: Working directory does not exist (${WORKDIR})"
  exit 2
fi

if [ -n "${TASKFILEURL}" ] && [ "$(echo ${TASKFILEURL} | grep '^s3://'  -c)" -gt "0" ]; then
  cd ${WORKDIR}
  aws s3 cp ${TASKFILEURL} ${TASKFILE}
  funnel-x86-linux worker run -f ${TASKFILE}
elif [ -n "${TASKFILEURL}" ] && [ "$(echo ${TASKFILEURL} | grep '^https?://'  -c)" -gt "0" ]; then
  cd ${WORKDIR}
  wget -o  ${TASKFILE} ${TASKFILEURL}
  funnel-x86-linux worker run -f ${TASKFILE}
else
  echo "ERR: TaskFile not a S3 or HTTP URL (${TASKFILEURL})"
  exit 3
fi
