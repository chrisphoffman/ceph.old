#!/bin/bash
set -xe

environment(){
if [ ! -f site-a.conf ] && [ ! -L site-a.conf ]; then
	ln -s run/site-a/ceph.conf site-a.conf
fi

if [ ! -f site-b.conf ] && [ ! -L site-b.conf ]; then
	ln -s run/site-b/ceph.conf site-b.conf
fi

}
stop(){
../src/mstop.sh site-a
../src/mstop.sh site-b
killall rbd-mirror || true
killall rbd-mirror || true
killall rbd-mirror || true
}
start(){
#setup site-a and site-b
#MON=1 OSD=1 MGR=3 MDS=0 RGW=0 ../src/mstart.sh site-a --short --new --without-dashboard -o "
#mirroring_debug_snap_copy_delay = 9876
#debug rbd = 20
#debug rbd_mirror = 30
#rbd_default_features = 61"
#MON=1 OSD=1 MGR=3 MDS=0 RGW=0 ../src/mstart.sh site-b --short --new -x --localhost --bluestore --without-dashboard

#MON=1 OSD=1 MGR=1 MDS=0 RGW=0 ../src/mstart.sh site-a --short -n -d -o "
#rbd_default_features = 61" --without-dashboard
MON=1 OSD=1 MGR=1 MDS=0 RGW=0 ../src/mstart.sh site-a --short -n -d -o "
mirroring_debug_snap_copy_delay = 9876
debug rbd = 0
debug rbd_mirror = 0
rbd_default_features = 61" --without-dashboard
#MON=1 OSD=1 MGR=1 MDS=0 RGW=0 ../src/mstart.sh site-b --short -n -d -o "
#rbd_default_features = 61" --without-dashboard
MON=1 OSD=1 MGR=1 MDS=0 RGW=0 ../src/mstart.sh site-b --short -n -d -o "
mirroring_debug_snap_copy_delay = 9876
mirroring_debug_snap_copy_delay = 9876
debug rbd = 20
debug rbd_mirror = 20
rbd_default_features = 61" --without-dashboard
#client, rados, optracker,  tp, mgr, mgrc, eventtrace
#setup pool
./bin/ceph --cluster site-a osd pool create pool1
./bin/rbd --cluster site-a pool init pool1
 
./bin/ceph --cluster site-b osd pool create pool1
./bin/rbd --cluster site-b pool init pool1

#set to image mirror
./bin/rbd --cluster site-a mirror pool enable pool1 image

#create image
###./bin/rbd --cluster site-a create image1 --size 1000 --pool pool1  --image-feature exclusive-lock,journaling
#./bin/rbd --cluster site-b create image1 --size 1000 --pool pool1  --image-feature exclusive-lock,journaling

#create token
./bin/rbd --cluster site-a mirror pool peer bootstrap create pool1 | tail -n 1 > token

#import token
./bin/rbd --cluster site-b mirror pool peer bootstrap import --site-name site-b pool1 token

#setup peering
#./bin/rbd --cluster site-a mirror pool peer add pool1 client.remote@remote
#./bin/rbd --cluster site-b mirror pool peer add pool1 client.local@local

#start rbd-mirror
#./bin/rbd-mirror --cluster site-a --debug-rbd 20 --debug-rbd-mirror 20
#./bin/rbd-mirror --cluster site-b --debug-rbd 20 --debug-rbd-mirror 20
./bin/rbd-mirror --cluster site-a --rbd-mirror-delete-retry-interval=5 --rbd-mirror-image-state-check-interval=5 --rbd-mirror-journal-poll-age=1 --rbd-mirror-pool-replayers-refresh-interval=5 --debug-rbd=20 --debug-rbd_mirror=40 --daemonize=true
./bin/rbd-mirror --cluster site-b --rbd-mirror-delete-retry-interval=5 --rbd-mirror-image-state-check-interval=5 --rbd-mirror-journal-poll-age=1 --rbd-mirror-pool-replayers-refresh-interval=5 --debug-rbd=20 --debug-rbd-mirror=20 --daemonize=true
#./bin/rbd-mirror --cluster site-b --rbd-mirror-delete-retry-interval=5 --rbd-mirror-image-state-check-interval=5 --rbd-mirror-journal-poll-age=1 --rbd-mirror-pool-replayers-refresh-interval=5 --daemonize=true
#./bin/rbd-mirror -c site-b.conf
#./bin/rbd-mirror --cluster site-b --rbd-mirror-delete-retry-interval=15 --rbd-mirror-image-state-check-interval=15 --rbd-mirror-journal-poll-age=1 --rbd-mirror-pool-replayers-refresh-interval=15 --debug-rbd=20 --debug-journaler=40 --debug-rbd-mirror=20 --debug-rbd-mirror=20 --debug-ms=20 --debug-objecter=20 --debug-timer=20 --daemonize=true


#enable mirroring on image
###./bin/rbd --cluster site-a mirror image enable pool1/image1

#verify peering:
########./bin/rbd --cluster site-a mirror pool info pool1
#./bin/rbd --cluster site-a mirror pool status pool1

#set image snapshot
###./bin/rbd --cluster site-a mirror image enable pool1/image1 snapshot

#set a schedule
###./bin/rbd mirror snapshot schedule add --pool pool1 --image image1 1m  --cluster site-b

#./bin/ceph --cluster site-b config set global debug_rbd 20
#./bin/ceph --cluster site-b config set global debug_rbd_mirror 20
#./bin/ceph --cluster site-b config set client.rbd-mirror.a debug_ms 20
#./bin/ceph --cluster site-b config set client.rbd-mirror.a log_file /sdb/choffman/code/ceph/build/run/site-b/out/log1.log
#./bin/ceph --cluster site-b config set client.rbd-mirror-peer debug_ms 20
#./bin/ceph --cluster site-b config set client.rbd-mirror-peer log_file /sdb/choffman/code/ceph/build/run/site-b/out/log2.log

}

NUM_ARGS=`echo "$@" | awk '{print NF}'`
ACTION=$1
if [ "$ACTION" == "start" ]; then
	echo setting up environment
	environment
	echo start
	start
elif [ "$ACTION" == "stop" ]; then
	echo stop
	stop
else
	echo "Option not recognized"
fi
