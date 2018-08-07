#!/bin/bash
#
# Usage:
#   ./run.sh <function name>
#
# Examples:
#
#   ./run.sh frames      # generates .pbrt files
#   ./run.sh render-all  # generates .exr files
#   ./run.sh all-jpg     # generates .jpg files
#   ./run.sh make-video  # generate .mp4 file
#
# Quick polytope:
#
#   ./run.sh all-120-cell
#
# Bathroom:
#
# Once:
#   ./run.sh prepare-bathroom  # copy files into the right place
#
# Each time:
#   ./run.sh pbrt-bathroom
#   ./run.sh render-bathroom  # takes a couple minutes
#   ./run.sh video-bathroom
#
# Distributed bathroom rendering:
#
# Once:
#   ./run.sh copy-pbrt-bin   # copy the binary (one-time setup)o
#
#   - Check that MACHINES in this shell script is what you want.
#   - Set FRAMES_PER_MACHINE
#   ./run.sh pbrt-bathroom to generates input files
#   ./run.sh copy-bathroom-pbrt
#   ./run.sh dist-render-bathroom

set -o nounset
set -o pipefail
set -o errexit

# On local machine
mount-output() {
  # NOTE: Requires host defined in ~/.ssh/config
  sshfs broome: ~/broome

  ls ~/broome/git/pbrt-video
}

# OS X deps: https://www.xquartz.org/
# Ubuntu deps: ipython3
# TODO: Try Jupyter too

# ubuntu deps
deps() {
  # scipy: for ConvexHull
  pip3 install numpy matplotlib scipy
}

# $USER is expanded on the local machine.
readonly PBRT_REMOTE=/home/$USER/bin/pbrt 
readonly ANDY_PBRT_BUILD=~andy/git/other/pbrt-v3-build/pbrt 

pbrt() {
  if [[ "$USER" == "caroline_lin" ]]; then
    ~/pbrt-exec "$@"
  elif [[ "$USER" == "andy" ]]; then
    $ANDY_PBRT_BUILD "$@"
  else
    echo "Caroline: please only run this on Heap!"
    exit 1
  fi
}

copy-pbrt-bin() {
  local dir=$(dirname $PBRT_REMOTE)
  for machine in ${MACHINES[@]}; do
    ssh $machine "mkdir -v -p $dir"
    scp $ANDY_PBRT_BUILD $machine:$dir
  done
}

render-simple() {
  local src=${1:-scenes/killeroo-simple.pbrt}
  pbrt $src
  #../other/pbrt-v3-build/pbrt $src
}

render-hi() {
  local src=${1:-../other/pbrt-v3-scenes/contemporary-bathroom/contemporary-bathroom.pbrt}
  pbrt --quick $src
  #../other/pbrt-v3-build/pbrt $src
}

clean() {
  rm -v _out/pbrt/* _out/exr/* _out/jpg/*
}

frames() {
  mkdir -p _out/{pbrt,exr,jpg}

  local NUM_FRAMES=10

  # has to be in scenes to include the geometry file
  local out_dir=_out
  ./frames.py $NUM_FRAMES $out_dir
  ls -l $out_dir/pbrt
}

# Oops has to be in original dir
render-killeroo-frames() {
  # TODO: xargs

  # Or just use a single command to share?
  # Why does this segfault?
  # pbrt does seem to accept multiple args.
  #pbrt scenes/k-*.pbrt
  #return

  for input in _out/pbrt/k-*.pbrt; do
    pbrt $input
  done
}

# On local machine

exr-to-jpg() {
  local exr=$1
  local name=$(basename $exr .exr)
  convert $exr _out/jpg/${name}.jpg
}

readonly NPROC=$(( $(nproc) - 1 ))

all-jpg() {
  echo _out/exr/k-*.exr | xargs --verbose -n 1 -P $NPROC -- $0 exr-to-jpg
}


# NOTE: Tried 'convert' from imagemagick but it didn't seem to work

# https://superuser.com/questions/249101/how-can-i-combine-30-000-images-into-a-timelapse-movie

join-frames() {
  local out=$1
  shift

  # 41.66 ms is 24 fps
  # ticks are 10ms, so delay is 4.166
  #local delay=4.1666
  local delay=10

  #local delay=50

  time convert -delay $delay -quality 95 "$@" $out
  echo "Wrote $out"
}

make-video() {
  # with imagemagick
  # http://jupiter.ethz.ch/~pjt/makingMovies.html 
  time convert -delay 6 -quality 95 _out/jpg/k-*.jpg _out/movie.mp4
  echo "Wrote $PWD/_out/movie.mp4"
}

ply-demo() {
  #local ply=_out/demo.ply
  local ply=render/temp.ply
  ./polytope.py pbrt $ply 5 3
  #pbrt $ply
  pbrt render/convex_render.pbrt
}

# TODO: Parameterize over different polytopes!  Give them different names.
gen-pbrt-4d() {
  local sch=${1:-'5-3-3'}  # schlafli number
  local num_frames=${2:-48}

  local out_dir=_out/4d/$sch
  mkdir -p $out_dir
  rm -v -f $out_dir/*

  # split 5 3 3 into 5 3 3
  local -a sch_array=( ${sch//-/ } )
  NUM_FRAMES=$num_frames \
    ./polytope.py pbrt $out_dir ${sch}_frame%02d "${sch_array[@]}"

  ls -l $out_dir
}

gen-all-4d() {
  # This one gives a Convex Hull error
  #gen-pbrt-4d 3-3-3
  gen-pbrt-4d 4-3-3
  gen-pbrt-4d 3-4-3
  gen-pbrt-4d 3-3-4
  gen-pbrt-4d 5-3-3
  gen-pbrt-4d 3-3-5
}

render-4d() {
  # 3:38 for 5 low quality videos
  time for input in _out/4d/*/*.pbrt; do
    pbrt $input
  done
}

