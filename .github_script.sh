#!/bin/bash

throw(){ echo $@ >&2 ; exit 1; }
          
set_image_name(){ 
  image_name="$(echo $1 | tr A-Z a-z | sed s/_\.\*//g)"
  image_name="${image_name#*/}"
  tag_name="$(echo $1 | tr A-Z a-z | sed s/\.\*_//g)"
  [ ! -z "$tag_name" ] || tag_name=null
  img_desc="${LOGIN_NAME:-coshapp}/${image_name:?no imagename}:${tag_name:?no tagname}${TAG_POSTFIX:+-$TAG_POSTFIX}" 
}

is_non_l10n_img(){
  [ "${tag_name#archlinux}" = "" ] && return 0 || return 1
}

is_non_test_no_core_img(){
  if [ -z "${TEST_TARGET}" ] || [ "${image_name}" = "core" ]; then
    return 0
  else
    return 1
  fi
}
          
build_image(){ 
  set -o xtrace
  # for autobuild and shipping on \*-test (but not core-test) branches
  if [ -n "$TEST_TARGET" ] && [ "$TEST_TARGET" = "${TEST_TARGET#core*}" ]; then 
    docker pull coshapp/core:archlinux-test
    docker pull coshapp/core:archlinux-test
    docker tag coshapp/core:archlinux-test coshapp/core:archlinux
    docker tag coshapp/core:archlinux-test coshapp/core:archlinux
  fi
  for j in $@; do
    set_image_name "$j" ;
    docker build -t ${img_desc:?img not specified} -f "$j" .;
    : ${tag_name:? tag_name not set} 
    is_non_l10n_img && is_non_test_no_core_img && {
      docker tag $img_desc ${img_desc%%:*}:latest
    } || echo skipping...
  done
}

push_image(){
  set -o xtrace
  for j in $@; do
    set_image_name "$j" ;
    : ${img_desc:?img not specified}
    docker push $img_desc
    is_non_l10n_img && is_non_test_no_core_img && {
      docker push ${img_desc%%:*}:latest
    } || echo skipping...
    # removing cache for non-core images
    if echo "$j" | grep -E \^coshapp/core: > /dev/null; then
      docker rmi $img_desc
    fi
  done
}

## filter target images for test images releases on *-test branch
filter_image(){
  if [ "${GITHUB_REF}" != "${GITHUB_REF%-test}" ]; then
    filter_target="${TEST_TARGET:-${GITHUB_REF%-test}}"
    echo */* | tr \\\  \\\n | grep -i "${filter_target##*/}"
  elif [ "${GITHUB_REF}" != "${GITHUB_REF%-script}" ]; then
    echo */* | tr \\\  \\\n | grep -i "${TEST_TARGET:-firefox}"
  else
    echo */*  ## equal to build_all
  fi
}

# build with branch filtering
filtered_build(){ build_image $(filter_image); }

# push with branch filtering
filtered_push(){ push_image $(filter_image); }

# build all images ontshot
build_all(){ build_image */*; }

push_core(){ push_image Archlinux/Core_*; }

build_core(){ build_image Archlinux/Core_*; }

# remove all image without core
rmi_without_core(){
  images="$(docker images | grep ${LOGIN_NAME:-coshapp} | awk '{print $1 ":" $2}' | grep -v ${LOGIN_NAME:-coshapp}/core:)"
  docker rmi $images
}

# variable TEST_TARGET is created from branch name
# for *-test branches, TEST_TARGET=*
# for test branch, TEST_TARET not set
set_test_target(){
  TAG_POSTFIX="test" 
  [ $# -ne 0 ] && TEST_TARGET="$1"
  [ $# -eq 0 ] && [ "${GITHUB_REF}" != "${GITHUB_REF%-test}" ] && {
    TEST_TARGET="${GITHUB_REF%-test}"
    TEST_TARGET="${TEST_TARGET##*/}"
  }
}
