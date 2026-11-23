# Active Directory & PowerShell Automation Lab — Build, Attack, Detect & Respond

> I built a full Windows Server 2025 Active Directory environment, automated
> 150+ users with PowerShell, hardened it with Group Policy, then ran real
> attacks against it and **detected, cracked, and fixed** every one — proving the
> fixes held.

**Author:** Opeyemi Ajadi · MS Cybersecurity (Lewis University) · CompTIA Security+ · Microsoft SC‑200

---

### In plain English (for any reader)

Think of a company's computer network as an office building, where one central
system is the front desk, the security office, and the master-key system all at
once.

In this project I built that building from scratch, then tested how well it's
protected:

- **Set up the "front desk"** — the server that knows every employee and controls
  which doors their badge opens (this is *Active Directory*).
- **"Hired" 152 employees automatically** with a script, instead of typing each
  one in by hand — the kind of time-saving automation real IT teams rely on.
- **Set company security rules** — strong passwords, locked file rooms, no USB
  sticks, limited settings for regular staff.
- **Became the burglar** — tried one common password on every door at once, and
  copied a spare key that used a weak, old-style lock. Both worked.
- **Became the security guard** — pulled the building's "camera footage" (the
  system logs) and proved I could spot both break-ins.
- **Fixed the weak spots** and ran the exact same break-ins again — this time they
  failed.

In one sentence: **I built a realistic company network, broke into it, caught
myself doing it, and then made it secure** — which is exactly what IT security
teams do for a living. Everything ran in a sealed-off lab, so no real systems
were touched.

---

