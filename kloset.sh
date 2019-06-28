#!/bin/bash

# Allow overriding
while getopts "hi:t:v:a:" opt; do
  case ${opt} in
    i ) # process option a
      echo "install $OPTARG"
      INSTALL_PATH=$OPTARG
      ;;
    t ) # process option t
      GITHUB_TOKEN=$OPTARG
      ;;
    v ) # process option v
      VERSION=$OPTARG
      ;;
    a ) # process option a
      ARCH=$OPTARG
      ;;
    h )
      echo "Usage: install [-h] [-t GITHUB_TOKEN] [-i INSTALL_PATH] [-v VERSION] [-a ARCH]"
      echo "  -t defaults to \$LOCKIT_GITHUB_TOKEN"
      echo "  -i defaults to /usr/local/bin"
      echo "  -v defaults to latest"
      echo "  -a by default it will auto-detect using uname"
      exit 1
      ;;
    *)
      exit 2
  esac
done

# Check which variant we should download
if [ "`uname`" = "Darwin" ]; then
  VARIANT=osx
else
  VARIANT=linux
fi

# Defaults for developer machine
INSTALL_PATH=${INSTALL_PATH:=/usr/local/bin}
GITHUB_TOKEN=${GITHUB_TOKEN:-$LOCKIT_GITHUB_TOKEN}
VERSION=${VERSION:-latest}
ARCH=${ARCH:-$VARIANT}
REPO_DOWNLOAD_LOCATION=${REPO_DOWNLOAD_LOCATION:-$(cd ../ && pwd)}

# Parameters. Generally you should only need to change this section
TMP_PATH=/tmp
NAME=kloset
EXE=$INSTALL_PATH/klosetd
FILE=klosetd-$ARCH.tgz


echo "Installing $NAME $VERSION ($ARCH) to $INSTALL_PATH"

LOCK_FILE=/tmp/$NAME-install.exclusivelock
(
  # Wait for lock (fd 200) for 5 minutes
  if [ $(which flock) ]; then
    echo "Acquiring lock" $LOCK_FILE " ..."
    flock -w 300 200
    echo "Got lock" $LOCK_FILE
  fi
  IFS=',' read -ra TOKENS <<< "$GITHUB_TOKEN"
  if [ "$VERSION" = "latest" ]; then
    path=$VERSION
  else
    current=`$EXE --version`
    IFS=' ' read -ra VER <<< "$current"
    if [ "${VER[1]}" = "$VERSION" ]; then
      echo "$EXE already up to date"
      $EXE --version
      exit 0
    fi
    path="tags/v$VERSION"
  fi

  echo "===================== DOWNLOADING KLOSET SOURCE CODE ======================="

  releases_json=`curl -H "Authorization: token ${TOKENS[0]}" -H "Accept: application/vnd.github.v3.raw" -s https://api.github.com/repos/coupa/$NAME/releases/$path`
  #release_path="api.github.com/repos/coupa/kloset/tarball/build/109"
  release_path=`echo $releases_json | sed -e 's|^\"tarball_url\": \"http[s]*://||' | sed -e 's/\".*$//'`
  
  echo "*** Downloading $NAME release in $REPO_DOWNLOAD_LOCATION from $release_path ***"
  mkdir -p $REPO_DOWNLOAD_LOCATION
  curl --basic -L https://${TOKENS[0]}:@$release_path > $REPO_DOWNLOAD_LOCATION/$NAME.tar.gz
  repo_dir_name=`tar -tf $REPO_DOWNLOAD_LOCATION/$NAME.tar.gz | head -1 | cut -f1 -d"/"`
  tar -zxvf $REPO_DOWNLOAD_LOCATION/$NAME.tar.gz -C $REPO_DOWNLOAD_LOCATION
  rm $REPO_DOWNLOAD_LOCATION/$NAME.tar.gz

  echo "==================== SETTING UP AND RUNNING KLOSETD ===================="

  echo "*** Downloading klosetd binary ***"
  asset_json=`echo $releases_json | sed -e 's/^.*\"assets\": \[ //' | sed -e 's/\ ].*$//' | sed -e 's/}, {/\}$\{/' | tr '$' '\n' | grep "$FILE"`
  asset_path=`echo $asset_json | sed -e 's|^{ \"url\": \"http[s]*://||' | sed -e 's/\".*$//'`
  
  echo "*** Downloading $NAME from $asset_path ***"
  curl --basic -L -H 'Accept:application/octet-stream' https://${TOKENS[0]}:@$asset_path > $TMP_PATH/$FILE

  echo "*** Installing klosetd ***"
  mkdir -p $INSTALL_PATH && tar -zxvf $TMP_PATH/$FILE -C $INSTALL_PATH

  echo "*** Creating config file in /etc/klosetd.yml ***"
  sudo cp $REPO_DOWNLOAD_LOCATION/$repo_dir_name/agent/development.yml /etc/klosetd.yml
  echo "NOTE: Configuration in /etc/klosetd.yml points to Kloset Central running on localhost:8080"
  rm $TMP_PATH/$FILE

  echo "*** Running klosetd ***"
  klosetd server&
  
  echo "======================== RUNNING KLOSET CENTRAL IN DOCKER ========================"

  echo "*** Running kloset central on port 8080 ***"
  make docker.build -C $REPO_DOWNLOAD_LOCATION/$repo_dir_name
  make docker.run -C $REPO_DOWNLOAD_LOCATION/$repo_dir_name

) 200>$LOCK_FILE
