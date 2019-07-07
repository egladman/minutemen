# bootstrap-minecraft

Build/Provision dedicated minecraft servers with forge mod support in seconds. Platform/Device agnostic; written with cloud computing in mind, however you can run it on a SBC (Single Board Computer) with no modifications. Might run like shit, but you can do it.

### Need to know
 
- Currently only supports `ubuntu` and its derivatives. Planning to support Fedora in the near future. 


### Quick and Dirty

> curl | bash is indefensible. Just because the transport is over HTTPS doesn't guarantee the content hasn't been maliciously modified on the server. It also doesn't guarantee that you won't receive a partial download that happens to stop at some inopportune time. 

```
curl https://raw.githubusercontent.com/egladman/bootstrap-minecraft/master/bootstrap.sh | bash
```


### The Proper Way

```
git clone git@github.com:egladman/bootstrap-minecraft.git
cd bootstrap-minecraft
./bootstrap.sh
```

*Modify the script to your heart's content...*
 

### Tips

1. If you add mods (i.e. `.jar`) to `/opt/minecraft/mods` be sure to set permissions
```
chown minecraft:minecraft /opt/minecraft/mods/*
```

2. If you want to skip systemd and run the server manually you can
```
su - minecraft
/opt/minecraft/start.sh
```

3. View process details 
```
systemctl status minecraftd
ps aux | grep minecraft
```

4. View logs that would typically be printed to stdout
```
journalctl -u minecraftd.service
```
 
