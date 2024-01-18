#!/bin/bash
MYSAVEDIR=$(mktemp -d -p ../)
if [ -x "$(command -v realpath)" ]; then
  MYSAVEDIR=$(realpath "$MYSAVEDIR")
elif [ -x "$(command -v readlink)" ]; then
  MYSAVEDIR=$(readlink -f "$MYSAVEDIR")
else
  MYSAVEDIR=$(pwd)/$MYSAVEDIR
fi
case $MYOPENWRTTARGET in
  R2S)
    mv -f ./*squashfs* ./*manifest* "$MYSAVEDIR"/
    ;;
  x86)
    mv -f ./*combined* ./*manifest* "$MYSAVEDIR"/
    ;;
  *)
    echo "Error: Unknown target"
    echo "Please check your environment variable: MYOPENWRTTARGET"
    echo "Current value is: $MYOPENWRTTARGET"
    rmdir "$MYSAVEDIR"
    exit 1
    ;;
esac
rm -rf ./*
pushd "$MYSAVEDIR" > /dev/null
  gzip -d ./*.gz
  gzip --best --keep ./*.img
  echo && echo
  sha256sum openwrt* | tee "sha256_$(date '+%Y%m%d').hash"
  md5sum    openwrt* | tee    "md5_$(date '+%Y%m%d').hash"
  echo && echo
  rm -f ./*.img
popd > /dev/null
mv -f "$MYSAVEDIR"/* ./
rmdir "$MYSAVEDIR"
exit 0
