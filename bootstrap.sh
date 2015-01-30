#!/bin/sh

set -e

# Ensure the script is run successfully
if [ -z "$1" ]
then
  echo "Usage: $0 username" >&2
  exit 1
fi

username="$1"

# Set up dependencies
for archive in deps-archives/*.tar.*
do
  dep_name=`echo $(basename $archive)     | sed -e 's/-.*\.tar\..*$//'`
  base_name=`echo $(basename $archive)    | sed -e 's/\.tar\..*$//'`
  archive_type=`echo $(basename $archive) | sed -e 's/^.*\.tar\.//'`

  if [ -d deps/$dep_name ]
  then
      echo "Skipping: $archive"
  else
      echo "Uncompressing: $archive"
      case $archive_type in
        gz)
          gunzip -c $archive | tar -C deps/ -x -f -
            ;;
        bz2)
          bunzip2 -c $archive | tar -C deps/ -x -f -
            ;;
        xz)
          unxz -c $archive | tar -C deps/ -x -f -
            ;;
      esac

      mv deps/$dep_name* deps/$dep_name
  fi
done

# Clean/remove built environment
docker rmi $username/muslbase-build-base || true
docker rmi $username/muslbase-build || true

# Create Dockerfile
sed "s|@@USERNAME|$username|" < Dockerfile.in > Dockerfile

# Build, first using glibc from debian, then musl from selfhost build environment
for buildbase in debian selfhost selfhost
do
  if [ "$buildbase" = "selfhost" ]
  then
    # If we're self-hosting, use muslbase as the build environment
    docker tag $username/muslbase $username/muslbase-build-base
  else
    # Otherwise, build and use the initial Debian base build environment
    docker build --rm -t=$username/muslbase-build-base buildbase/$buildbase
  fi

  # Remove earlier muslbase images
  docker rmi $username/muslbase || true
  docker rmi $username/muslbase-runtime || true
  docker rmi $username/muslbase-static-runtime || true

  # Build muslbase rootfs
  docker build --rm -t=$username/muslbase-build .

  # Build docker image: muslbase
  docker run --rm $username/muslbase-build cat /rootfs.tar > rootfs/full/rootfs.tar
  docker build --rm -t=$username/muslbase rootfs/full
  rm rootfs/full/rootfs.tar

  # Build docker image: muslbase-runtime
  docker run --rm $username/muslbase-build cat /runtime-rootfs.tar > rootfs/runtime/rootfs.tar
  docker build --rm -t=$username/muslbase-runtime rootfs/runtime
  rm rootfs/runtime/rootfs.tar

  # Build docker image: muslbase-static-runtime
  docker run --rm $username/muslbase-build cat /static-runtime-rootfs.tar > rootfs/static-runtime/rootfs.tar
  docker build --rm -t=$username/muslbase-static-runtime rootfs/static-runtime
  rm rootfs/static-runtime/rootfs.tar

  # Clean/remove build environment
  docker rmi $username/muslbase-build-base
  docker rmi $username/muslbase-build
done
