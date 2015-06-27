#!/bin/sh
set -e

# variables
# Version of Postgresql
pgversion='9.4'
# Source +  package_name + package_version
# . pg_qualstats
pg_qualstats_source='https://github.com/dalibo/pg_qualstats/archive/0.0.6.zip'
pg_qualstats_name="postgresql-${pgversion}-pg-qualstats"
pg_qualstats_version='0.0.4'
# . pg_stat_kcache
pg_stat_kcache_source='https://github.com/dalibo/pg_stat_kcache/archive/REL2_0_2.zip' 
pg_stat_kcache_name="postgresql-${pgversion}-pg-stat-kcache"
pg_stat_kcache_version="2.0.2"
# . powa-archivist
#pg_powa_archivist_source='https://github.com/dalibo/powa-archivist/archive/REL_2_0_0.zip'
pg_powa_archivist_source='https://github.com/dalibo/powa-archivist/archive/master.zip'
pg_powa_archivist_name="postgresql-${pgversion}-powa-archivist"
pg_powa_archivist_version="2.0.1.$(date +%s)"

# Download a file from url
# $1 = source
# $2 = dest
downloadfile()
{
 if [ ! -f "$2" ]; then
  wget -O "$2" "$1"
 fi
}

# Indicate if redhat
is_redhat()
{
 test -f /etc/redhat-release
}

# Install a package
# $1 = .deb
# or
# $* = name (in apt)
installpackage()
{
 if [ "$(basename $1 .rpm)" != "$(basename $1)" ]; then
  /bin/rpm -Uvh --replacepkgs "$@"
 elif [ "$(basename $1 .deb)" != "$(basename $1)" ]; then
  DEBIAN_FRONTEND=noninteractive /usr/bin/dpkg --force-confold -i "$@"
 elif is_redhat; then
  /usr/bin/yum install -y "$@"
 else
  DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -f -q -y -o 'DPkg::Options::=--force-confold' --force-yes "$@"
 fi
}

# build a package from a tar.gz on web
# $1 = source
# $2 = package name
# $3 = package version
# $4 = workdir
# $5 = destdir
# [--beforebuild function]
# $* = fpm options
build()
{
  if is_redhat; then
   installpackage 'rpm-build'
  fi
  source=$1
  pkgname=$2
  pkgversion=$3
  workdir=$4
  destdir=$5
  shift 5
  if $(echo $source | grep -q '.tar.gz$'); then
	ext='.tar.gz'
  else
    ext='.zip'
  fi
  name="$(basename $source $ext)"
  createdir ${workdir}/${name}
  createdir ${workdir}/${name}-rootfs
  downloadfile "$source" ${workdir}/${name}/${name}${ext}
  cd ${workdir}/${name}
  if [ "${ext}" = '.tar.gz' ]; then
   tar xzf ${name}.tar.gz
  else
   unzip ${name}.zip
  fi
  cd ->/dev/null
  dir=$(find ${workdir}/${name} -maxdepth 1 -type d | tail -n 1)
  cd $dir
  if [ "$1" = '--beforebuild' ]; then
   "$2"
   shift 2
  fi
  if is_redhat; then
   opt='-R'
   type='rpm'
  else
   opt='-D'
   type='deb'
  fi
  [ -x ./configure ] && ./configure
  make
  make install DESTDIR=${workdir}/${name}-rootfs
  if [ "$(ls -1 ${workdir}/${name}-rootfs | wc -l)" -eq '0' ]; then
   echo "Error no file installed" >&2
   return 1
  fi
  fpm -f -s dir -t $type -n ${pkgname} -v ${pkgversion} -C ${workdir}/${name}-rootfs -m "--maintainer=${MAINTAINER}" "$@"
  if is_redhat; then
   cp *.rpm ${destdir}/
  else
   cp *.deb ${destdir}/  
  fi
  cd ->/dev/null
  rm -Rf ${workdir}/${name}
  rm -Rf ${workdir}/${name}-rootfs
}

# Clean env
cleanenv()
{
 if is_redhat; then
  installpackage 'redhat-lsb-core' 'which'
 else
  apt-get update -y </dev/null
  installpackage debconf-utils
  apt-get install -f -y </dev/null
  apt-get autoremove -y </dev/null
  installpackage lsb-release
  arc='amd64'
  if [ "$(arch)" = 'i686' ]; then
   arc='i386'
  fi
  maj=$(lsb_release -rs | cut -f1 -d'.')
  if [ "$maj" -ge '7' ]; then
   libssl='libssl1.0.0'
  elif [ "$maj" -eq '6' ]; then
   libssl='libssl0.9.8'
  else
   libssl=''
  fi
  if [ -n "$libssl" ]; then
	echo "${libssl}:${arc} ${libssl}/restart-services string" | debconf-set-selections
   installpackage $libssl
  fi
 fi
}

# Create a directory
# $1 = dir
createdir()
{
 if [ ! -d "$1" ]; then
  mkdir -p "$1"
 fi
}

