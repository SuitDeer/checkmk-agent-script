# checkmk-agent-script
Install, update and remove checkmk Agent on Windows or Linux with automated scripts.
Furthermore these scripts are adding or removing the client-object in the checkmk-Server (via API calls).

## Prerequisites
1. No pending changes open in checkmk instance before running a script.
2. Open web interface from checkmk server and log-in with admin account.
3. Create a new User (if not already existent) with the following name: `automation`
4. Asign the Role `Administrator` to the `automation`-User.

   ![automation user](images/automation%20user%20(assign%20Administrator%20role).png)

---

## Linux
1. For all scripts please edit the following variuables:
   - **SERVER_NAME**: IP-Address or DNS name of your checkmk-Server.
   - **SITE_NAME**: Site where you want to add the host/client-system to.

     More info what a site is in checkmk: [https://docs.checkmk.com/latest/en/intro_setup.html#create_site](https://docs.checkmk.com/latest/en/intro_setup.html#create_site)

   - **PASSWORD**: Password of the newly created or existent user `automation`

2. After creating or downloading the script please make it executable:

   ```bash
   chmod +x <SCRIPTNAME.sh>
   ```

3. Execute the script with root-rights:

   ```bash
   sudo ./<SCRIPTNAME.sh>
   ```

**All scripts are running ca. 3 minutes (do to some API calls.) !!!**

### [install-checkmk.sh](install-checkmk.sh)

### [uninstall-checkmk.sh](uninstall-checkmk.sh)

### [update-checkmk.sh](update-checkmk.sh)

---

## Windows

1. For all scripts please edit the following variuables:
   - **SERVER_NAME**: IP-Address or DNS name of your checkmk-Server.
   - **SITE_NAME**: Site where you want to add the host/client-system to.

     More info what a site is in checkmk: [https://docs.checkmk.com/latest/en/intro_setup.html#create_site](https://docs.checkmk.com/latest/en/intro_setup.html#create_site)

   - **PASSWORD**: Password of the newly created or existent user `automation`

2. Execute the script with administrator-rights:

   ```powershell
   powershell ./<SCRIPTNAME.ps1>
   ```

**All scripts are running ca. 3 minutes (do to some API calls.) !!!**

### [install-checkmk.ps1](install-checkmk.ps1)

### [uninstall-checkmk.ps1](uninstall-checkmk.ps1)

### [update-checkmk.ps1](update-checkmk.ps1)

---
