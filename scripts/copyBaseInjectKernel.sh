#! /bin/bash

#Make the kernel
make kernel

#Make a new copy of the image
cp PrawnOS-Alpha-c201-libre-2GB.img-base PrawnOS-Alpha-c201-libre-2GB.img

#inject the kernel
make kernel_inject

#Rename the new image to match the patch
mv  PrawnOS-Alpha-c201-libre-2GB.img PrawnOS-Alpha-c201-libre-2GB.img-$1
