#!/bin/bash

# Script for installing various dependencies for Travis jobs.
# Usage: ./travis_install.sh libmongoc|mongodb|sourcery|swiftlint

# usage: install_from_gh [name] [url]
install_from_gh () {
	NAME=$1
	URL=$2
	mkdir ${PWD}/${NAME}
	curl -L ${URL} -o ${PWD}/${NAME}/${NAME}.zip
	unzip ${PWD}/${NAME}/${NAME}.zip -d ${PWD}/${NAME}
}

if [[ $1 == "libmongoc" ]]
then
	if [[ "$TRAVIS_OS_NAME" == "osx" ]]; then INSTALL_PREFIX=/usr/local; fi
	if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then INSTALL_PREFIX=/usr; fi

	# populate cache
	if [ ! -d ${LIBMONGOC_CACHE_DIR} ] || [ -z "$(ls -A $LIBMONGOC_CACHE_DIR)" ]; then
		git clone -b ${LIBMONGOC_VERSION} https://github.com/mongodb/mongo-c-driver /tmp/libmongoc
		pushd /tmp/libmongoc
		cmake -DCMAKE_INSTALL_PREFIX:PATH=${LIBMONGOC_CACHE_DIR}
		sudo make -j8 install
		popd
	fi

	sudo cp -r ${LIBMONGOC_CACHE_DIR}/* ${INSTALL_PREFIX}

elif [[ $1 == "mongodb" ]]
then
	MONGODB_BASE="mongodb-linux-x86_64"
	if [[ "$TRAVIS_OS_NAME" == "osx" ]]; then MONGODB_BASE="mongodb-osx-ssl-x86_64"; fi

	# install mongodb
	wget http://fastdl.mongodb.org/${TRAVIS_OS_NAME}/${MONGODB_BASE}-${MONGODB_VERSION}.tgz
	mkdir mongodb-${MONGODB_VERSION}
	tar xzvf ${MONGODB_BASE}-${MONGODB_VERSION}.tgz -C mongodb-${MONGODB_VERSION} --strip-components 1
	${PWD}/mongodb-${MONGODB_VERSION}/bin/mongod --version

elif [[ $1 = "sourcery" ]]
then
	install_from_gh sourcery https://github.com/krzysztofzablocki/Sourcery/releases/download/0.16.1/Sourcery-0.16.1.zip

elif [[ $1 = "swiftlint" ]]
then
	install_from_gh swiftlint https://github.com/realm/SwiftLint/releases/download/0.35.0/portable_swiftlint.zip

elif [[ $1 = "swiftformat" ]]
then
  git clone https://github.com/nicklockwood/SwiftFormat --branch="0.40.13"
  pushd SwiftFormat
  swift build -c release
  popd

else
	echo Missing/unknown install option: "$1"
	echo Usage: "./travis_install.sh libmongoc|mongodb|sourcery|swiftlint|swiftformat"
fi
