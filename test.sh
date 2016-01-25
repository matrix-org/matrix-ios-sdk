#!/bin/sh

set -e
set -x

pod update
#xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphonesimulator analyze

git -C synapse pull || git clone https://github.com/matrix-org/synapse
[ -d venv ] || virtualenv venv
. venv/bin/activate
#pip install --process-dependency-links synapse/
python synapse/synapse/python_dependencies.py | xargs -n1 pip install

basedir=`pwd`
function cleanup {
    cd $basedir
    cd synapse/demo
    ./stop.sh
}
trap cleanup EXIT

cd synapse/demo
./stop.sh || true
./clean.sh
./start.sh --no-rate-limit

cd ../..
xcodebuild -workspace MatrixSDK.xcworkspace/ -scheme MatrixSDK -sdk iphonesimulator  -destination 'name=iPhone 4s' test

