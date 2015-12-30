#!/bin/bash -ex

source config
hook_file=$(pwd)/commit-msg

BRANCH_NAME=sync_transifex

try_download_CL()
{
    prj=$1
    json=$(curl -s "https://$GERRIT_HOST/changes/?q=topic:$BRANCH_NAME+project:$prj+status:open" | sed 1d)
    len=$(echo $json | jq '.|length')
    case $len in
	0)
	    echo "there hasn't any CL exists for $prj"
	    return 1
	    ;;
	1)
	    CL=$(echo $json | jq '.[0]._number')
	    echo "there found an exists CL $CL, using this CL to update POs"
	    git review -d $(echo $json | jq '.[0]._number')
	    return 0
	    ;;
	*)
	    echo "Two many exists CLs for $prj, do nothing" >> error.log
	    return 1
	    ;;
    esac
}

download()
{
    prj=$1
    branch=$2
    echo "download po from $prj $branch ..."
    savedDir=$(pwd)
    tmpDir="/tmp/sync-po-$prj"
    gitDir="ssh://$GERRIT_USER@$GERRIT_HOST:29418/$prj"
    echo "$gitDir"
    rm -rf $tmpDir
    git clone $gitDir $tmpDir
    cd $tmpDir
    git config user.email "transifex@linuxdeepin.com"
    git config user.name "transifex"
    cp $hook_file .git/hooks

    git checkout $branch
    if [ $? -ne 0 ]; then
	cd $savedDir
	rm -rf $tmpDir
	return
    fi

    if try_download_CL $prj; then
        tx pull -f -a
        git add *.po
        git commit -a --amend --no-edit
    else
        git checkout -b "$BRANCH_NAME"
        tx pull -f -a
        git add *.po
        git commit -a -m "auto sync po files from transifex"
    fi

    git remote set-url origin $gitDir
    git review -f $branch
    cd $savedDir
    rm -rf $tmpDir
}

init()
{
    # git-review
    mkdir -p ~/.config/git-review
    echo "[gerrit]
defaultremote = origin" > ~/.config/git-review/git-review.conf

    # transifex
    tx init --host=${TX_HOST} --user=${TX_USER} --pass=${TX_PASSWORD}
}

upload()
{
    #branch=$(get_work_branch $1)
    prj=$1
    branch=$2
    savedDir=$(pwd)
    echo "upload po to $1 $branch ..."
    tmpDir="/tmp/sync-po-$1"
    gitDir="ssh://$GERRIT_USER@$GERRIT_HOST:29418/$prj"
    echo "$gitDir"
    rm -rf $tmpDir
    git clone $gitDir $tmpDir
    cd $tmpDir

    git checkout $branch
    if [ $? -ne 0 ]; then
        cd $savedDir
        rm -rf $tmpDir
        return
    fi

    tx push -s
    cd $savedDir
    rm -rf $tmpDir
}

usage() { echo "Usage: $0 [ -u | -d ] gerrit_project [gerrit_branch] " 1>&2; exit 1; }

init

declare action
while getopts "ud" o; do
    case "${o}" in
	u)
	    action="upload"
	    ;;
	d)
	    action="download"
	    ;;
	*)
	    usage
	    ;;
    esac
done
shift $((OPTIND-1))

echo Action $action
if [ ! -n "$action" ]; then
    echo "action must be specified" 1>&2; exit 1
fi

case $action in
    "upload")
	if [ ! -n "$1" ]; then
        echo "project name must be specified" 1>&2; exit 1
	else
	    upload $1 $2
	fi
	;;
    "download")
	if [ ! -n "$1" ]; then
        echo "project name must be specified" 1>&2; exit 1
	else
	    download $1 $2
	fi
	;;
esac
