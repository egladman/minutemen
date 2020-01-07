# [minutemen](https://github.com/egladman/minutemen)

Build/Provision dedicated minecraft servers with forge mod support in seconds.

## How this project came to be

I began work on *minutemen* when I offered to host a small modded minecraft server for some friends and I. I was unimpressed with the current opensource offerings I found online so I decided to build my own. Most of the scripts/tutorials I found on forums/blogs either went against Linux best practices or went as far as suggesting `screen` in lieu of a named pipe and proper init system. I found these solutions to be unexceptable.


## Features

- Written 100% in Bash :muscle: Depends only on common Linux utilities; no additional languages required
- Designed to be rerunnable with no repercussions
- Built with security in mind
- Supports `Fedora` and `Ubuntu`. If your distro of choice isn't compatible make an issue.
- Utilizes Systemd
- Does **NOT** depend on `screen`; instead [named pipes](https://en.wikipedia.org/wiki/Named_pipe) are used
- Supports multiple concurrent minecraft servers on a single host
- Supports multiple versions of ForgeMod. Each instance can run a different version.


## Installaton

### Quick and Dirty

> curl | bash is indefensible. Just because the transport is over HTTPS doesn't guarantee the content hasn't been maliciously modified on the server. It also doesn't guarantee that you won't receive a partial download that happens to stop at some inopportune time. 

```
curl https://raw.githubusercontent.com/egladman/minutemen/master/bootstrap.sh | bash
```


### The Proper Way

```
git clone git@github.com:egladman/minutemen.git
cd minutemen
./bootstrap.sh -v -e 28.1.0
```

**Note:** Checkout `manifest.json` to see all supported forgemod versions. Other versions can be added with minimum effort. 


## Tips and Tricks

1. Run the help utility for more info
```
./bootstrap.sh -h
```

2. Override jvm max heap size in megabytes
```
./bootstrap.sh -m 4096M
```

3. Have you created a monster and don't know what to do?

Delete the main installation folder and rerun `bootstrap.sh`
```
rm -rf /opt/minecraft
```

4. Kill instance

**Warning:** You run the risk of data loss. Can you use `systemctl stop minutemen@<uuid>`?

```
systemctl kill -s SIGKILL minutemen@<uuid>
```

5. If you're running multiple builds place the forge installer jar in `/opt/minecraft/.cache` to reduce network activity. The `.jar` is cached after the first install.


## Configuration

### Mods

1. If you add mods (i.e. `.jar`) to `/opt/minecraft/instances/<uuid>/mods` or `/opt/minecraft/.forgemods` be sure to set permissions
```
chown -R mminecraft:mminecraft /opt/minecraft/.forgemods
# or
chown -R mminecraft:mminecraft /opt/minecraft/instances/<uuid>/mods/
```

2. Mods placed in `/opt/minecraft/.forgemods` will be automatically be installed


### Password

1. Generate a password with the following command:
```
#Tested againt mkpasswd 5.5.3 on Fedora31
mkpasswd --method=sha512crypt mySuperSecretPassword
```

**Tip:** Run `mkpasswd --method=help` to print all the available encryption algorthims. `SHA-512` is by far the strongest provided by `mkpasswd`.


2. For example if you'd like user: `mminecraft` to have password: `HelloWorld` you'd run:
```
mkpasswd --method=sha512crypt HelloWorld
```

`mkpasswd` will return the following:
```
$6$RN.HLGL5BosPQ2ZS$kVfGYi709anfOLAn7Hc18zwTfhRhwEcLfSMvhKl2yVU1wIJV4P4sJTheebx8BMpzr0HWl/cIsp3GK8FO670v9.
```

**Note:** By default `mkpasswd` salts the string. So each time you run `mkpasswd` you'll get a different hash by design.


3. Pass the hash into `bootstrap.sh` as an environment variable
```
MC_USER_PASSWORD_HASH='$6$RN.HLGL5BosPQ2ZS$kVfGYi709anfOLAn7Hc18zwTfhRhwEcLfSMvhKl2yVU1wIJV4P4sJTheebx8BMpzr0HWl/cIsp3GK8FO670v9.' ./bootstrap.sh
```


## Logging

1. The forge installer stdout is saved to `/opt/minecraft/log/<uuid>`

2. View process details
```
systemctl status minutemen@<uuid>
```

3. View logs that would typically be printed to stdout
```
journalctl -u minutemen@<uuid>.service -f
```


## Console Commands

To run the following commands you'll need to authenticate as `mminecraft`
```
su - mminecraft
```

```
/opt/minecraft/bin
├── backup
├── backup-restore
├── cmd
├── save
├── start
└── stop
```

1. `backup`
  - Summary: Copies `/opt/minecraft/instances/<uuid>` directory and saves it to `/opt/minecraft/backups/<uuid>` as `<epoch-time>.tar.gz` 
  - Example: `/opt/minecraft/bin/backup <uuid>`

2. `backup-restore`
  - Summary: Recover from backup.
  - Example: `/opt/minecraft/bin/backup-restore <uuid> <epoch-time>`

3. `cmd`
  - Summary: Execute any console command. See full list [here](https://minecraft.gamepedia.com/Commands) 
  - Example: `/opt/minecraft/bin/cmd <uuid> say HELLO`

4. `save`
  - Summary: Executes console command `save-all flush`.
  - Example: `/opt/minecraft/bin/save <uuid>`
 
5. `start`
  - Summary: Skip systemd and run the server manually
  - Example: `/opt/minecraft/bin/start <uuid>`
  
6. `stop`
  - Summary: Executes console command `stop`
  - Example: `/opt/minecraft/bin/stop <uuid>`
