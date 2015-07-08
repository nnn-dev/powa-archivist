#!/bin/sh

usage()
{
cat <<_EOF_
Create packages for Powa 2.

* Create packages on docker  
Syntax : $0 -D [--linux32] [--keep] image
 --keep    = keep container after good execution 
 --linux32 = prefix with linux32 to build 32bit package (use with 32-bit docker image only)
 image     = docker image (ex: debian:wheezy)
Note: you can pass options to docker run by DOCKER_OPTS environment variable
 
* Create packages on vagrant
Syntax : $0 -V [--linux32] box
 --keep    = keep container after good execution
 --linux32 = prefix with linux32 to build 32bit package (use with 32-bit box only)
 box   = vagrant box url or simple name (ex:)
_EOF_
}

executedocker()
{
 keep=$3
 name=buildpowa2_$(echo $0$1 | md5sum | cut -f1 -d' ')
 # Remove old
 if $(docker inspect $name 1>/dev/null 2>&1); then
	docker rm -f $name
 fi	
 # Build packages
 docker run $DOCKER_OPTS -d -t --name=$name -v $D/packages:/build -v $D/buildscripts:/buildscripts -e MAINTAINER=$M -e DOCKERIMAGE=$1 $1 /bin/bash
 docker exec -t $name  $2 /buildscripts/provision.sh
 [ "$?" -ne '0' ] && exit $(fatal $name)
 docker stop ${name}
 docker rm ${name}
 # Test packages
 docker run $DOCKER_OPTS -d -t -p 8888 -P --name=$name -v $D/packages:/build -v $D/buildscripts:/buildscripts -e MAINTAINER=$M -e DOCKERIMAGE=$1 $1 /bin/bash
 docker exec -t $name  $2 /buildscripts/provision.sh --test
 [ "$?" -ne '0' ] && exit $(fatal $name)
 if [ "$keep" -ne '1' ]; then
  docker stop ${name}
  docker rm ${name}
 else
  echo "docker container ${name} ready to use"
 fi
}

executevagrant()
{
name=$(echo $1 | md5sum | cut -f1 -d' ')
type='box'
if $(echo $1 | grep -q '^https:|^http:'); then
 type='box_url'
fi

# on windows get real path
if uname -a | grep -q '^MINGW32'; then
 DR=$(cd $D; pwd -W)
else
 DR=$D
fi

#Remove old
if [ -d .vagrant ]; then
  vagrant destroy
fi

#build package
cat >Vagrantfile <<_EOF_
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure(2) do |config|
  config.vm.$type = "$1"
  config.vm.synced_folder "$DR/buildscripts", "/buildscripts"
  config.vm.synced_folder "$DR/packages", "/build"
  config.vm.provision "shell" do |s|
   s.inline = "DOCKERIMAGE='$1' $2 sh /buildscripts/provision.sh"
  end
end
_EOF_
vagrant up
vagrant provision
 [ "$?" -ne '0' ] && exit $(fatal '.')
vagrant destroy -f

cat >Vagrantfile <<_EOF_
# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure(2) do |config|
  config.vm.$type = "$1"
  config.vm.synced_folder "$DR/buildscripts", "/buildscripts"
  config.vm.synced_folder "$DR/packages", "/build"
  Vagrant.configure("2") do |config|
  config.vm.network "forwarded_port", guest: 8888, host: 8888,
    auto_correct: true
  end
  config.vm.provision "shell" do |s|
   s.inline = "DOCKERIMAGE='$1' $2 /buildscripts/provision.sh --test"
  end
end
_EOF_
vagrant up
vagrant provision
 [ "$?" -ne '0' ] && exit $(fatal '.')
if [ "$keep" -ne '1' ]; then
  vagrant destroy -f
  rm Vagrantfile
else
  echo "vagrant container ready to use"
fi
}

fatal()
{
echo "Error. Look container $1" >&2
return 1
}

if [ "$#" -eq '0' ]; then
 usage
 exit 0
fi
 shell='/bin/sh'
 mode='docker'
 keep=0;
 logfile='/dev/null'
while [ "$#" -gt '0' ]; do
 case $1 in
  '--linux32') shell='/usr/bin/linux32';;
  '-D') mode='docker';;
  '-V') mode='vagrant';;
  '--keep') keep=1;;
  '--logfile') logfile=$2; shift 1;;
  *) image=$1 ;;
 esac
 shift 1
done
# Absolute dir name
D=$(cd $(dirname $0);pwd -P)
# Maintainer email from git config
unset M
[ -n "$(git config user.email)" ] && M="$(git config user.email)"
case $mode in
'docker') executedocker $image $shell $keep | tee -a $B ;;
'vagrant') executevagrant $image $shell $keep | tee -a $B ;;
esac
