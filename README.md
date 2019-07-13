# [minutemen](https://github.com/egladman/minutemen)

Build/Provision dedicated minecraft servers with forge mod support in seconds. Platform/Device agnostic; written with cloud computing in mind, however you can just as easily run this on a SBC (Single Board Computer) with no modifications. It might run like shit, but hey...you can do it.

### Need to know
 
- Supports `Fedora` and `Ubuntu`.


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

*Modify the script to your heart's content...*
 

### Tips

1. Run the help utility for more info
```
./bootstrap.sh -h
```

2. If you add mods (i.e. `.jar`) to `/opt/minecraft/mods` be sure to set permissions
```
chown minecraft:minecraft /opt/minecraft/<uuid>/mods/*
```

3. Mods placed in `/opt/minecraft/.mods` will be automatically installed

4. If you're running multiple builds place the forge installer jar in `/opt/minecraft/.downloads` to reduce network activity

5. If you want to skip systemd and run the server manually you can
```
su - minecraft
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
 