## Contents
1. [What makes this more than a basic AD lab](#what-makes-this-more-than-a-basic-ad-lab)
2. [Skills demonstrated](#skills-demonstrated)
3. [Architecture](#architecture)
4. [Part 1 — Build the domain](#part-1--build-the-domain)
5. [Part 2 — Automate 150+ users with PowerShell](#part-2--automate-150-users-with-powershell)
6. [Part 3 — Harden with Group Policy](#part-3--harden-with-group-policy)
7. [Part 4 — Instrument for detection](#part-4--instrument-for-detection)
8. [Part 5 — Attack, detect & respond](#part-5--attack-detect--respond)
9. [Part 6 — Attack-path mapping with BloodHound](#part-6--attack-path-mapping-with-bloodhound)
10. [What broke and how I fixed it](#what-broke-and-how-i-fixed-it)
11. [Key takeaways](#key-takeaways)
12. [Future work](#future-work)

---

## What makes this more than a basic AD lab

Most "Active Directory home lab" tutorials stop at three steps: install AD,
bulk-create users with a simple loop, join one client. That shows you can follow
a wizard. I built this lab to show something harder — that I can **run and defend
a domain the way a real IT and security team does.**

| Area | Typical AD home lab | **This lab** |
|---|---|---|
| **User creation** | A loop making `user1`…`user150` | CSV-driven onboarding: departments, OUs, security groups, job titles, manager chains, forced password change — and the script is re-runnable without creating duplicates |
| **Group Policy** | None, or one password policy | Password/lockout, group-targeted drive maps, USB blocking, Control Panel restriction with an IT exemption — **each one verified by testing**, not just set |
| **Security logging** | Not addressed | Full audit + PowerShell logging configured **before** any attack, so attacks leave evidence |
| **Attacks** | None | Password spraying and Kerberoasting, run from an ordinary (non-admin) user |
| **Detection** | None | **Hand-written detections** for each attack (spray = 4625 pattern, Kerberoast = 4769 RC4) |
| **Response** | None | Weaknesses fixed, then the **same attacks re-run to prove they now fail** |
| **Attack surface** | Unknown | Mapped with BloodHound (276 objects) |
| **Documentation** | A few screenshots | Full write-up with a real troubleshooting log |

In short: a typical lab proves you can *set up* a domain. This one proves I can
**attack it, catch the attack, and fix it** — the loop a SOC analyst works in
every day.

### Before vs. after — measurable improvement

The clearest way to prove a system is "better" is to measure it before and after.
I ran each attack against the domain, then hardened it and ran the **identical**
attack again:

| Weakness | Before hardening | After hardening |
|---|---|---|
| **Password spraying** | 2 accounts compromised, no alert | **0 compromised**, detection alert fires |
| **Kerberoasting** | Weak RC4 ticket cracked to the real password (`P@ssw0rd2026`) | **AES-256 ticket — not crackable** |
| **Attacker visibility** | Little useful logging | Full audit trail + 1 GB Security log + PowerShell logging |
| **Service account** | Weak, static password | Strong 30-char password, AES-only (gMSA recommended) |

Same environment, same attacks — the only thing that changed is the hardening and
detection I added. That before/after evidence is the heart of the project.

---

## Skills demonstrated

- **Windows Server:** AD DS, DNS, DHCP, RRAS/NAT, OU design, delegation, file
  shares with share + NTFS permissions.
- **PowerShell automation:** bulk account creation from CSV, idempotent scripting,
  secure password generation, AD queries and clean-up.
- **Group Policy:** password/lockout policy, drive mapping with item-level
  targeting, removable-storage control, Control Panel restriction with a
  group exemption.
- **Detection engineering:** audit policy, PowerShell script-block logging, and
  custom detections for spraying (4625) and Kerberoasting (4769).
- **Offensive security:** password spraying, Kerberoasting, offline hash cracking
  (Rubeus + John the Ripper), BloodHound/SharpHound.
- **Incident response:** service-account hardening (AES-only + strong password),
  account recovery, endpoint-protection management.
- **Troubleshooting:** a documented trail of real problems solved along the way.

---

## Architecture

| Host | Role | OS | Network |
|---|---|---|---|
| **DC01** | Domain Controller (AD DS, DNS, DHCP, RRAS/NAT) | Windows Server 2025 | NAT (internet) + Internal `172.16.0.1/24` |
| **CLIENT1** | Domain member | Windows Server 2025¹ | Internal only — `172.16.0.100` (DHCP) |

¹ *The client was planned as Windows 11 Pro, but that VM would not boot on this
host under VirtualBox (see [What broke](#what-broke-and-how-i-fixed-it)). I used
Server 2025 as the client instead — it shows the same skills: DHCP lease, NAT
internet, domain join, and domain-user logon.*

| Network item | Value |
|---|---|
| Domain | `mydomain.com` (`MYDOMAIN`) |
| Internal subnet | `172.16.0.0/24`, gateway/DNS `172.16.0.1` (DC01) |
| DHCP scope | `172.16.0.100–200`, 8-day lease |
| Internet path | CLIENT1 → DC01 RRAS NAT → host (fully isolated from any real network) |

> **Isolation:** CLIENT1 has only an *Internal Network* adapter, so it can reach
> nothing but DC01. No attack traffic can leave the lab.

---

## Part 1 — Build the domain

Deployed **DC01** on Server 2025 with two network adapters, a static internal IP,
and promoted it to a new forest:

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "mydomain.com" -DomainNetbiosName "MYDOMAIN" -InstallDns
```

I used a dedicated admin account (`a-oajadi`) rather than the built-in
Administrator, installed **RRAS/NAT** so the isolated client could reach the
internet through DC01, and set up **DHCP** to hand out addresses automatically.

![Domain promoted](screenshots/04-get-addomain-mydomain.png)
![DHCP scope and options](screenshots/09b-dhcp-scope-and-options-clean.png)
![NAT translating client traffic](screenshots/26-rras-nat-mappings.png)

---

## Part 2 — Automate 150+ users with PowerShell

Instead of a throwaway `user1..user150` loop, I wrote a realistic onboarding
script, `Create-LabUsers.ps1`, that reads a CSV and builds a believable company:

- A per-department **OU** and a `GRP-<Dept>` **security group** for each.
- Usernames as *first-initial + surname*, with automatic de-duplication.
- **Department, Title, Company** filled in, a **random temporary password**, and
  **change-at-next-logon** forced.
- **Idempotent** — safe to run again; existing accounts are skipped.

**Result: 152 users across 7 departments**, with an Executive team and
manager → direct-report links.

| Dept | Users | Dept | Users |
|---|---|---|---|
| Sales | 35 | Finance | 25 |
| Operations | 30 | Marketing | 20 |
| IT | 25 | HR | 15 |
| Executive | 2 | | |

![Script output — 152 created, 0 failed](screenshots/11-create-labusers-output.png)
![Department OUs and users](screenshots/12-aduc-employees-finance-ou.png)
![Executive reporting line](screenshots/14-aduc-coo-org-chart.png)

I then built **CLIENT1**, confirmed it got `172.16.0.100` from DHCP and reached
the internet through DC01's NAT, joined it to the domain, and logged in as a
domain user — whose temporary password was correctly forced to change at first
logon.

![Welcome to the domain](screenshots/18-client1-domain-join-welcome.png)
![Domain user logon + group membership](screenshots/22-domain-user-whoami-groups.png)

---

## Part 3 — Harden with Group Policy

| GPO | Scope | Effect |
|---|---|---|
| **Default Domain Policy** | Domain | 12-char complex passwords; lockout after 5 tries for 15 min |
| **EMP – Drive Mappings** | `_EMPLOYEES` | `S:` for everyone; `F:` (Finance) only for Finance + Executive groups, via item-level targeting |
| **WKS – Block USB Storage** | `_WORKSTATIONS` | Denies all removable storage |
| **EMP – Restrict Control Panel** | `_EMPLOYEES` | Blocks Control Panel — **IT staff exempted** with a *Deny – Apply group policy* on `GRP-IT` |

Each policy was **proven by testing**, not just configured. A Sales user gets
only `S:` and is denied the Finance share; an Executive gets both. A non-IT user
can't open Control Panel; an IT user can.

![Finance share denied for Sales user](screenshots/39-sales-user-finance-access-denied.png)
![USB storage blocked](screenshots/42-client1-gpresult-usb-applied.png)
![Control Panel blocked for Sales user](screenshots/45b-sales-user-control-panel-blocked-whoami.png)
![IT user exempt — Control Panel opens](screenshots/47-it-user-gpresult-denied-security.png)

I also tested the **lockout policy**: five bad logons locked the account, which
produced **Event 4740** naming the account and source machine — then unlocked it
like a help-desk tech would.

![Lockout event 4740](screenshots/32-lockout-verified-event-4740.png)

---

## Part 4 — Instrument for detection

Before attacking, I turned the DC into a sensor:

- **Advanced Audit Policy** (Success + Failure) for logon, lockout, Kerberos, and
  account-management events.
- **PowerShell Script-Block Logging** (Event 4104) to capture attacker scripts.
- **Security log raised to 1 GB** so an attack can't flood out the evidence.

This produces the key events used later: **4625** (failed logon), **4769**
(service-ticket request), **4740** (lockout), **4104** (PowerShell).

![Advanced audit policy](screenshots/48-auditpol-advanced-audit-enabled.png)
![1 GB Security log + script-block logging](screenshots/49-security-log-1gb-pslogging.png)

I then planted two realistic weaknesses to attack:

- A **service account** (`svc-sql`) with a weak password (`P@ssw0rd2026`) — a
  Kerberoasting target.
- Two users (`psanchez`, `aadeyemi`) sharing a seasonal password (`Autumn2026!!`)
  — password-spray targets.

![Planted weaknesses](screenshots/50-planted-weaknesses-spn-spray-targets.png)

---

## Part 5 — Attack, detect & respond

### Attack 1 — Password spraying

A spray tries **one** password against **every** account — one attempt each, so
nothing locks out. From CLIENT1, as an ordinary user, I sprayed `Autumn2026!!`.

**Attack:** two accounts compromised, **zero lockouts.**

![Spray — valid credentials found](screenshots/51-password-spray-hits.png)

**Detect:** my PowerShell detection flagged the signature — **157 failed logons
(4625) across 155 accounts from one machine** in seconds. "One source, many
accounts, few failures each" is the spray fingerprint.

![Spray detection fires](screenshots/52-spray-detection-4625-alert.png)

**Respond:** reset both accounts to strong passwords. The same spray now returns
**zero hits.**

![Spray re-run — no hits](screenshots/65-remediation-spray-no-hits.png)

### Attack 2 — Kerberoasting

Any user can ask for a service account's Kerberos ticket, which is encrypted with
that account's password — crackable **offline**, with no further contact with the
DC.

**Attack:** `svc-sql`'s ticket came back as weak **RC4**.

![RC4 service ticket](screenshots/53-kerberoast-ticket-rc4.png)

**Detect:** **Event 4769** for `svc-sql` with **encryption type 0x17 (RC4)** — the
classic Kerberoast flag.

![Kerberoast detection 4769](screenshots/54-kerberoast-detection-4769-rc4.png)

**Crack:** extracted the hash with Rubeus and cracked it with John the Ripper:

```
svc-sql : P@ssw0rd2026   (krb5tgs, etype 23 / RC4)
```

![Hash cracked](screenshots/57-kerberoast-cracked-password.png)

**Respond:** gave `svc-sql` a 30-character random password and forced **AES-only**
encryption (`msDS-SupportedEncryptionTypes = 24`). The ticket now comes back as
**AES-256** — nothing weak left to crack.

![svc-sql AES-only](screenshots/64-remediation-svcsql-aes.png)
![Kerberoast re-run — AES-256 ticket](screenshots/66-remediation-kerberoast-aes.png)

> *Best-practice fix:* a **gMSA** (group managed service account) with a
> 120-char auto-rotating password. The strong-password + AES-only approach here
> defeats the same attack and is simpler to show.

### Endpoint protection caught the tools

Windows Defender **blocked both offensive tools** (Rubeus, SharpHound) on
download — a reminder that endpoint protection is a real obstacle, and that
turning off AV is itself a red-flag event a SOC watches for. (I lowered it
deliberately and temporarily to stage the lab, then turned it back on.)

![Defender blocks Rubeus](screenshots/55-defender-smartscreen-blocks-rubeus.png)
![Defender blocks SharpHound](screenshots/58-defender-blocks-sharphound.png)

---

## Part 6 — Attack-path mapping with BloodHound

Using **SharpHound**, an ordinary user mapped the **entire domain — 276 objects**
(users, groups, computers, permissions, trusts) in under a minute. I loaded it
into **BloodHound 4.3.1** and reviewed:

- **Domain Admins** — who holds the keys.
- **Kerberoastable accounts** — BloodHound surfaced `svc-sql` on its own, the same
  account I'd already cracked.
- **DCSync rights** — who could dump every password hash; here, correctly limited
  to top-tier admins and the DC.

![SharpHound — 276 objects](screenshots/59-sharphound-collection-complete.png)
![Domain Admins graph](screenshots/61-bloodhound-domain-admins.png)
![Kerberoastable — svc-sql](screenshots/62-bloodhound-kerberoastable-svcsql.png)
![DCSync rights](screenshots/63-bloodhound-dcsync-rights.png)

Because the domain was built cleanly, there were no hidden escalation paths to
Domain Admin — which is the point: a tidy domain gives attackers few routes.

---

## What broke and how I fixed it

Real labs don't go perfectly. The troubleshooting is part of the value.

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | Setup looped to "booted from installation media" | VM rebooted mid-install and booted the ISO again | Ejected the ISO; setup resumed from disk |
| 2 | VM clock 2 hours off | Server defaulted to Pacific time | `Set-TimeZone` to Central (Kerberos and logs need correct time) |
| 3 | DHCP error "scope 172.10.0.0" | Typo (172.10 vs 172.16) | Read the error, re-ran with the right scope |
| 4 | Windows 11 client VM wouldn't boot | VM firmware hang on this host (EFI/TPM/Secure Boot) | Used Server 2025 as the client — same skills shown |
| 5 | GPO named "…Control Panle" | Typo | Renamed; link and delegation unaffected |
| 6 | hashcat: "No OpenCL/CUDA device" | No GPU in the VM | Switched to John the Ripper (CPU) |
| 7 | John: "No password hashes loaded" | Hash wrapped across lines **and** the SPN's `:1433` broke John's field parsing | Joined the hash to one line and removed the port |
| 8 | Wrong Java / Neo4j for BloodHound 4.3.1 | Download pages only offer newest versions | Pinned JDK 11 + Neo4j 4.4.18 |
| 9 | Defender deleted tool downloads | Real-time protection | Temporary exclusion, then restored protection |
| 10 | `klist purge` printed usage text | Java's `klist.exe` shadowed Windows' on PATH after the JDK install | Called `C:\Windows\System32\klist.exe` by full path |

---

## Key takeaways

- **Lockout policy alone doesn't stop password spraying** — you catch it by
  spotting the *pattern* (one source, many accounts).
- **Service accounts are prime targets.** A weak, RC4 service password cracks
  offline with zero noise. AES-only + strong/managed passwords close it.
- **Logging comes first.** Every detection here depended on audit policy set up
  *before* the attack.
- **Defense in depth works:** endpoint protection, audit logs, least-privilege
  shares, and Group Policy each caught or contained a different part of the chain.
- **The full loop matters.** Attacking is half the job — detecting it from logs
  and proving the fix is what a SOC analyst actually does.

---

## Future work

- **Microsoft Sentinel (Part 2 — coming next):** forward DC01's logs to a cloud
  SIEM and rewrite these detections as **KQL** analytics rules (SC‑200 skills).
- **gMSA** for the service account, with automatic password rotation.
- A tiered-admin model and a larger client fleet.

---

*All activity was performed in an isolated, self-owned lab for educational
purposes. No production or third-party systems were involved.*
