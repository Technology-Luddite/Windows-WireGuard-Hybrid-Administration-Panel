
# WireGuard Hybrid Administration Panel (v1.0)

Windows Server serves as a powerful backbone for enterprise workloads, but deploying a secure, headless WireGuard VPN tunnel on it natively can be a friction-heavy process. Out of the box, setting up WireGuard requires manual interface plumbing, complex registry overrides for routing, and the tedious management of tracking client configuration files across separate text assets.

The **WireGuard Hybrid Administration Panel** acts as an administrative surgical tuning kit. Rather than making permanent, destructive changes to your server's infrastructure, this framework unifies deployment, routing topology, and peer token signing into a single graphical workspace. It works directly with WireGuard’s native kernel driver layer and configuration engines, ensuring your VPN infrastructure boots up as a native system service before any user even logs into the server console.

---

## Deployment & Folder Directory Rules

Unlike standard consumer software that abstracts file management into hidden databases, this tool relies on strict, predictable directory paths to maintain state. 

### The Engine Storage Rules
* **The Server Root Engine:** The script creates a hard secured infrastructure vault at `C:\ProgramData\WireGuard\`. This is where the core configuration (`wg0.conf`) and internal runtime state JSON files live.
* **The App & Client Workspace:** The script dynamically looks for a folder named `Clients` sitting in the **exact same directory** where the `.ps1` or compiled `.exe` application itself is currently running. 
* **The Portability Catch:** You can place the application workspace file inside **any folder name or directory path you want** upon initial installation. However, once the application is configured and client generations begin, **it must remain in that exact path**. Moving the executable or script after initialization will break the path mapping engine, forcing the tool to spin up a blank, isolated `Clients` folder in the new location.

---

## Technical Initialization: Script vs. Self-Compiled Binary

To maintain absolute transparency in enterprise settings, administrators do not have to trust pre-compiled binaries from the internet. The raw script code allows for full security auditing and can be run natively or compiled internally.

### Method A: Running Natively as a PowerShell Script
1. Right-click the Windows Start button and choose **PowerShell (Admin)** or **Terminal (Admin)** to initialize an elevated console workspace.
2. Navigate to your workspace directory:
   ```powershell
   cd C:\VPN_Manager\

```

3. Launch the script engine natively by executing the filename:
```powershell
.\WireGuardPanel.ps1

```



### Method B: Compiling the Executable Internally (Recommended for Distribution)

If you want to distribute a hardened, standalone `.exe` with a custom embedded icon to other administrators without worrying about local execution policies or floating script files, you can compile it yourself:

1. Open an elevated PowerShell terminal and install the community-standard compiler module:
```powershell
Install-Module -Name ps2exe -Force

```


2. Place your raw script and a multi-resolution `.ico` file (named `app_logo.ico`) into your working folder.
3. Execute the compiler command to build the binary wrapper:
```powershell
Invoke-ps2exe -inputFile ".\WireGuardPanel.ps1" -outputFile ".\WireGuardPanel.exe" -iconFile ".\app_logo.ico" -noConsole -requireAdmin

```



> [!NOTE]
> * **`-noConsole`**: Suppresses the background command prompt window so only your clean dashboard GUI appears.
> * **`-requireAdmin`**: Embeds an application manifest that forces Windows to prompt for UAC (User Account Control) elevation automatically when launched.
> 
> 

---

## Technical Breakdown: What the Selection Panels Enforce

The management console separates your orchestration capabilities into four distinct, tabbed interfaces. Here is the behavior profile and technical interaction of each screen:

```
+--------------------------------------------------------------------------+
|                 WireGuard Hybrid Administration Panel                    |
+--------------------------------------------------------------------------+
| [ Server Orchestration ] [ Add New Client ] [ Manage ] [ Live Dashboard ] |
+--------------------------------------------------------------------------+