video-4d() {
  for dir in _out/4d/*; do
    if ! test -d $dir; then
      continue
    fi
    local name=$(basename $dir)
    local out=_out/4d/$name.mp4
    join-frames $out $dir/*.png 
    echo "Wrote $out"
  done
}

# A particular one

gen-120-cell() {
  gen-pbrt-4d 5-3-3 20
}

# 1:01 at low quality
render-120-cell() {
  rm -v -f _out/4d/5-3-3/*.png
  time for input in _out/4d/5-3-3/*.pbrt; do
    pbrt $input
  done
}

video-120-cell() {
  join-frames _out/4d/5-3-3.mp4 _out/4d/5-3-3/*.png 
}

all-120-cell() {
  gen-120-cell
  render-120-cell
  video-120-cell
}

readonly BATHROOM_OUT=_out/4d/bathroom

# Put everything in the right dirs.
prepare-bathroom() {
  rm -r -f $BATHROOM_OUT
  mkdir -p $BATHROOM_OUT

  for dir in scenes/contemporary-bathroom/{geometry,spds,textures,bsdfs}; do
    cp -r $dir $BATHROOM_OUT
  done

  cp scenes/contemporary-bathroom/contemporary_bathroom.blend $BATHROOM_OUT

  cp scenes/contemporary-bathroom/geometry.pbrt $BATHROOM_OUT/geometry
  cp scenes/contemporary-bathroom/materials.pbrt $BATHROOM_OUT/geometry

  ls -l $BATHROOM_OUT
}

#readonly -a MACHINES=( {spring,mercer,crosby}.cluster.recurse.com )
readonly -a MACHINES=( {spring,mercer}.cluster.recurse.com )
readonly NUM_MACHINES=${#MACHINES[@]}

readonly FRAMES_PER_MACHINE=10
readonly NUM_BATHROOM_FRAMES=$(( FRAMES_PER_MACHINE * NUM_MACHINES ))

pbrt-bathroom() {
  local out_dir=$BATHROOM_OUT
  rm -v -f $out_dir/frame*.{ply,pbrt}

  NUM_FRAMES=$NUM_BATHROOM_FRAMES \
  FRAME_TEMPLATE=4d-contemporary-bathroom.template \
    ./polytope.py pbrt $out_dir "frame%03d" 5 3 3

  ls $out_dir
}

copy-bathroom-pbrt() {
  local i=0
  for machine in "${MACHINES[@]}"; do
    echo "=== $machine"

    ssh $machine "mkdir -p /home/$USER/pbrt-video/bathroom/"
    rsync --archive --verbose \
      $BATHROOM_OUT/ "$machine:/home/$USER/pbrt-video/bathroom/"

    # So we can run ./run.sh dist-render-bathroom on each machine
    rsync --archive --verbose \
      $0 "$machine:/home/$USER/pbrt-video/"

    echo $i > worker-id.txt

    rsync --archive --verbose \
      worker-id.txt "$machine:/home/$USER/pbrt-video/"

    (( i++ )) || true  # bash annoyance with errexit!
  done
}

should-render-frame() {
  local path=$1
  local worker_id=$2

  return 0
}

dist-render-bathroom() {
  local worker_id=$(cat worker-id.txt)
  time for input in ~/pbrt-video/bathroom/frame*.pbrt; do
    if should-render-frame $input $worker_id; then
      $PBRT_REMOTE $input
    fi
  done
}

# 1:01 at low quality
render-bathroom() {
  rm -v -f $BATHROOM_OUT/*.png
  time for input in $BATHROOM_OUT/frame*.pbrt; do
    pbrt $input
  done
}

video-bathroom() {
  join-frames _out/4d/bathroom.mp4 $BATHROOM_OUT/*.png 
}

"$@"
