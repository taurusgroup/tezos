.. _version-10:

Version 10.0~rc2
================

**This release candidate changes the storage backend and requires specific care when updating.**

The new storage backend uses a different file format for storing
files, which contain the block history. This new storage layer
provides a more efficient backend in terms of both performance and
storage size. As a result, the block history maintained by a Mainnet
node in full mode requires around 6GB of disk space, compared to more
than 22GB before that. In archive mode, it drops from 30 to 60GB down
to 9GB. It also reduces by a factor of more than 2 the time needed to
export and import snapshots.

This version also notably introduces an Access Control List (ACL) feature for RPCs,
a new *light* mode for the client, and a new executable
:doc:`tezos-proxy-server<../user/proxy-server>`.
See full `Changelog`_ for more details.

Update Instructions
-------------------

To update from sources::

  git fetch
  git checkout v10.0-rc2
  rm -rf _opam _build
  make build-deps
  eval $(opam env)
  make

If you are using Docker instead, use the ``v10.0-rc2`` Docker images of Tezos.

Changelog
---------

- `Version 10.0~rc2 <../CHANGES.html#version-10-0-rc2>`_
- `Version 10.0~rc1 <../CHANGES.html#version-10-0-rc1>`_

Storage Upgrade
---------------

To upgrade your node, you have two choices.

- You can use the ``storage upgrade`` command to convert your storage
  data from ``v0.0.4`` to ``v0.0.5``. This method is suitable for any
  kind of history modes. See `Upgrade Using the Upgrade Command`_

- You can import a recent snapshot to get a fresh data directory based
  on the ``v0.0.5`` storage. This method is not suitable for
  ``archive`` history modes and is recommended for ``full`` and
  ``rolling`` modes. This method is about twice as fast as using the
  upgrade command. See `Upgrade Using a Snapshot`_

Upgrade Using the Upgrade Command
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- Make sure your have at least 10GB of available disk space, as the
  upgrade command will automatically create a backup of the former
  storage (in ``~/.tezos-node/lmdb_store_to_remove``) to restore
  it if the upgrade fails.

- Stop your node.

- Compile the new version of the node (see the `Update Instructions`_).

- Run: ``./tezos-node upgrade storage`` This takes between about 40
  minutes and few hours depending on your hardware. (Docker users can
  refer to `Guide for Docker Users`_.)

- You are now ready to start your upgraded node with: ``./tezos-node run``

- If your node is running well, you can now safely remove the backup with:
  ``rm -rf ~/.tezos-node/lmdb_store_to_remove``

Upgrade Using a Snapshot
~~~~~~~~~~~~~~~~~~~~~~~~

- Export or download a snapshot (see `How to Export a Snapshot`_). No
  need to care about the snapshot's version as the ``v0.0.5`` storage
  can import legacy (``v1``) snapshots.

- Stop your node.

- Compile the new version of the node (see the `Update Instructions`_).

- Remove the ``context`` and ``store`` folders in your data directory,
  or simply move them away with: ``mv ~/.tezos-node/context
  ~/tezos-context-backup`` and: ``mv ~/.tezos-node/store
  ~/tezos-store-backup``

- Import your snapshot using: ``./tezos-node snapshot import
  snapshot.full`` This takes between about 20 minutes and one hour
  depending on your hardware.

- You are now ready to start your upgraded node with: ``./tezos-node run``

If your node is running well and you made backups of your ``context``
and ``store`` directories, you can now safely remove them with: ``rm -rf
~/tezos-context-backup ~/tezos-store-backup``

How to Export a Snapshot
~~~~~~~~~~~~~~~~~~~~~~~~

Some of the previous instructions require you to export a snapshot.
Here is how to do so. You may also just download a recent snapshot
instead.

- Get the hash of the current block using: ``./tezos-client rpc get
  /chains/main/blocks/head | grep 'hash\": \"BL'`` (or simply find the
  hash in the logs of your running node).

- Export the snapshot with: ``./tezos-node snapshot --block <BLOCK>
  export snapshot.full`` (replace ``<BLOCK>`` with the hash of the
  current block).

If you do not specify ``--block`` the snapshot will be less recent and
thus your node will have to spend some time to catch up.

Guide for Docker Users
~~~~~~~~~~~~~~~~~~~~~~

Docker users can run the upgrade procedure using the
``tezos-upgrade-storage`` command as follows (replace ``docker-node`` by
the name of your Docker volume)::

    docker run -v docker-node:/var/run/tezos/node -it registry.gitlab.com/tezos/tezos:amd64-v10.0-rc1 tezos-upgrade-tezos

Users who use ``storage-docker-manager.sh`` can simply execute the built-in
upgrade command, such as (for Mainnet): ``./mainnet.sh node upgrade``

If the upgrade is successful and your node is running well, you can
now safely remove the backup of the previous store version.
To do so, start a shell using (replace ``docker-node`` by
the name of your Docker volume)::

    docker run -v docker-node:/var/run/tezos/node -it --entrypoint /bin/sh registry.gitlab.com/tezos/tezos/debug:amd64-v10.0-rc1

Once you have a shell, remove the backup using::

    rm -rf /var/run/tezos/node/data/lmdb_store_to_remove

and close the shell with ``exit`` or Ctrl+D.