```

### 1. Server Orchestration (The Infrastructure Foundation)

This screen controls the global state of the local WireGuard engine, network routing layers, and deployment lifecycle.

* **WireGuard Engine Status Label:** A live-updating tracker that monitors the host's Service Control Manager. It outputs `Active (Tunnel Live)` in green if the kernel service is running, or red warnings if the tunnel is dormant or missing.
* **Run Pre-Flight Check Button:** Intercepts your local application layer. It scans your system storage for the native WireGuard core files. If missing, it uses secure TLS 1.2 protocols to download the official MSI enterprise installer from `download.wireguard.com` and executes a silent, headless install.
* **Provision Infrastructure Button:** This button handles the heavy lifting of network plumbing.
* **Firewall Engineering:** It automatically injects an explicit inbound firewall security rule named `WireGuard-Server`, opening UDP port `51820`.
* **Routing Engine Rules:** It writes to the kernel registry to enable system IP routing (`IPEnableRouter = 1`) and enforces persistent connections over reboots.
* **The NAT Topology Selection:** The engine automatically detects your operating system's capabilities. If the server natively supports enterprise **NetNAT**, it binds a secure `10.10.0.0/24` internal network. If running on a Windows Server version requiring a legacy fallback, it invokes a fallback wrapper via **Internet Connection Sharing (ICS)**, routing traffic through an automatically assigned host alias network segment of `192.168.137.1`.


* **Nuclear Rollback Button (The Nuke Option):** This is your full systemic purge control. Clicking this prompts a critical warning interface. Upon confirmation, it gracefully tears down the running WireGuard background services, drops all underlying network card adapters, deletes local firewall exceptions, reverts IP routing registry hooks to default values, purges the `wg0.conf` configuration vault, and completely uninstalls the core WireGuard enterprise application tracks from the operating system registry.

### 2. Add New Client (Token Generation & Enrollment)

This workspace allows for the rapid creation and provisioning of new remote endpoints.

* **Profile Identifier Name Field:** Generates a randomized, tracking-safe naming string (e.g., `RemoteWorker_4892`) out of the box, which can be custom overwritten to match employee names or device tags.
* **Generate Client Profile Button:** When pressed, this module spins up a local execution loop:
1. It triggers a secure cryptographic private/public keypair calculation natively.
2. It leverages public API lookup loops (`api.ipify.org` / `icanhazip.com`) to discover your server's public WAN IP address. If the server is locked down without outbound internet access, it drops a manual input box prompting the admin for the WAN address or hostname.
3. It automatically calculates the next available incremental IP address slot in your subnet structure (e.g., `10.10.0.5`, `10.10.0.6`) by checking existing assets.
4. It dumps a structured client configuration block into your local `Clients` workspace directory as a `.conf` asset, appends the corresponding peer parameters to the server's central `wg0.conf` vault, and immediately passes the new routing tokens directly to the live kernel driver on-the-fly without interrupting existing users.



### 3. Manage Clients (Inventory & Revocation Control)

A central inventory index designed for lifecycle tracking and access management.

* **The Left Index List:** Dynamically reads the contents of your local `Clients` directory, populating a clean roster of every generated profile currently tracking in your administration landscape.
* **The Configuration Preview Window:** Clicking any user profile reads their local config file on-the-fly, displaying their explicit keys, assigned internal IP addresses, and Endpoint targets for verification.
* **Remove Selected Client Button:** Your instant revocation control. If an employee departs or a device is compromised, selecting their profile and hitting remove deletes their local profile file, dynamically rewrites the master server `wg0.conf` to strip their entry, and reaches straight into the active system kernel to instantly terminate their live handshake sessions.

### 4. Live Tunnel Dashboard (Kernel Monitoring Diagnostics)

Because the panel is designed for clean deployment, it operates independently of standard consumer desktop apps.

* **Query Live Kernel Diagnostics Button:** Bypasses basic file structures and queries the active WireGuard kernel driver via the native command line tool. It dumps live data packets directly into an integrated console view, revealing every single active peer, their verified public identifiers, their last known endpoint IP addresses, and exact real-time byte transfer rates.

---

## Coexistence with the WireGuard GUI Application

```
               [ Standalone Admin Panel Engine ]
                               |
            (Writes Central Tunnel Registries to Core Vault)
                               |
                               v
         Path -> C:\ProgramData\WireGuard\Data\Configurations
                               ^
                               |
         (Import config here to pair standard GUI app)
                               |
                  [ Official WireGuard GUI App ]

```

An important structural design detail of this orchestration panel is that **it does not need the official WireGuard user interface to run**. Because it registers the active tunnels directly as system-wide service components, all encryption, routing, and data processing run silently in the background before users log in.

However, if you or your security operations center prefer to visually track data transfer graphs or active handshakes using the standard developer application layout, you can easily bridge them:

1. Open the official **WireGuard GUI Application** on your Windows Server.
2. Select **Import tunnel(s) from file...** from the application import dropdown layout.
3. Path directly into the secure core configuration asset vault:
```
C:\ProgramData\WireGuard\Data\Configurations

```


4. Select the central `wg0.conf` file managed by the script.

Once imported, the developer application interface will pair perfectly with the running network adapters, giving you an alternative window to watch active connections while leaving the panel to safely automate your orchestration tasks.

```

```
