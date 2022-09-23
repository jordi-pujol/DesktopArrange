#!/bin/sh

[ -e build-stamp ] || \
	: > build-stamp

if [ -n "$(find . -type f -anewer build-stamp)" ]; then
	debuild -tc
	: > build-stamp
fi