# Install postgresql on debian
# $1 = version
# [--devel]
installpg_debian()
{
  installpackage 'ca-certificates'
  if [ ! -f '/etc/apt/sources.list.d/pgdg.list' ]; then
   echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
  fi
  if ! apt-key export ACCC4CF8 2>/dev/null | grep -q KEY; then
   downloadfile 'https://www.postgresql.org/media/keys/ACCC4CF8.asc' '/tmp/ACCC4CF8.asc'
   apt-key add /tmp/ACCC4CF8.asc
   apt-get update -y </dev/null
  fi
  # install packages
  if [ "$2" = '--devel' ]; then
	installpackage "postgresql-$1" "postgresql-contrib-$1" "postgresql-server-dev-$1" "postgresql-doc-$1"
  else
    installpackage "postgresql-$1" "postgresql-contrib-$1"
  fi
}

# Install postgresql on redhat
# $1 = version
# [--devel]
installpg_redhat()
{
  pgversion2=$(echo $1 | tr -d '.')
  # retrieve repo
  downloadfile http://yum.postgresql.org/repopackages.php /tmp/repo.html
  maj=$(lsb_release -rs | cut -f1 -d'.')
  arch=$(uname -m)
  if [ "$(echo $arch | cut -c1)" = 'i' ]; then
   arch="i[36]86"
  fi
  repourl=$(grep "$1" /tmp/repo.html | grep -i "$(lsb_release -is)"  | grep -- "$arch" | grep -- "-$maj-" | sed -e '1,$s|^.*href="||g' -e '1,$s|.rpm".*$|.rpm|g')
  yum localinstall -y "http://yum.postgresql.org/$repourl"
  yum makecache
  # install packages
  if [ "$2" = '--devel' ]; then
	installpackage "postgresql$pgversion2-server" "postgresql$pgversion2-contrib" "postgresql$pgversion2-devel"	"postgresql$pgversion2-docs"
  else
    installpackage "postgresql$pgversion2-server" "postgresql$pgversion2-contrib"
  fi
  # create db
  service postgresql-$1 initdb
  service postgresql-$1 restart
  export PATH="/usr/pgsql-$1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/bin:$PATH"
}

# Install postgresql
# $1 = version
# [--devel]
installpg()
{
 if is_redhat; then
  installpg_redhat "$@"
 else
  installpg_debian "$@"
 fi
}

patch_pg_qualstats()
{
mv doc/README.md doc/README.pg_qualstats.md
sed -i '1,$s|^DOCS *=.*$|DOCS = doc/README.pg_qualstats.md|g' Makefile
}

patch_powa_archivist()
{
mv README.md README.powa-archivist.md
sed -i '1,$s|^DOCS *=.*$|DOCS = README.powa-archivist.md|g' Makefile
}
  
