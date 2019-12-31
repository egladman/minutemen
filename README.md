# [minutemen](https://github.com/egladman/minutemen)

Build/Provision dedicated minecraft servers with forge mod support in seconds. Platform/Device agnostic; written with cloud computing in mind, however you can just as easily run this on a SBC (Single Board Computer) with no modifications. It might run like shit, but hey...you can do it.

I began work on *minutemen* when I started hosting a small modded minecraft server for some friends and I. I was unimpressed with the current opensource offerings I found online so I decided to build my own. Most of the scripts/tutorials I found on forums/blogs either went against Linux best practices or went as far as suggesting `screen` in lieu of a proper init system. I found this solution to be unexceptable. Don't get me wrong, `screen` is great when used as a traditional multiplexer, but it's overkill for this particular use case. 


### Features

- Written 100% in Bash :muscle: Depends only on common Linux utilities; no additional languages required
- Designed to be rerunnable with no repercussions
- Supports `Fedora` and `Ubuntu`
- Supports Systemd
- Does **NOT** depend on `screen`; instead [named pipes](https://en.wikipedia.org/wiki/Named_pipe) are used
- Supports multiple concurrent minecraft servers on a single host


### Quick and Dirty

> curl | bash is indefensible. Just because the transport is over HTTPS doesn't guarantee the content hasn't been maliciously modified on the server. It also doesn't guarantee that you won't receive a partial download that happens to stop at some inopportune time. 

```
curl https://raw.githubusercontent.com/egladman/minutemen/master/bootstrap.sh | bash
```


### The Proper Way

```
git clone git@github.com:egladman/minutemen.git
cd minutemen
./bootstrap.sh -v
```

*Depending on your user priveleges you might need to prefix `./bootstrap.sh` with `sudo`. This will not be discussed any further since it's a fundamental concept for Unix-like operating systems.* 

*Modify the script to your heart's content...*
 

### Tips

1. Run the help utility for more info
```
./bootstrap.sh -h
```

2. If you add mods (i.e. `.jar`) to `/opt/minecraft/mods` be sure to set permissions
```
chown mminecraft:mminecraft /opt/minecraft/<uuid>/mods/*
```

3. Mods placed in `/opt/minecraft/.mods` will be automatically be installed

4. If you're running multiple builds place the forge installer jar in `/opt/minecraft/.downloads` to reduce network activity

5. If you want to skip systemd and run the server manually you can
```
su - mminecraft
/opt/minecraft/bin/start
```

6. View process details
```
systemctl status minutemen@<uuid>
ps aux | grep minecraft
```

7. View logs that would typically be printed to stdout
```
journalctl -u minutemen@<uuid>.service
```

8. Set password for user: `minecraft`
```
MC_USER_PASSWORD_HASH="" ./bootstrap.sh
```

To generate a password use the following command:
```
#Tested againt mkpasswd 5.5.3 on Fedora31
mkpasswd --method=sha512crypt mySuperSecretPassword
```
*Run `mkpasswd --method=help` to print all the available encryption algorthims. `SHA-512` is by far the strongest provided by `mkpasswd`. By default `mkpasswdd` salts the string.*

For example if you'd like user: `mminecraft` to have password: `HelloWorld` you'd do
```
mkpasswd --method=sha512crypt HelloWorld
$6$RN.HLGL5BosPQ2ZS$kVfGYi709anfOLAn7Hc18zwTfhRhwEcLfSMvhKl2yVU1wIJV4P4sJTheebx8BMpzr0HWl/cIsp3GK8FO670v9.
```

Then pass the hash into `bootstrap.sh` as an environment variable
```
MC_USER_PASSWORD_HASH='$6$RN.HLGL5BosPQ2ZS$kVfGYi709anfOLAn7Hc18zwTfhRhwEcLfSMvhKl2yVU1wIJV4P4sJTheebx8BMpzr0HWl/cIsp3GK8FO670v9.' ./bootstrap.sh
```

After the script executes, you can then authenticate as user: `mminecraft` with password: `HelloWorld`
```
su - mminecraft
```

9. Have you created a monster and don't know what to do?

Delete the main installation folder and rerun `bootstrap.sh`
```
rm -rf /opt/minecraft
```


 
