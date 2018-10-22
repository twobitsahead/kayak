
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
* FetchConfig
* Postboot
* ApplyChanges
* MakeBootable

# hvm_help.sh

* log
* HVM_Create_Diskvol
* HVM_Destroy_Diskvol
* HVM_Build_Devtree