create()
{

# construct final build directory
destdir="/build/${osname}"
workdir='/tmp/powa-build'

# 0. Init

installpackage wget tar unzip 

if is_redhat; then
 installpackage 'ruby' 'ruby-devel' 'gcc' 'rubygems' 
else
 installpackage 'ruby' 'ruby-dev' 'gcc' 'make'
 [ ! -x /usr/bin/gem ] && installpackage 'rubygems'
fi
[ ! -x /usr/bin/fpm ] && gem install --no-rdoc --no-ri fpm 


createdir $workdir

createdir $destdir

rm -Rf $destdir/*

# 1. Install postgresql

installpg $pgversion --devel

# 2. Compile pg_qualstats

build "$pg_qualstats_source" "$pg_qualstats_name" "$pg_qualstats_version" $workdir $destdir --beforebuild patch_pg_qualstats

# 3. Compile pg_stat_kcache

build "$pg_stat_kcache_source" "$pg_stat_kcache_name" "$pg_stat_kcache_version" $workdir $destdir

# 4. Compile Powa-archivist

if is_redhat; then
 pgversion2=$(echo "$pgversion" | tr -d '.')
 pgpackage="postgresql$pgversion2-server"
 pgcontrib="postgresql$pgversion2-contrib"
else
 pgpackage="postgresql-$pgversion"
 pgcontrib="postgresql-contrib-$pgversion"
fi
build "$pg_powa_archivist_source" "$pg_powa_archivist_name" "$pg_powa_archivist_version" $workdir $destdir --beforebuild patch_powa_archivist -d $pgpackage -d $pgcontrib


cat >${destdir}/README.rst <<_EOF_
Building on this environnement :
--------------------------------
:OS: $(lsb_release -ds) [$DOCKERIMAGE]
:POSTGRESQL: $(psql --version)

_EOF_

echo "packages copied on ${destdir}"
}

testing()
{

# construct final build directory
sourcedir="/build/${osname}"

# 0. Init

installpackage wget tar

# 1. Install postgresql

installpg $pgversion 

# 2. Install packages

if is_redhat; then
 installpackage ${sourcedir}/*.rpm
else
 installpackage ${sourcedir}/*.deb
fi

# 3. Configure postgresql

if is_redhat; then
 conf="/var/lib/pgsql/${pgversion}/data/postgresql.conf"
 pghba="/var/lib/pgsql/${pgversion}/data/pg_hba.conf"
 else
 conf="/etc/postgresql/${pgversion}/main/postgresql.conf"
 pghba="/etc/postgresql/${pgversion}/main/pg_hba.conf"
fi

cat >>$conf <<_EOF_
shared_preload_libraries = 'pg_stat_statements,pg_qualstats,pg_stat_kcache,powa'
track_io_timing = on
_EOF_

# backup original pg_hba.conf
[ ! -f $pghba.orig ] && cp $pghba $pghba.orig
cat >$pghba <<_EOF_
local all all         trust
host  all powaweb all trust
_EOF_

# 4. Restart pg
if is_redhat; then
 service postgresql-${pgversion} restart
else
 service postgresql restart
fi
# 5. Configure extensions
if ! su - postgres -c "psql -q -P pager=off -c 'select datname from pg_catalog.pg_database;'" | grep -q powa; then 
 su - postgres -c "psql -P pager=off -c 'CREATE DATABASE powa;'"
fi
if ! su - postgres -c "psql -q -P pager=off -c 'select rolname from pg_roles;'" | grep -q powaweb; then 
 cat >/tmp/user.sql <<_EOF_
create role powaweb with superuser login password 'powaweb';
_EOF_
 su - postgres -c "psql -q -P pager=off -f /tmp/user.sql"
fi
su - postgres -c "psql -q -P pager=off -d powa -c 'CREATE EXTENSION IF NOT EXISTS btree_gist;'"
su - postgres -c "psql -q -P pager=off -d powa -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements;'"
su - postgres -c "psql -q -P pager=off -d powa -c 'CREATE EXTENSION IF NOT EXISTS pg_qualstats;'"
su - postgres -c "psql -q -P pager=off -d powa -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_kcache;'"
su - postgres -c "psql -q -P pager=off -d powa -c 'CREATE EXTENSION IF NOT EXISTS powa;'"

# 6. Test powa

# Can connect ?
su - postgres -c "psql -q -P pager=off -c 'select 1;'"

# I don't know how to test if powa works. 
# Do a pgbench and test if statements are stored.
if is_redhat; then
 pgbench="/usr/pgsql-$pgversion/bin/pgbench"
else
 pgbench='pgbench'
fi
su - postgres -c "$pgbench -i postgres"
su - postgres -c "$pgbench -c10 -j5 -T10 -v postgres"
cat >/tmp/check.sql <<_EOF_
select count(*) from powa_statements where query like 'insert into pgbench_%'
_EOF_
nb="$(su - postgres -c "psql -q -P pager=off -t -d powa -f /tmp/check.sql" | head -n 1)"
if [ -z "$nb" ]; then
 echo 'ERROR: pgbench is not stored' >&2
 exit 1
fi
if [ "$nb" -eq '0' ]; then
 echo 'ERROR: pgbench is not stored' >&2
 exit 1
fi

# 7. Testing via powa-web

if is_redhat; then
 installpackage epel-release
 installpackage python-pip libpqxx-devel python-devel gcc
else
 installpackage python-pip libpq-dev python-dev
fi

cd /tmp
pip install powa-web

cat >/etc/powa-web.conf  <<_EOF_
servers={
  'main': {
    'host': 'localhost',
    'port': '5432',
    'database': 'powa'
  }
}
cookie_secret="SUPERSECRET_THAT_YOU_SHOULD_CHANGE"
_EOF_

echo "launching powa-web..."
nohup powa-web &

sleep 2
date1=$(date --rfc-3339=seconds | sed -e 's|+.*$|%252B0000|g' -e 's|:|%253A|g' -e 's| |%2B|g')
#can connect ?
wget -O /dev/null --save-cookies cookies.txt \
 --post-data 'username=powaweb&password=powaweb&server=main' \
 'http://localhost:8888/login/'
date2=$(date --rfc-3339=seconds | sed -e 's|+.*$|%252B0000|g' -e 's|:|%253A|g' -e 's| |%2B|g')
#can have info ?
wget -O /dev/null --load-cookies cookies.txt \
 --post-data 'username=powaweb&password=powaweb&server=main' \
 "http://localhost:8888/login/?next=%2Fmetrics%2Fdatabases_globals%2F%3Ffrom%3D$date1%26to%3D$date2"

echo "packages tested succesfully from ${sourcedir}"

cat >>${sourcedir}/README.rst <<_EOF_
Testing on this environnement :
-------------------------------
:OS: $(lsb_release -ds) [$DOCKERIMAGE]
:POSTGRESQL: $(psql --version)

_EOF_

}

cleanenv >&2

# OS Id (Distribution + Maj version + arch)
osname=$(lsb_release -is)$(lsb_release -rs | cut -f1 -d'.')_$(arch)


if [ "$1" = '--test' ]; then
 testing
else
 create
fi
 