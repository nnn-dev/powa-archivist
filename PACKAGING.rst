====
Goal
====

This is a experiment to deliver easily **powa-archivist** packages for Debian or Redhat (Centos).

THESE PACKAGES ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

=====================
How to use packages ?
=====================

1. Look on ``packages`` directory for your distribution and os architecture.
2. Retrieve the files (.deb or .rpm) on your machine
3. Deploy it

On Debian : 

.. code-block:: bash

 apt-get install postgresql-9.4 postgresql-contrib-9.4
 dpkg -i *.deb
 
On RedHat :
 
.. code-block:: bash

 yum install *.rpm

4. Configure your postgres instance (see http://powa.readthedocs.org/en/latest/) :

Modify postgresql.conf 

.. code-block:: ini
 
 shared_preload_libraries='pg_stat_statements,powa,pg_stat_kcache,pg_qualstats'

Restart postgresql

Add powa databse and extension.

.. code-block:: bash

 psql -U postgres 
 Type "help" for help.
 
 postgres=# CREATE DATABASE powa;
 CREATE DATABASE
 postgres=# CREATE EXTENSION pg_stat_statements;
 CREATE EXTENSION
 postgres=# CREATE EXTENSION btree_gist;
 CREATE EXTENSION
 postgres=# CREATE EXTENSION pg_qualstats;
 CREATE EXTENSION
 postgres=# CREATE EXTENSION pg_stat_kcache;
 CREATE EXTENSION
 postgres=# CREATE EXTENSION powa;
 CREATE EXTENSION
 postgres=# \q

5. Install **powa-web** if you want

6. It is done

===============
Made packages ?
===============

The principe
------------

1. ``createpackageon.sh`` launch a container environment with docker or Vagrant
2. On container: ``provision.sh`` is executed (see ``buildscripts\provision.sh``)
3. Install all the stuff for building package (postgresql devel, fpm)
4. Build package with fpm (https://github.com/jordansissel/fpm) for pg_qualstats, pg_stat_kcache, powa-archivist
5. Copy package outside the container (on ``packages`` directory)
6. Delete container environment
7. Recreate container environment
8. On container: ``provision.sh --test`` is executed (see ``buildscripts\provision.sh``) 
9. Install only the postgresql stuff 
10. Deploy packages
11. Configure postgresql
12. Launch postgresql
13. Test powa-archivist

Images used to create packages
------------------------------

:32bits VAGRANT:
 * puppetlabs/debian-7.8-32-nocm
 
:32bits DOCKER:
 * toopher/centos-i386:centos6

:64bits DOCKER:
 * centos:6
 * centos:7
 * debian:wheezy
 * debian:jessie
 * ubuntu:14.04.2
 
How to make others packages
---------------------------

:Prerequisites:

* You must have *docker* or *Vagrant*.
* You must have the name of a *docker image* (https://registry.hub.docker.com/) or *Vagrant base* (https://atlas.hashicorp.com/boxes/search?vagrantcloud=1)
* You must know if 32 bits or 64 bits

:Usage:

.. code-block:: bash

 createpackageon.sh [-D|-V] [--linux32] [--keep] image
 
 -D           use docker (default)
 -V           use Vagrant
 --linux32    indicate this for 32 bits image
 --keep       useful when debugging. The container is not remove after execution.
 image        shortname (docker), base name (Vagrant) or base url (Vagrant)

To use vagrant, this script create a Vagrantfile on the current directory. So you cannot build several packages at same time.
 
:How the investigate (debugging):

Use ``--keep`` option. After you can launch a shell on the container.

On docker:

.. code-block:: bash

 docker exec -t -i containerid /bin/bash

 containerid is the id indicated by the script (something like ``buildpowa2_XXXXXXXXXXXXXXXXXXXXXXXX``)

On Vagrant: 

.. code-block:: bash
 
 vagrant ssh
 
The port 8888 on the container (used by powa-web) are binded with a port of the host.

On docker to know the port to use:

.. code-block:: bash

 docker ps

On vagrant the 8888 port is used but change if it is used.

After, you must delete the container

On docker

.. code-block:: bash

 docker rm containerid
 
 containerid is the id indicated by the script (something like ``buildpowa2_XXXXXXXXXXXXXXXXXXXXXXXX``)

On vagrant

.. code-block:: bash

 vagrant destroy
