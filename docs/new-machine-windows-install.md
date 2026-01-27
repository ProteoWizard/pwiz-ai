# New Machine: Windows Installation

This guide covers clean Windows installation and initial configuration for development workstations. Written for Dell Precision 3680 systems using Windows Enterprise from IT, but Part 2 applies to any new Windows machine.

**New computers with Windows pre-installed can skip directly to [Part 2: Initial Windows Configuration](#part-2-initial-windows-configuration).**

---

## Part 1: Clean Windows Installation

Use these steps when re-installing Windows on an existing system. Dell Precision-specific.

### BIOS Configuration (F2 at boot)

1. **Storage** → Set SATA/NVMe Operation to **AHCI/NVMe** (not RAID)
   - Windows installer won't see the NVMe drive if set to RAID mode
2. **Security** → Disable **Secure Boot** (if needed for your install media)
3. **Save and Exit**

### Boot from USB Installer (F12 at boot)

1. Insert the IT department Windows Enterprise installer flash drive
2. Press **F12** repeatedly during startup to access the one-time boot menu
3. Select **UEFI Generic Mass Storage** (this is the USB drive)

### Windows Installation

1. Proceed through language/keyboard selection
2. At "Select location to install Windows 11":
   - Identify your target NVMe drive (typically ~1TB or ~2TB, labeled "Disk 0")
   - **Delete all partitions** on the target drive only
   - Avoid deleting partitions on secondary data drives (e.g., 7TB spinning disk)
   - The USB installer shows as "CPBA_X64FRE_EN-US_DV9" — leave it alone
3. Select the resulting **Unallocated Space** on your target drive
4. Click **Next** — Windows creates partitions automatically
5. Wait for installation to complete (system will reboot several times)
   - Do not boot from USB again after the first reboot

### BIOS Update (Recommended)

Updating the BIOS prevents potential firmware update loops on these machines.

1. Once in Windows, open a browser
2. Go to **https://www.dell.com/support**
3. Enter the **Service Tag** (found on case sticker or in BIOS Overview)
4. Navigate to **Drivers & Downloads** → **BIOS**
5. Download and run the latest BIOS .exe file
6. Follow prompts — system will reboot to flash the update

---

## Part 2: Initial Windows Configuration

These steps apply to any new Windows machine — clean install or factory-fresh.

### Sign In and Set Password

1. Sign in with your Microsoft account or domain credentials
2. Change password if needed: **Settings → Accounts → Sign-in options**

### Rename Computer

1. **Settings → System → About → Rename this PC**
2. Enter the desired machine name
3. Restart when prompted

### Enable Remote Desktop

1. **Settings → System → Remote Desktop**
2. Toggle Remote Desktop to **On**
3. Confirm when prompted
4. Note the PC name displayed for future connections

### Configure Power Settings

Critical for remote access — prevents the machine from sleeping and becoming unreachable.

1. **Settings → System → Power**
2. Set Power mode to **Best performance**
3. Set "Turn off my screen after" to **30 minutes**
4. Set "Make my device sleep after" to **Never**

---

## Verification

From your primary computer:

1. Open Remote Desktop Connection
2. Connect to the new machine by name
3. Confirm you can log in successfully

---

## Next Steps

The workstation is now ready for development environment setup. Continue with:

**[new-machine-bootstrap.md](new-machine-bootstrap.md)** — Install Git and Claude Code, then let AI guide the rest of the setup.

---

## Troubleshooting

### NVMe drive not visible in Windows installer
- Boot into BIOS (F2) and verify Storage is set to **AHCI/NVMe**, not RAID

### F12 boot menu not appearing
- Disable **Fast Boot** in BIOS if enabled
- Try holding F12 before the Dell logo appears

### Firmware update stuck at 0%
- Force restart (hold power button 10+ seconds)
- In BIOS → **Update,Recovery**: disable **UEFI Capsule Firmware Updates** and **BIOS Recovery from Hard Drive**
- Boot into Windows and run a manual BIOS update from Dell's support site
- Re-enable the update options afterward if desired

### BIOS time/date errors after restart
- Go to BIOS → **Integrated Devices** → set correct **Date/Time**
- Or boot into Windows and let it sync time automatically via internet
