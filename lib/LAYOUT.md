
Notes on the layout of the files and functions that make up kayak.
Documented functions for use in kayak configuration files are emboldened.

# rpool-install.sh

* BuildBE <pool> <image>
* ApplyChanges <hostname> <tz> <lang> <kbd>
* MakeBootable <pool>

# find_and_install.sh

* Disk selection menu
* BuildRpoolOnly
* rpool-install.sh

# net_help.sh

* Ether
  * Get MAC address
* **EnableDNS**
  * resolv.conf
  * nsswitch.conf (domain + search)
* **SetDNS**
  * EnableDNS
  * resolv.conf (nameserver)
* **UseDNS**  _(deprecated)_
  * EnableDNS
  * SetDNS

# disk_help.sh

* BuildRpoolOnly <disk list>
  * zpool create
* **BuildRpool**
  * BuildRpoolOnly `$*`
  * BuildBE
* GetTargetVolSize
* GetRpoolFree
* MakeSwapDump

# install_help.sh

* ConsoleLog
* CopyInstallLog
* SendInstallLog
* OutputLog
* log
* bomb
* getvar
* **RootPW**
* SetRootPW
* ForceDHCP
* BuildBE [pool]
  * BE_Create_Root
  * BE_Receive_Image
  * BE_Mount
  * BE_SeedSMF
  * BE_LinkMsglog
  * MakeSwapDump
  * zfs destroy kayak snapshot
* FetchConfig
* MakeBootable
  * zfs set bootfs=... pool
  * beadm activate omnios
  * install boot blocks
  * bootadm update-archive
* **SetHostname**
* **AutoHostname**
* **SetTimezone**
* SetLang
* SetKeyboardLayout
* ApplyChanges [hostname] [timezone] [language] [kbd]
  * Link in SMF profiles
  * Set properties as per arguments
* **Postboot**
* Reboot
* RunInstall
  FetchConfig
  Postboot
  ApplyChanges
  MakeBootable

# xen_help.sh

* log
* SetupPart
* SetupPVGrub
* SetupZPool
* ZFSRootDS
  * set compression=on
  * zfs create ROOT
  * Does not set canmount=off
  * zfs set mountpoint=legacy ROOT
* ZFSRecvBE
  * Receive image
  * set canmount=noauto
  * set mountpoint=legacy
  * destroy kayak snapshot
* MountBE
* UmountBE
* PrepareBE
  * Generate UUID
  * activate
  * Initialise SMF seed
  * devfsadm -r
  * Link msglog
  * Grub stuff
* Xen_Customise
  * Enable root ssh lgin
  * NP root in /etc/shadow
  * Enable DNS
  * install rsync ec2-credential ec2-api-tools

